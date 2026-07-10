import Foundation
import Observation

/// Pending cross-tab navigation intents, consumed by the destination view when
/// it is actually visible.
///
/// Replaces the timer-based hand-offs (asyncAfter 0.4 s after tab switches,
/// a 1.5 s cold-launch sleep) that raced the tab/splash animations: too early
/// and UIKit silently dropped the presentation (the user's tap did nothing),
/// too late and the app felt sluggish. State + visibility can't race.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    private init() {}

    /// Present the Add Transaction sheet as soon as the Home tab is visible.
    var pendingAddTransaction = false

    /// Push the Recurring review screen as soon as the More tab is visible.
    var pendingRecurringReview = false
}
