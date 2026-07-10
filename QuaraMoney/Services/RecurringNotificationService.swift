import Foundation
import UserNotifications
import SwiftData

/// Schedules a local reminder on each recurring rule's `nextDueDate` so the
/// user knows to review (confirm-before-post) the upcoming charge.
///
/// One pending request per rule, keyed `recurring_<ruleID>`, fired at
/// `reminderHour` local time on the due day (non-repeating — the next period's
/// reminder is (re)scheduled when the rule advances). Reminders honor
/// `remindersEnabled`, `isActive`, `deletedAt` and `endDate`, and are silently
/// skipped when notification authorization is missing.
enum RecurringNotificationService {

    private static let identifierPrefix = "recurring_"
    static let categoryIdentifier = "RECURRING_DUE"
    /// Hour of the due day at which the reminder fires (local time).
    private static let reminderHour = 9

    // Action identifiers handled by `AppDelegate` (the notification delegate).
    // Post/Skip run in the background (no `.foreground`) so the user can act
    // straight from the banner; Review opens the app on the Recurring screen.
    static let postActionIdentifier = "RECURRING_POST"
    static let skipActionIdentifier = "RECURRING_SKIP"
    static let reviewActionIdentifier = "RECURRING_REVIEW"

    static func identifier(for ruleID: UUID) -> String { identifierPrefix + ruleID.uuidString }

    /// The `RECURRING_DUE` category with Post / Skip / Review actions. Registered
    /// app-wide alongside the budget categories (a single `setNotificationCategories`
    /// call owns the whole set).
    static var dueCategory: UNNotificationCategory {
        let post = UNNotificationAction(identifier: postActionIdentifier, title: L10n.Recurring.post, options: [])
        let skip = UNNotificationAction(identifier: skipActionIdentifier, title: L10n.Recurring.skip, options: [.destructive])
        let review = UNNotificationAction(identifier: reviewActionIdentifier, title: L10n.Recurring.Review.title, options: [.foreground])
        return UNNotificationCategory(identifier: categoryIdentifier, actions: [post, skip, review], intentIdentifiers: [], options: [])
    }

    /// Mirror the count of currently-due rules onto the app-icon badge. No-ops
    /// (via `try?`) when badge authorization is missing.
    @MainActor
    static func refreshBadgeCount(in context: ModelContext) async {
        let due = RecurringRuleService.dueRules(in: context).count
        try? await UNUserNotificationCenter.current().setBadgeCount(due)
    }

    // MARK: - Authorization

    /// Request notification permission (drive from a user action, e.g. the
    /// reminders toggle). Returns whether it was granted.
    @MainActor
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            #if DEBUG
            print("RecurringNotificationService auth error: \(error)")
            #endif
            return false
        }
    }

    @MainActor
    private static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    // MARK: - Snapshot

    /// Value snapshot of the fields a reminder needs. Captured **synchronously
    /// while the model is alive** so scheduling work never touches a
    /// `RecurringRule` after a suspension point.
    ///
    /// Why this exists: the old fire-and-forget pattern
    /// (`Task { await reschedule(for: rule) }`) suspended at the authorization
    /// check and then read the model's fields on resume. Any reschedule that
    /// outlived the rule's `ModelContainer` — e.g. a test's per-case in-memory
    /// container, or a future short-lived background context — crashed with
    /// "This model instance was destroyed by calling ModelContext.reset"
    /// (SwiftData/BackingData.swift:835), killing the whole process.
    struct ReminderSnapshot: Sendable {
        let id: UUID
        let name: String
        let amount: Decimal
        let currencyCode: String
        let nextDueDate: Date
        let endDate: Date?
        /// isActive && not soft-deleted && remindersEnabled at capture time.
        let wantsReminder: Bool

        init(_ rule: RecurringRule) {
            id = rule.id
            name = rule.name
            amount = rule.amount
            currencyCode = rule.currencyCode
            nextDueDate = rule.nextDueDate
            endDate = rule.endDate
            wantsReminder = rule.isActive && rule.deletedAt == nil && rule.remindersEnabled
        }
    }

    // MARK: - Scheduling

    /// Remove a single rule's pending reminder (call on delete/pause/disable).
    @MainActor
    static func cancel(for ruleID: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(for: ruleID)])
    }

    /// Fire-and-forget reschedule: snapshots the rule synchronously, then does
    /// the async notification-center work with **no model references**. This is
    /// the only safe way to reschedule without awaiting the result — the task
    /// may outlive the rule's ModelContainer.
    @MainActor
    static func rescheduleDetached(for rule: RecurringRule) {
        let snapshot = ReminderSnapshot(rule)
        Task { await reschedule(snapshot: snapshot) }
    }

    /// Re-create a single rule's reminder to match its current state. No-ops
    /// (after clearing) when the rule is paused/deleted/reminders-off, the next
    /// due date is past its end date, or the fire time has already passed.
    /// The snapshot is taken before the first suspension point, so the model is
    /// never touched after an await.
    @MainActor
    static func reschedule(for rule: RecurringRule) async {
        await reschedule(snapshot: ReminderSnapshot(rule))
    }

    @MainActor
    private static func reschedule(snapshot: ReminderSnapshot) async {
        cancel(for: snapshot.id)
        guard snapshot.wantsReminder else { return }
        guard await isAuthorized() else { return }
        await scheduleRequest(for: snapshot)
    }

    /// Rebuild every recurring reminder from scratch (call on launch). Clears
    /// only our own pending requests so the daily/budget reminders are untouched.
    @MainActor
    static func rescheduleAll(in context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard await isAuthorized() else { return }
        let descriptor = FetchDescriptor<RecurringRule>(
            predicate: #Predicate { $0.isActive && $0.deletedAt == nil }
        )
        let rules = (try? context.fetch(descriptor)) ?? []
        // Snapshot + count synchronously, before the per-rule awaits, so no
        // model is read after a suspension point (same crash class as above).
        let snapshots = rules.filter(\.remindersEnabled).map(ReminderSnapshot.init)
        let dueCount = rules.filter { RecurringRuleService.isDue($0) }.count

        for snapshot in snapshots {
            await scheduleRequest(for: snapshot)
        }
        // Keep the app-icon badge in step with what's actually due.
        try? await UNUserNotificationCenter.current().setBadgeCount(dueCount)
    }

    // MARK: - Helpers

    @MainActor
    private static func scheduleRequest(for snapshot: ReminderSnapshot) async {
        guard let fireDate = fireDate(for: snapshot), fireDate > Date() else { return }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: snapshot.id),
            content: makeContent(for: snapshot),
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// `reminderHour` on the due day, or `nil` if the next due date is past the
    /// rule's end date.
    private static func fireDate(for snapshot: ReminderSnapshot) -> Date? {
        if let end = snapshot.endDate, snapshot.nextDueDate > end { return nil }
        let cal = Calendar.current
        let day = cal.startOfDay(for: snapshot.nextDueDate)
        return cal.date(byAdding: .hour, value: reminderHour, to: day)
    }

    private static func makeContent(for snapshot: ReminderSnapshot) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = L10n.Recurring.Reminder.title
        content.body = L10n.Recurring.Reminder.body(snapshot.name, snapshot.amount.formattedAmount(for: snapshot.currencyCode))
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = ["recurringRuleID": snapshot.id.uuidString]
        return content
    }
}
