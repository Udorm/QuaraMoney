import UIKit

// Receives UIWindowScene callbacks that SwiftUI's internal scene delegate
// does not forward. Window/view setup is still handled by SwiftUI's @main App.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    // Cold launch: the scene is being created because the user tapped the shortcut
    // while the app was not running. Store the pending action for HomeView to pick
    // up after the view hierarchy is ready.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shortcut = connectionOptions.shortcutItem,
           shortcut.type == AppDelegate.ShortcutType.addTransaction {
            AppDelegate.pendingShortcutType = shortcut.type
        }
    }

    // Warm launch: the app was backgrounded and the user tapped the shortcut.
    // Post immediately — ContentView switches the tab and stages the intent on
    // AppRouter; HomeView presents the sheet once it is actually visible, so no
    // settle-delay is needed (the old 0.4 s timer could fire too early on a
    // slow device and the presentation was silently dropped).
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard shortcutItem.type == AppDelegate.ShortcutType.addTransaction else {
            completionHandler(false)
            return
        }
        NotificationCenter.default.post(name: .openAddTransaction, object: nil)
        completionHandler(true)
    }
}
