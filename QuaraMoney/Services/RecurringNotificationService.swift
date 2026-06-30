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
    private static let categoryIdentifier = "RECURRING_DUE"
    /// Hour of the due day at which the reminder fires (local time).
    private static let reminderHour = 9

    static func identifier(for ruleID: UUID) -> String { identifierPrefix + ruleID.uuidString }

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

    // MARK: - Scheduling

    /// Remove a single rule's pending reminder (call on delete/pause/disable).
    @MainActor
    static func cancel(for ruleID: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(for: ruleID)])
    }

    /// Re-create a single rule's reminder to match its current state. No-ops
    /// (after clearing) when the rule is paused/deleted/reminders-off, the next
    /// due date is past its end date, or the fire time has already passed.
    @MainActor
    static func reschedule(for rule: RecurringRule) async {
        cancel(for: rule.id)
        guard rule.isActive, rule.deletedAt == nil, rule.remindersEnabled else { return }
        guard await isAuthorized() else { return }
        await scheduleRequest(for: rule)
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
        for rule in rules where rule.remindersEnabled {
            await scheduleRequest(for: rule)
        }
    }

    // MARK: - Helpers

    @MainActor
    private static func scheduleRequest(for rule: RecurringRule) async {
        guard let fireDate = fireDate(for: rule), fireDate > Date() else { return }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: rule.id),
            content: makeContent(for: rule),
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// `reminderHour` on the due day, or `nil` if the next due date is past the
    /// rule's end date.
    private static func fireDate(for rule: RecurringRule) -> Date? {
        if let end = rule.endDate, rule.nextDueDate > end { return nil }
        let cal = Calendar.current
        let day = cal.startOfDay(for: rule.nextDueDate)
        return cal.date(byAdding: .hour, value: reminderHour, to: day)
    }

    private static func makeContent(for rule: RecurringRule) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = L10n.Recurring.Reminder.title
        content.body = L10n.Recurring.Reminder.body(rule.name, rule.amount.formattedAmount(for: rule.currencyCode))
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = ["recurringRuleID": rule.id.uuidString]
        return content
    }
}
