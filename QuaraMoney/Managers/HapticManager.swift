
import UIKit

/// Process-wide feedback generators, created once and kept warm.
///
/// `UIFeedbackGenerator` is not a value type you throw away: allocating one and
/// firing it immediately — which is what this used to do on every call — leaves
/// the Taptic Engine to spin up from idle, so the tap is felt noticeably after
/// it was made. `prepare()` warms the engine ahead of the event; keeping the
/// generators alive is what makes that possible at all. This matters most on the
/// compact entry keypad, where a digit is tapped several times per transaction.
@MainActor
final class HapticManager {
    static let shared = HapticManager()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()

    private init() {}

    private func generator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch style {
        case .light: return lightImpact
        case .medium: return mediumImpact
        case .heavy: return heavyImpact
        case .rigid: return rigidImpact
        case .soft: return softImpact
        @unknown default: return mediumImpact
        }
    }

    /// Warms the engine for a screen that is about to fire a burst of haptics
    /// (the calculator keypad). Cheap, and idempotent — the system lets the
    /// warm state lapse on its own after a few seconds of no feedback.
    func prepareForRapidInput() {
        lightImpact.prepare()
        mediumImpact.prepare()
    }

    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
    }

    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = generator(for: style)
        generator.impactOccurred()
        // Re-arm for the next one: taps come in runs, not singly.
        generator.prepare()
    }

    func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    // Convenience wrappers so callers (e.g. view models without a UIKit import)
    // can trigger notification haptics without referencing UIKit enum cases.
    func success() { notification(type: .success) }
    func warning() { notification(type: .warning) }
    func error() { notification(type: .error) }
}
