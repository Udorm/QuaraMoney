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
    /// True after the app was opened from a password-recovery link: the user is
    /// signed in with a recovery session and must be shown the "set new
    /// password" sheet. Cleared when the password is updated or the sheet is
    /// dismissed. While true, the app defers the post-sign-in sync pipeline
    /// (account reconcile + first-sign-in conflict check) so the data-conflict
    /// sheet can't appear on top of the password reset.
    @Published var passwordRecoveryPending = false

    /// Persisted marker that THIS device requested a password reset, so the next
    /// auth deep-link callback is treated as the recovery link. Needed because
    /// the PKCE flow (the SDK default, which this app uses) never emits the
    /// `.passwordRecovery` event — only `.signedIn`. PKCE links can only be
    /// completed on the requesting device (the code verifier is local), so a
    /// device-local flag is exactly as reliable as the flow itself.
    private let recoveryFlowRequestedKey = "authRecoveryFlowRequested.v1"

    private var observationTask: Task<Void, Never>?

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    var currentEmail: String? {
        if case let .signedIn(email) = state { return email }
        return nil
    }

    /// The display name stored on the Supabase auth account (captured at
    /// sign-up, in `user_metadata.display_name`). The `profiles` table remains
    /// the syncing source of truth; this is the account-level fallback used when
    /// no profile row exists yet.
    var currentDisplayName: String? {
        guard let name = client?.auth.currentUser?.userMetadata["display_name"]?.stringValue,
              !name.isEmpty else { return nil }
        return name
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
                    if let session = change.session, !session.isExpired {
                        self.state = .signedIn(email: session.user.email ?? "")
                    } else {
                        self.state = .signedOut
                    }
                case .signedOut:
                    self.state = .signedOut
                case .passwordRecovery:
                    // Opened from a reset-password email link: the session is
                    // valid, but the user came here to choose a new password.
                    if let session = change.session, !session.isExpired {
                        self.state = .signedIn(email: session.user.email ?? "")
                        self.passwordRecoveryPending = true
                    }
                default:
                    break
                }
            }
        }
    }

    // MARK: - Actions

    func signUp(email: String, password: String, name: String = "") async {
        guard let client else { return }
        beginWork()
        defer { isWorking = false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let response = try await client.auth.signUp(
                email: email,
                password: password,
                // Stash the name on the auth account so it survives even before
                // a `profiles` row exists (and on any future fresh device).
                data: trimmedName.isEmpty ? nil : ["display_name": .string(trimmedName)]
            )
            // Seed the name locally so it shows immediately and the next sync
            // pushes it up to the `profiles` table (the syncing source of truth).
            if !trimmedName.isEmpty {
                ProfileSyncService.shared.setDisplayNameLocally(trimmedName)
            }
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
            // Signed in normally — any earlier reset request is moot; don't let
            // its marker hijack a future magic-link callback.
            UserDefaults.standard.removeObject(forKey: recoveryFlowRequestedKey)
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
            // A magic-link request supersedes any earlier reset request — its
            // callback must not be misread as a recovery link.
            UserDefaults.standard.removeObject(forKey: recoveryFlowRequestedKey)
            infoMessage = "We emailed you a sign-in link. Open it on this device."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Emails a password-reset link. The link opens the app via the same
    /// `quaramoney://auth-callback` deep link as magic links; the resulting
    /// `.passwordRecovery` event surfaces the "set new password" sheet.
    func sendPasswordReset(email: String) async {
        guard let client else { return }
        beginWork()
        defer { isWorking = false }
        do {
            try await client.auth.resetPasswordForEmail(
                email.trimmingCharacters(in: .whitespaces),
                redirectTo: SupabaseConfig.authCallbackURL
            )
            UserDefaults.standard.set(true, forKey: recoveryFlowRequestedKey)
            infoMessage = "We emailed you a password-reset link. Open it on this device."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sets a new password for the signed-in (recovery) session. Returns true
    /// on success so the sheet knows to dismiss.
    func updatePassword(_ newPassword: String) async -> Bool {
        guard let client else { return false }
        beginWork()
        defer { isWorking = false }
        do {
            _ = try await client.auth.update(user: UserAttributes(password: newPassword))
            passwordRecoveryPending = false
            infoMessage = "Your password has been updated."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func signOut() async {
        guard let client else { return }
        beginWork()
        defer { isWorking = false }
        // Flush pending changes while still authenticated (waits for any
        // in-flight sync first, so the flush can't silently no-op). Only wipe
        // the local cache when the flush verifiably left nothing behind — the
        // sync ran clean, the initial upload has completed, AND no dirty rows or
        // queued deletions remain — so an offline or racing sign-out can't lose
        // un-synced edits.
        do {
            try await Self.performProtectedSignOut(
                flush: { await SyncEngine.shared.flushBeforeSignOut() },
                authenticationSignOut: { try await client.auth.signOut() },
                canWipe: { SyncEngine.shared.canWipeAfterAuthenticationSignOut(cleanRevision: $0) },
                wipe: { revision in
                    await SyncEngine.shared.wipeForSignOut(expectedCleanRevision: revision)
                }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    struct SignOutSafetyError: LocalizedError, Sendable {
        let message: String
        var errorDescription: String? { message }
    }

    static func performProtectedSignOut(
        flush: @MainActor () async -> Result<UInt64, SyncEngine.SyncFailure>,
        authenticationSignOut: @MainActor () async throws -> Void,
        canWipe: @MainActor (UInt64) -> Bool,
        wipe: @MainActor (UInt64) async -> Bool
    ) async throws {
        let cleanRevision: UInt64
        switch await flush() {
        case .success(let revision):
            cleanRevision = revision
        case .failure(let failure):
            // Authentication sign-out is deliberately aborted. Retaining rows is
            // not enough: a later different-account sign-in could otherwise wipe
            // edits that never reached the previous account's cloud.
            throw failure
        }
        try await authenticationSignOut()
        guard canWipe(cleanRevision) else {
            throw SignOutSafetyError(
                message: "sync.error.signOutChanged".localized
            )
        }
        guard await wipe(cleanRevision) else {
            throw SignOutSafetyError(
                message: "sync.error.preWipeChanged".localized
            )
        }
    }

    /// Permanently deletes the signed-in account: cloud rows (FK cascade),
    /// storage objects, and the auth user itself via the `delete-account` Edge
    /// Function (the client cannot delete its own auth user). Local data is
    /// wiped afterwards. Required by App Store Guideline 5.1.1(v).
    func deleteAccount() async {
        guard let client else { return }
        beginWork()
        defer { isWorking = false }
        do {
            try await client.functions.invoke("delete-account")
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        // The server-side user no longer exists; drop the local session (the
        // global sign-out endpoint would 403) and clear the device copy.
        try? await client.auth.signOut(scope: .local)
        _ = await SyncEngine.shared.wipeForSignOut()
        state = .signedOut
        infoMessage = "Your account and all cloud data have been deleted."
    }

    /// Completes an auth flow opened via the `quaramoney://auth-callback` deep link
    /// (magic link / email confirmation / password recovery). Wired from the
    /// app's `.onOpenURL`.
    func handleCallback(_ url: URL) {
        guard let client else { return }
        // Recovery must be detected app-side: under PKCE the SDK never emits
        // `.passwordRecovery`, and the flag has to be up BEFORE the exchange so
        // the `.signedIn` state change already sees a recovery in progress.
        let isRecovery = UserDefaults.standard.bool(forKey: recoveryFlowRequestedKey)
            || Self.urlIndicatesRecovery(url)
        if isRecovery { passwordRecoveryPending = true }
        Task {
            do {
                try await client.auth.session(from: url)
                if isRecovery {
                    UserDefaults.standard.removeObject(forKey: recoveryFlowRequestedKey)
                }
            } catch {
                // Expired/invalid link: stand down so the reset sheet doesn't
                // sit on top of a signed-out app.
                if isRecovery { passwordRecoveryPending = false }
                errorMessage = error.localizedDescription
            }
        }
    }

    /// True when the callback URL itself is marked as a recovery link
    /// (`type=recovery` in the query or fragment — present in implicit-flow
    /// links; the persisted request marker covers PKCE).
    private nonisolated static func urlIndicatesRecovery(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        if components.queryItems?.contains(where: { $0.name == "type" && $0.value == "recovery" }) == true {
            return true
        }
        if let fragment = components.fragment {
            var fragmentComponents = URLComponents()
            fragmentComponents.query = fragment
            return fragmentComponents.queryItems?
                .contains(where: { $0.name == "type" && $0.value == "recovery" }) == true
        }
        return false
    }

    private func beginWork() {
        errorMessage = nil
        infoMessage = nil
        isWorking = true
    }
}
