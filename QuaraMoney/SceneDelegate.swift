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
    // Post the notification after a brief delay so ContentView's tab switch
    // animation completes before HomeView presents the sheet.
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard shortcutItem.type == AppDelegate.ShortcutType.addTransaction else {
            completionHandler(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(name: .openAddTransaction, object: nil)
        }
        completionHandler(true)
    }
}
