import Foundation
import SwiftData
import Supabase

/// Subscribes to Supabase Realtime and triggers a debounced delta sync whenever
/// any of the user's rows change on the server — so edits made on another device
/// appear on-screen without a manual refresh.
///
/// Design: Realtime is used as a *signal* ("something changed → go delta-sync"),
/// not as a per-row applier. This reuses the tested SyncEngine pull (incremental,
/// relationship-safe) and keeps the surface small and scalable. RLS still governs
/// which changes the user receives.
@MainActor
final class SyncRealtime {
    static let shared = SyncRealtime()

    private var channel: RealtimeChannelV2?
    private var observeTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var context: ModelContext?

    private init() {}

    /// Begins listening when sync is operational. Idempotent.
    func start(context: ModelContext) {
        guard SupabaseFeatureFlags.isOperational,
              let client = SupabaseManager.shared.client,
              channel == nil else { return }
        self.context = context
        let channel = client.channel("quaramoney-sync")
        self.channel = channel
        let changes = channel.postgresChange(AnyAction.self, schema: "public")
        observeTask = Task { [weak self] in
            await channel.subscribe()
            for await _ in changes {
                self?.scheduleSync()
            }
        }
    }

    /// Stops listening (e.g. on background or sign-out).
    func stop() {
        observeTask?.cancel(); observeTask = nil
        debounceTask?.cancel(); debounceTask = nil
        guard let channel else { return }
        self.channel = nil
        Task { await channel.unsubscribe() }
    }

    private func scheduleSync() {
        guard context != nil else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self, let ctx = self.context else { return }
            await SyncEngine.shared.syncIfOperational(context: ctx)
        }
    }
}
