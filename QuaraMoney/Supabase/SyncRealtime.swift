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
    private var pendingIdentities: Set<SyncEngine.EventIdentity> = []
    private var hasUnfingerprintableEvent = false
    private var generation: UInt64 = 0
    private var debounceDelay: Duration = .seconds(1.5)

    private struct IdentityPayload: Decodable {
        let id: UUID
        let updated_at: Date
    }

    private init() {}

    /// Begins listening when sync is operational. Idempotent.
    func start(context: ModelContext) {
        guard SupabaseFeatureFlags.isOperational,
              let client = SupabaseManager.shared.client,
              channel == nil else { return }
        self.context = context
        SyncEngine.shared.configureSyncContext(context)
        let startGeneration = generation
        let channel = client.channel("quaramoney-sync")
        self.channel = channel

        // Register a per-table binding BEFORE subscribing (required ordering).
        let streams = Self.watchedTables.map { table in
            (table, channel.postgresChange(AnyAction.self, schema: "public", table: table))
        }

        observeTask = Task { [weak self] in
            // Ensure the Realtime socket carries the user's JWT before binding, so
            // RLS-protected postgres_changes are actually delivered (avoids a race
            // where the channel subscribes with only the anon key).
            await client.realtimeV2.setAuth()
            do {
                try await channel.subscribeWithError()
            } catch {
                #if DEBUG
                print("[SyncRealtime] subscribe failed: \(error)")
                #endif
                return
            }
            #if DEBUG
            print("[SyncRealtime] subscribed; watching \(streams.count) tables")
            #endif

            // Fan the per-table change streams into one resync trigger.
            await withTaskGroup(of: Void.self) { group in
                for (table, stream) in streams {
                    group.addTask { [weak self] in
                        for await change in stream {
                            guard let self else { return }
                            await self.receive(change, table: table, generation: startGeneration)
                        }
                    }
                }
            }
        }
    }

    /// Stops listening (e.g. on background or sign-out).
    func stop() {
        generation &+= 1
        observeTask?.cancel(); observeTask = nil
        debounceTask?.cancel(); debounceTask = nil
        pendingIdentities.removeAll()
        hasUnfingerprintableEvent = false
        context = nil
        SyncEngine.shared.stopSyncLifecycle()
        guard let channel else { return }
        self.channel = nil
        Task { await channel.unsubscribe() }
    }

    private func receive(_ change: AnyAction, table: String, generation eventGeneration: UInt64) {
        guard eventGeneration == generation, context != nil else { return }
        let kind: String
        switch change {
        case .insert: kind = "INSERT"
        case .update: kind = "UPDATE"
        case .delete: kind = "DELETE"
        }

        routeDecodedEvent(identity: Self.identity(from: change, table: table), kind: kind)
    }

    private func routeDecodedEvent(identity: SyncEngine.EventIdentity?, kind: String) {
        if let identity {
            if SyncEngine.shared.isOwnEcho(identity) {
                #if DEBUG
                print("[SyncRealtime] own \(kind) echo suppressed table=\(identity.table) id=\(identity.id)")
                #endif
                return
            }
            if SyncEngine.shared.isSyncing {
                #if DEBUG
                print("[SyncRealtime] remote \(kind) received mid-sync; buffering identity")
                #endif
                SyncEngine.shared.receiveRealtimeEvent(identity)
                return
            }
            #if DEBUG
            print("[SyncRealtime] remote \(kind) received; scheduling resync")
            #endif
            scheduleSync(identity: identity)
        } else {
            #if DEBUG
            print("[SyncRealtime] remote \(kind) received without fingerprint; scheduling resync")
            #endif
            scheduleSync(identity: nil)
        }
    }

    private static func identity(from change: AnyAction, table: String) -> SyncEngine.EventIdentity? {
        let payload: IdentityPayload
        do {
            switch change {
            case .insert(let action):
                payload = try action.decodeRecord(as: IdentityPayload.self, decoder: AnyJSON.decoder)
            case .update(let action):
                payload = try action.decodeRecord(as: IdentityPayload.self, decoder: AnyJSON.decoder)
            case .delete:
                return nil
            }
        } catch {
            return nil
        }
        return SyncEngine.EventIdentity(table: table, id: payload.id, updatedAt: payload.updated_at)
    }

    private func scheduleSync(identity: SyncEngine.EventIdentity?) {
        guard context != nil else { return }
        if let identity {
            pendingIdentities.insert(identity)
        } else {
            hasUnfingerprintableEvent = true
        }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounceDelay)
            guard !Task.isCancelled, self.context != nil else { return }
            let identities = self.pendingIdentities
            let forceRun = self.hasUnfingerprintableEvent
            self.pendingIdentities.removeAll()
            self.hasUnfingerprintableEvent = false
            if forceRun {
                SyncEngine.shared.enqueueSync(reason: .realtime)
            } else {
                SyncEngine.shared.enqueueSync(reason: .realtime, eventIdentities: identities)
            }
        }
    }

    #if DEBUG
    func injectPayloadForTesting(
        identity: SyncEngine.EventIdentity?,
        context: ModelContext
    ) {
        self.context = context
        routeDecodedEvent(identity: identity, kind: "TEST")
    }

    func setDebounceDelayForTesting(_ delay: Duration) {
        debounceDelay = delay
    }

    func resetForTesting() {
        debounceTask?.cancel()
        debounceTask = nil
        pendingIdentities.removeAll()
        hasUnfingerprintableEvent = false
        context = nil
        debounceDelay = .seconds(1.5)
    }
    #endif
}
