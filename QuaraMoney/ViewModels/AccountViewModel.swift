import Foundation
import SwiftData
import SwiftUI

/// Logic for the unified Account screen (profile + cloud sync + auth).
///
/// Exists so the tricky sync-toggle side effects live in exactly one place,
/// regardless of which view hosts the toggle:
    ///  • Re-enabling sync restarts auth. QuaraMoneyApp observes the same
    ///    AppStorage flag and owns the reconcile/conflict/sync pipeline so it can
    ///    invalidate account maintenance in the same auth generation model.
///  • Disabling sync must stop the Realtime channel — previously it kept the
///    socket subscribed and idle-triggering no-op syncs.
@MainActor
final class AccountViewModel {

    var isConfigured: Bool { SupabaseConfig.isConfigured }

    /// Side effects of the master Cloud Sync toggle.
    func syncEnabledChanged(_ enabled: Bool) {
        guard enabled else {
            SyncRealtime.shared.stop()
            return
        }
        SupabaseAuthManager.shared.start()
    }

    /// True when the device is signed out but its local store still belongs to
    /// an account and holds un-pushed changes. Signing in to a *different*
    /// account from this state wipes those changes (they can only be pushed by
    /// the owning account), so the sign-in form surfaces a warning.
    var hasUnsyncedDataFromPreviousAccount: Bool {
        !SupabaseAuthManager.shared.isSignedIn
            && SyncEngine.isLocalStoreAccountOwned
            && SyncEngine.shared.hasPendingLocalChanges()
    }

    /// Kicks a sync after a local profile edit (name/avatar), so the change
    /// lands in the cloud without waiting for the next app-level trigger.
    func pushProfileEdit(avatarChanged: Bool = false, context: ModelContext) {
        ProfileSyncService.shared.noteLocalEdit(avatarChanged: avatarChanged)
        SyncEngine.shared.configureSyncContext(context)
        SyncEngine.shared.enqueueSync(reason: .profileEdit)
    }
}
