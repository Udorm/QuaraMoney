import UIKit
import UserNotifications
import SwiftData

final class AppDelegate: NSObject, UIApplicationDelegate {

    enum ShortcutType {
        static let addTransaction = "com.quaramoney.add-transaction"
    }

    // Stores a shortcut action so HomeView can act on it after onAppear.
    static var pendingShortcutType: String?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.shortcutItems = [
            UIApplicationShortcutItem(
                type: ShortcutType.addTransaction,
                localizedTitle: "Add Transaction",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "plus.circle.fill")
            )
        ]

        // Own notification responses (Post / Skip / Review on recurring reminders,
        // and surfacing budget alerts in-foreground). Must be set before any
        // notification is delivered.
        UNUserNotificationCenter.current().delegate = self

        // Register the background re-arm task before launch completes.
        RecurringBackgroundRefresh.register()

        return true
    }

    // Route all scene connections through SceneDelegate so that
    // windowScene(_:performActionFor:) is called on our class instead of
    // SwiftUI's internal delegate (which doesn't handle quick actions).
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

// MARK: - Notification handling

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// Show recurring/budget banners even while the app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle taps and action buttons. Recurring Post/Skip mutate in the
    /// background (no app launch needed); Review / a plain tap routes the user
    /// to the Recurring review screen.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let categoryID = response.notification.request.content.categoryIdentifier
        let actionID = response.actionIdentifier

        guard categoryID == RecurringNotificationService.categoryIdentifier else {
            completionHandler()
            return
        }

        let ruleID = (userInfo["recurringRuleID"] as? String).flatMap(UUID.init)

        Task { @MainActor in
            defer { completionHandler() }

            switch actionID {
            case RecurringNotificationService.postActionIdentifier:
                applyRecurringAction(ruleID: ruleID) { rule, context in
                    RecurringRuleService.post(rule: rule, in: context)
                }
            case RecurringNotificationService.skipActionIdentifier:
                applyRecurringAction(ruleID: ruleID) { rule, context in
                    RecurringRuleService.skip(rule: rule, in: context)
                }
            default:
                // Review action or a plain tap on the banner.
                NotificationCenter.default.post(name: .openRecurringReview, object: nil)
            }
        }
    }

    /// Resolve the rule, run `mutate`, then refresh the app-icon badge.
    @MainActor
    private func applyRecurringAction(
        ruleID: UUID?,
        mutate: (RecurringRule, ModelContext) -> Void
    ) {
        let context = QuaraMoneyApp.sharedContainer.mainContext
        guard let ruleID, let rule = RecurringRuleService.rule(withID: ruleID, in: context) else { return }
        mutate(rule, context)
        Task { await RecurringNotificationService.refreshBadgeCount(in: context) }
    }
}
