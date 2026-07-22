import SwiftUI
import SwiftData

extension View {
    /// Adds pull-to-refresh that runs a Supabase delta-sync (no-op when cloud sync
    /// is off). The sync posts `.dataDidUpdate` on completion, so views observing
    /// it refresh. Safe on every scrollable screen.
    func syncPullToRefresh(_ context: ModelContext) -> some View {
        self.refreshable {
            SyncEngine.shared.configureSyncContext(context)
            _ = await SyncEngine.shared.requestSyncAndWait(reason: .manualRefresh)
        }
    }
}
