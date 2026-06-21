
import UIKit

class HapticManager {
    static let shared = HapticManager()
    
    private init() {}
    
    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
    
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    // Convenience wrappers so callers (e.g. view models without a UIKit import)
    // can trigger notification haptics without referencing UIKit enum cases.
    func success() { notification(type: .success) }
    func warning() { notification(type: .warning) }
    func error() { notification(type: .error) }
}
