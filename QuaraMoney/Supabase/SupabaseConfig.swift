import Foundation

/// Static Supabase configuration.
///
/// Values are sourced from `SupabaseSecrets` — a gitignored file generated from
/// `supabase/secrets.local.xcconfig` by `supabase/gen-secrets.sh`. Real keys are
/// never committed. The anon/publishable key is safe to embed in the client; data
/// is protected by Row-Level Security on the server.
enum SupabaseConfig {
    static var url: URL? { URL(string: SupabaseSecrets.url) }
    static var anonKey: String { SupabaseSecrets.anonKey }

    /// True only when both a valid URL and a non-placeholder key are present.
    /// When false the app stays fully local — `SupabaseManager.client` is nil.
    static var isConfigured: Bool {
        guard let url, url.host != nil else { return false }
        let key = anonKey
        return !key.isEmpty && !key.contains("PASTE")
    }
}
