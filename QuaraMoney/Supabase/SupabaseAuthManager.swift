import Foundation
import Combine
import Supabase

/// Observable authentication state for the Supabase backend.
///
/// Phase 1: provides email/password (and magic-link) auth, reachable from
/// Settings → Cloud Sync. Sessions are persisted automatically by supabase-swift
/// in the Keychain, so `start()` restores an existing session on launch.
///
/// Everything here is inert unless `SupabaseManager.shared.client` exists (i.e.
/// credentials are configured). The app does not force a login gate yet — that
/// arrives with the sync phases.
@MainActor
final class SupabaseAuthManager: ObservableObject {
    static let shared = SupabaseAuthManager()

    enum AuthState: Equatable {
        case unknown          // before first auth-state event
        case signedOut
        case signedIn(email: String)
    }

    @Published private(set) var state: AuthState = .unknown
    /// Transient user-facing error (e.g. wrong password). Cleared on next action.
    @Published var errorMessage: String?
    /// Transient info (e.g. "check your email"). Cleared on next action.
    @Published var infoMessage: String?
    /// True while an auth network call is in flight.
    @Published var isWorking = false

    private var observationTask: Task<Void, Never>?

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    var currentEmail: String? {
        if case let .signedIn(email) = state { return email }
        return nil
    }

    private var client: SupabaseClient? { SupabaseManager.shared.client }

    private init() {}

    /// Begins observing auth-state changes. Idempotent. Safe to call when the
    /// client is nil (it simply resolves to `.signedOut`).
    func start() {
        guard observationTask == nil else { return }
        guard let client else {
            state = .signedOut
            return
        }
        observationTask = Task { [weak self] in
            for await change in client.auth.authStateChanges {
                guard let self else { return }
                switch change.event {
                case .signedIn, .initialSession, .tokenRefreshed, .userUpdated:
                    if let session = change.session {
                        self.state = .signedIn(email: session.user.email ?? "")
                    } else {
                        self.state = .signedOut
                    }
                case .signedOut:
                    self.state = .signedOut
                default:
                    break
                }
            }
        }
    }

    // MARK: - Actions

    func signUp(email: String, password: String) async {
        guard let client else { return }
        beginWork()
        defer { isWorking = false }
        do {
            let response = try await client.auth.signUp(email: email, password: password)
            // When email confirmation is enabled, no session is returned yet.
            if response.session == nil {
                infoMessage = "Check your email to confirm your account, then sign in."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        guard let client else { return }
        beginWork()
        defer { isWorking = false }
        do {
            _ = try await client.auth.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendMagicLink(email: String) async {
        guard let client else { return }
        beginWork()
        defer { isWorking = false }
        do {
            try await client.auth.signInWithOTP(
                email: email,
                redirectTo: SupabaseConfig.authCallbackURL
            )
            infoMessage = "We emailed you a sign-in link. Open it on this device."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        guard let client else { return }
        beginWork()
        defer { isWorking = false }
        do {
            try await client.auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Completes an auth flow opened via the `quaramoney://auth-callback` deep link
    /// (magic link / email confirmation). Wired from the app's `.onOpenURL`.
    func handleCallback(_ url: URL) {
        guard let client else { return }
        Task {
            do {
                try await client.auth.session(from: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func beginWork() {
        errorMessage = nil
        infoMessage = nil
        isWorking = true
    }
}
