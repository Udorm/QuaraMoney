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

    /// Tables to watch. A `postgres_changes` binding must name a table — a
    /// schema-only binding is silently dropped server-side and delivers nothing,
    /// so we register one binding per synced table.
    private static let watchedTables = [
        "wallets", "categories", "events", "recurring_rules", "savings_goals", "debts",
        "transactions", "transaction_locations", "budgets", "budget_categories",
        "event_members", "event_ledger_transactions", "event_ledger_participants",
        "event_settlement_snapshots", "event_settlement_transfers", "event_wallet_export_records"
    ]

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

        // Register a per-table binding BEFORE subscribing (required ordering).
        let streams = Self.watchedTables.map { table in
            channel.postgresChange(AnyAction.self, schema: "public", table: table)
        }

        observeTask = Task { [weak self] in
            // Ensure the Realtime socket carries the user's JWT before binding, so
            // RLS-protected postgres_changes are actually delivered (avoids a race
            // where the channel subscribes with only the anon key).
            await client.realtimeV2.setAuth()
            do {
                try await channel.subscribeWithError()
            } catch {
                print("[SyncRealtime] subscribe failed: \(error)")
                return
            }
            print("[SyncRealtime] subscribed; watching \(streams.count) tables")

            // Fan the per-table change streams into one resync trigger.
            await withTaskGroup(of: Void.self) { group in
                for stream in streams {
                    group.addTask { [weak self] in
                        for await change in stream {
                            let kind: String
                            switch change {
                            case .insert: kind = "INSERT"
                            case .update: kind = "UPDATE"
                            case .delete: kind = "DELETE"
                            }
                            print("[SyncRealtime] remote \(kind) received; scheduling resync")
                            await MainActor.run { self?.scheduleSync() }
                        }
                    }
                }
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
