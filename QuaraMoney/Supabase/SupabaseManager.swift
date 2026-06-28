import Foundation
import Supabase

/// Owns the single `SupabaseClient` instance for the app.
///
/// Created lazily and only when `SupabaseConfig.isConfigured` is true, so a build
/// without credentials (or with sync disabled) behaves exactly like the original
/// local-only app — `client` is simply `nil` and nothing reaches the network.
///
/// Phase 0: this wrapper exists but no app code calls it yet. Auth (Phase 1) and
/// the SyncEngine (Phase 3) build on top of `client`.
final class SupabaseManager: Sendable {
    static let shared = SupabaseManager()

    /// `nil` when no valid credentials are configured.
    let client: SupabaseClient?

    private init() {
        if SupabaseConfig.isConfigured, let url = SupabaseConfig.url {
            client = SupabaseClient(
                supabaseURL: url,
                supabaseKey: SupabaseConfig.anonKey,
                options: .init(
                    auth: .init(
                        redirectToURL: SupabaseConfig.authCallbackURL,
                        emitLocalSessionAsInitialSession: true
                    )
                )
            )
        } else {
            client = nil
            #if DEBUG
            print("[Supabase] Not configured — running in local-only mode. " +
                  "Run ./supabase/gen-secrets.sh after filling secrets.local.xcconfig.")
            #endif
        }
    }
}
