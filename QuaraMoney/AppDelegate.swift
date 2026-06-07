import UIKit

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
