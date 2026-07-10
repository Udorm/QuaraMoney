import SwiftUI
import SwiftData

/// Hosts the first-sign-in data-conflict sheet and the "start Realtime once the
/// conflict resolves" side effect.
///
/// Deliberately isolated in its own modifier: `SyncEngine` is an
/// `ObservableObject`, so *any* `@Published` change (`isSyncing` flips twice per
/// auto-sync, `lastSyncDate` stamps after every save) invalidates every observer
/// wholesale. Observing it here confines that churn to this lightweight node
/// instead of re-evaluating the entire `WindowGroup` body — which previously
/// re-initialized `ContentView`/`HomeView` (and a throwaway `HomeViewModel`)
/// after nearly every user edit.
struct SyncConflictPresenter: ViewModifier {
    @ObservedObject private var syncEngine = SyncEngine.shared
    let mainContext: ModelContext

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { syncEngine.conflictState != .none },
                set: { _ in }
            )) {
                DataConflictResolutionView()
            }
            .onChange(of: syncEngine.conflictState) { _, newState in
                // Conflict resolved — start Realtime now (it was deferred while
                // the resolution sheet was pending).
                if newState == .none && SupabaseAuthManager.shared.isSignedIn {
                    SyncRealtime.shared.start(context: mainContext)
                }
            }
    }
}

extension View {
    /// Presents the sync conflict-resolution sheet whenever the engine raises a
    /// first-sign-in conflict. See ``SyncConflictPresenter``.
    func syncConflictPresenter(mainContext: ModelContext) -> some View {
        modifier(SyncConflictPresenter(mainContext: mainContext))
    }
}
