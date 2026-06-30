import Foundation

/// Runtime kill-switch for the Supabase backend.
///
/// Defaults to **off**. While off, the app is identical to the pre-migration
/// local-only version: no auth, no network, SwiftData only. This lets us disable
/// sync in the field (or during a phased rollout) without shipping a new build.
///
/// Later phases can back this with a remote config flag; for now it's a local
/// UserDefaults toggle so QA / TestFlight can opt in.
enum SupabaseFeatureFlags {
    private static let syncEnabledKey = "isSupabaseSyncEnabled"

    /// Master switch. When false, no Supabase code path should run.
    static var isSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: syncEnabledKey) } // absent => false
        set { UserDefaults.standard.set(newValue, forKey: syncEnabledKey) }
    }

    /// Convenience: sync may run only when explicitly enabled *and* credentials exist.
    static var isOperational: Bool {
        isSyncEnabled && SupabaseConfig.isConfigured && SupabaseManager.shared.client != nil
    }
}
