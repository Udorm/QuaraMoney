import Foundation

/// Single source of truth for whether premium ("Pro") analytics features are unlocked.
///
/// The Pro dashboard is **free for everyone today**, but every entry point routes through
/// this gate so a paywall (StoreKit 2, subscription, restore-purchases, etc.) can be added
/// later without touching the call sites. To monetize: replace `isProUnlocked` with a real
/// entitlement check and surface a paywall where the gate currently returns `false`.
enum ProFeatureGate {

    /// Whether the user can access the Pro analytics dashboard.
    /// Currently always `true` (free). Wire a purchase/entitlement check here later.
    static var isProUnlocked: Bool {
        // TODO: Replace with StoreKit entitlement lookup when Pro becomes a paid tier.
        true
    }
}
