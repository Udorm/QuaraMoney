import Foundation
import Combine
import SwiftData
import Supabase

/// Bidirectional sync between local SwiftData and Supabase.
///
/// Phase 3c slice: wallets, categories, transactions. Strategy:
///  • Push: rows with `needsSync == true` are upserted (parents before children),
///    then flagged `needsSync = false`.
///  • Pull: rows changed since a per-table cursor (`updated_at`) are applied
///    locally with row-level last-write-wins.
///  • `SyncMutationTracker.isApplyingSyncChanges` is held true around local writes
///    so the engine's own saves are not re-flagged as user edits.
///
/// Runs on the main context/actor (modest data volumes); network awaits don't
/// block the UI. Foreign keys to entities not yet synced (event/debt/savings/
/// recurring) are intentionally left null until those entities are added.
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published var lastError: String?

    private var autoSyncStarted = false
    private var autoSyncContext: ModelContext?
    private var debounceTask: Task<Void, Never>?

    private init() {}

    // MARK: - Auto-sync triggers

    /// Wires automatic sync: a debounced push after local saves. Idempotent.
    /// Safe to call when sync is off — `syncNow` guards on `isOperational`.
    func enableAutoSync(context: ModelContext) {
        guard !autoSyncStarted else { return }
        autoSyncStarted = true
        autoSyncContext = context
        NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                SyncEngine.shared.handleLocalSave()
            }
        }
    }

    /// Triggers a sync only when sync is enabled, configured, and signed in.
    /// Use for foreground / post-sign-in triggers.
    func syncIfOperational(context: ModelContext) async {
        guard SupabaseFeatureFlags.isOperational else { return }
        await syncNow(context: context)
    }

    private func handleLocalSave() {
        // Ignore the engine's own writes; only react to genuine local edits.
        guard !SyncMutationTracker.isApplyingSyncChanges,
              SupabaseFeatureFlags.isOperational,
              let context = autoSyncContext else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, let ctx = self.autoSyncContext else { return }
            await self.syncNow(context: ctx)
        }
    }

    enum SyncError: LocalizedError {
        case notOperational
        case noUser
        var errorDescription: String? {
            switch self {
            case .notOperational: return "Cloud sync is not enabled or configured."
            case .noUser: return "You must be signed in to sync."
            }
        }
    }

    func syncNow(context: ModelContext) async {
        guard !isSyncing else { return }
        guard SupabaseFeatureFlags.isOperational, let client = SupabaseManager.shared.client else {
            lastError = SyncError.notOperational.errorDescription
            return
        }
        guard let uid = client.auth.currentUser?.id else {
            lastError = SyncError.noUser.errorDescription
            return
        }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        // Hold the sync-write guard for the whole operation so none of the
        // engine's own writes (pull-applied rows, post-push needsSync clearing,
        // remote deletions) get re-flagged as local edits by the mutation tracker.
        SyncMutationTracker.isApplyingSyncChanges = true
        defer { SyncMutationTracker.isApplyingSyncChanges = false }

        do {
            // Propagate local deletions first (set deleted_at on the server).
            try await pushDeletions(client)

            // Push parents → children.
            try await pushWallets(context, client, uid)
            try await pushCategories(context, client, uid)
            try await pushEvents(context, client, uid)
            try await pushDebts(context, client, uid)
            try await pushSavingsGoals(context, client, uid)
            try await pushRecurringRules(context, client, uid)
            try await pushEventMembers(context, client, uid)
            try await pushEventLedgerTransactions(context, client, uid)
            try await pushEventLedgerParticipants(context, client, uid)
            try await pushEventSettlementSnapshots(context, client, uid)
            try await pushEventSettlementTransfers(context, client, uid)
            try await pushEventWalletExportRecords(context, client, uid)
            try await pushTransactions(context, client, uid)
            try await pushBudgets(context, client, uid)
            try await pushTransactionLocations(context, client, uid)

            // Pull parents → children.
            try await pullWallets(context, client, uid)
            try await pullCategories(context, client, uid)
            try await pullEvents(context, client, uid)
            try await pullDebts(context, client, uid)
            try await pullSavingsGoals(context, client, uid)
            try await pullRecurringRules(context, client, uid)
            try await pullEventMembers(context, client, uid)
            try await pullEventLedgerTransactions(context, client, uid)
            try await pullEventLedgerParticipants(context, client, uid)
            try await pullEventSettlementSnapshots(context, client, uid)
            try await pullEventSettlementTransfers(context, client, uid)
            try await pullEventWalletExportRecords(context, client, uid)
            try await pullTransactions(context, client, uid)
            try await pullBudgets(context, client, uid)
            try await pullTransactionLocations(context, client, uid)

            lastSyncDate = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Push

    private func pushWallets(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<Wallet>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let rows = pending.map { w in
            SyncWalletRow(id: w.id, user_id: uid, name: w.name, currency_code: w.currencyCode,
                      icon: w.icon, color_hex: w.colorHex, is_archived: w.isArchived,
                      created_at: w.createdAt, updated_at: w.updatedAt, deleted_at: w.deletedAt)
        }
        try await client.from("wallets").upsert(rows).execute()
        markSynced(pending, uid: uid, context: context)
    }

    private func pushCategories(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let rows = pending.map { c in
            SyncCategoryRow(id: c.id, user_id: uid, name: c.name, icon: c.icon, color_hex: c.colorHex,
                        type: c.type.rawValue, is_system: c.isSystem,
                        created_at: c.createdAt, updated_at: c.updatedAt, deleted_at: c.deletedAt)
        }
        try await client.from("categories").upsert(rows).execute()
        markSynced(pending, uid: uid, context: context)
    }

    private func pushTransactions(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        var rows: [SyncTransactionRow] = []
        rows.reserveCapacity(pending.count)
        for t in pending {
            var photoPath: String?
            if let data = t.photoData {
                photoPath = imagePath(uid, "transactions", t.id)
                try await uploadImage(data, to: photoPath!, client) // throws → sync retries (needsSync kept)
            }
            rows.append(SyncTransactionRow(
                id: t.id, user_id: uid, type: t.type.rawValue, date: t.date, note: t.note,
                tags: t.tags, exclude_from_reports: t.excludeFromReports, amount: t.amount,
                currency_code: t.currencyCode, exchange_rate: t.exchangeRate, stored_rate: t.storedRate,
                photo_path: photoPath,
                category_id: t.category?.id,
                event_id: t.event?.id,
                source_wallet_id: t.sourceWallet?.id,
                destination_wallet_id: t.destinationWallet?.id,
                recurring_rule_id: t.recurringRule?.id,
                debt_id: t.debt?.id,
                savings_goal_id: t.savingsGoal?.id,
                created_at: t.createdAt, updated_at: t.updatedAt, deleted_at: t.deletedAt))
        }
        try await client.from("transactions").upsert(rows).execute()
        markSynced(pending, uid: uid, context: context)
    }

    private func pushEvents(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<Event>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        var rows: [SyncEventRow] = []
        rows.reserveCapacity(pending.count)
        for e in pending {
            var coverPath: String?
            if let data = e.coverImageData {
                coverPath = imagePath(uid, "events", e.id)
                try await uploadImage(data, to: coverPath!, client)
            }
            rows.append(SyncEventRow(id: e.id, user_id: uid, title: e.title, start_date: e.startDate,
                         end_date: e.endDate, total_budget: e.totalBudget, cover_image_path: coverPath,
                         notes: e.notes, icon: e.icon, color_hex: e.colorHex, location: e.location,
                         status: e.status, currency_code: e.currencyCode, ledger_revision: e.ledgerRevision,
                         confirmed_settlement_revision: e.confirmedSettlementRevision,
                         ledger_mode: e.ledgerMode.rawValue, latitude: e.latitude, longitude: e.longitude,
                         updated_at: e.updatedAt, deleted_at: e.deletedAt))
        }
        try await client.from("events").upsert(rows).execute()
        markSynced(pending, uid: uid, context: context)
    }

    private func pushDebts(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<Debt>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let rows = pending.map { d in
            SyncDebtRow(id: d.id, user_id: uid, person_name: d.personName, total_amount: d.totalAmount,
                        currency_code: d.currencyCode, due_date: d.dueDate, type: d.type.rawValue, note: d.note,
                        date_created: d.dateCreated, is_completed: d.isCompleted, created_at: d.createdAt,
                        updated_at: d.updatedAt, deleted_at: d.deletedAt)
        }
        try await client.from("debts").upsert(rows).execute()
        markSynced(pending, uid: uid, context: context)
    }

    private func pushSavingsGoals(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<SavingsGoal>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let rows = pending.map { g in
            SyncSavingsGoalRow(id: g.id, user_id: uid, name: g.name, goal_description: g.goalDescription,
                               target_amount: g.targetAmount, current_amount: g.currentAmount,
                               currency_code: g.currencyCode, target_date: g.targetDate, created_date: g.createdDate,
                               updated_at: g.updatedAt, icon_name: g.iconName, color_hex: g.colorHex,
                               is_completed: g.isCompleted, completed_date: g.completedDate,
                               auto_contribute_enabled: g.autoContributeEnabled,
                               auto_contribute_amount: g.autoContributeAmount,
                               auto_contribute_period_raw: g.autoContributePeriod?.rawValue,
                               priority: g.priority, linked_wallet_id: g.linkedWallet?.id, deleted_at: g.deletedAt)
        }
        try await client.from("savings_goals").upsert(rows).execute()
        markSynced(pending, uid: uid, context: context)
    }

    private func pushRecurringRules(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<RecurringRule>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let rows = pending.map { r in
            SyncRecurringRuleRow(id: r.id, user_id: uid, name: r.name, amount: r.amount,
                                 currency_code: r.currencyCode, frequency: r.frequency.rawValue,
                                 start_date: r.startDate, next_due_date: r.nextDueDate, is_active: r.isActive,
                                 wallet_id: r.wallet?.id, category_id: r.category?.id,
                                 updated_at: r.updatedAt, deleted_at: r.deletedAt)
        }
        try await client.from("recurring_rules").upsert(rows).execute()
        markSynced(pending, uid: uid, context: context)
    }

    private func pushEventMembers(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<EventMember>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        var rows: [SyncEventMemberRow] = []
        rows.reserveCapacity(pending.count)
        for m in pending {
            var avatarPath: String?
            if let data = m.avatarData {
                avatarPath = imagePath(uid, "event_members", m.id)
                try await uploadImage(data, to: avatarPath!, client)
            }
            rows.append(SyncEventMemberRow(id: m.id, user_id: uid, event_id: m.event?.id, name: m.name,
                                           avatar_path: avatarPath, avatar_icon: m.avatarIcon,
                                           color_hex: m.colorHex, is_archived: m.isArchived,
                                           is_local_user: m.isLocalUser, is_budget_pool: m.isBudgetPool,
                                           sort_order: m.sortOrder, created_at: m.createdAt,
                                           updated_at: m.updatedAt, deleted_at: m.deletedAt))
        }
        try await client.from("event_members").upsert(rows).execute()
        markSynced(pending, uid: uid, context: context)
    }

    private func pushEventLedgerTransactions(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<EventLedgerTransaction>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let rows = pending.map { t in
            SyncEventLedgerTransactionRow(id: t.id, user_id: uid, event_id: t.event?.id, kind: t.kind.rawValue,
                                          title: t.title, amount_minor: t.amountMinor, paid_source: t.paidSource.rawValue,
                                          paid_by_member_id: t.paidByMemberId, split_type: t.splitType.rawValue,
                                          date: t.date, note: t.note, category_id: t.categoryId,
                                          category_name: t.categoryName, category_icon: t.categoryIcon,
                                          category_color_hex: t.categoryColorHex, is_split_all: t.isSplitAll,
                                          is_deleted: t.isDeleted, created_at: t.createdAt, updated_at: t.updatedAt,
                                          deleted_at: t.deletedAt)
        }
        try await client.from("event_ledger_transactions").upsert(rows).execute()
        markSynced(pending, uid: uid, context: context)
    }

    private func pushEventLedgerParticipants(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<EventLedgerParticipant>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let rows = pending.map { p in
            SyncEventLedgerParticipantRow(id: p.id, user_id: uid, transaction_id: p.transaction?.id,
                                          member_id: p.memberId, event_member_id: p.member?.id,
                                          order_index: p.orderIndex, updated_at: p.updatedAt, deleted_at: p.deletedAt)
        }
        try await client.from("event_ledger_participants").upsert(rows).execute()
        markSynced(pending, uid: uid, context: context)
    }

    private func pushEventSettlementSnapshots(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<EventSettlementSnapshot>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let rows = pending.map { s in
            SyncEventSettlementSnapshotRow(id: s.id, user_id: uid, event_id: s.event?.id,
                                           ledger_revision: s.ledgerRevision, created_at: s.createdAt,
                                           updated_at: s.updatedAt, deleted_at: s.deletedAt)
        }
        try await client.from("event_settlement_snapshots").upsert(rows).execute()
        markSynced(pending, uid: uid, context: context)
    }

    private func pushEventSettlementTransfers(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<EventSettlementTransfer>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let rows = pending.map { t in
            SyncEventSettlementTransferRow(id: t.id, user_id: uid, snapshot_id: t.snapshot?.id,
                                           from_member_id: t.fromMemberId, to_member_id: t.toMemberId,
                                           amount_minor: t.amountMinor, sequence: t.sequence,
                                           updated_at: t.updatedAt, deleted_at: t.deletedAt)
        }
        try await client.from("event_settlement_transfers").upsert(rows).execute()
        markSynced(pending, uid: uid, context: context)
    }

    private func pushEventWalletExportRecords(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<EventWalletExportRecord>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let rows = pending.map { r in
            SyncEventWalletExportRecordRow(id: r.id, user_id: uid, event_id: r.event?.id, snapshot_id: r.snapshot?.id,
                                           member_id: r.memberId, wallet_transaction_id: r.walletTransactionId,
                                           amount_minor: r.amountMinor, direction: r.direction.rawValue,
                                           export_type: r.exportType.rawValue, created_at: r.createdAt,
                                           updated_at: r.updatedAt, deleted_at: r.deletedAt)
        }
        try await client.from("event_wallet_export_records").upsert(rows).execute()
        markSynced(pending, uid: uid, context: context)
    }

    private func pushBudgets(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let rows = pending.map { b in
            SyncBudgetRow(id: b.id, user_id: uid, name: b.name, amount_limit: b.amountLimit,
                          currency_code: b.currencyCode, period_type_raw: b.periodType.rawValue,
                          start_date: b.startDate, created_at: b.createdAt, updated_at: b.updatedAt,
                          custom_end_date: b.customEndDate, month: b.month, year: b.year,
                          is_recurring: b.isRecurring, rollover_excess: b.rolloverExcess,
                          rollover_amount: b.rolloverAmount,
                          amount_type_data: b.amountType.encode().flatMap { String(data: $0, encoding: .utf8) },
                          alert_at_50: b.alertAt50, alert_at_80: b.alertAt80, alert_at_100: b.alertAt100,
                          alert_on_projected_overspend: b.alertOnProjectedOverspend,
                          last_alert_triggered_date: b.lastAlertTriggeredDate,
                          last_alert_threshold: b.lastAlertThreshold,
                          budget_category_type_raw: b.budgetCategoryType?.rawValue,
                          category_id: b.category?.id, deleted_at: b.deletedAt)
        }
        try await client.from("budgets").upsert(rows).execute()
        // Rebuild each budget's category join rows (delete then insert current set).
        for b in pending {
            try await client.from("budget_categories").delete().eq("budget_id", value: b.id.uuidString).execute()
            let joins = (b.categories ?? []).map {
                SyncBudgetCategoryRow(budget_id: b.id, category_id: $0.id, user_id: uid)
            }
            if !joins.isEmpty {
                try await client.from("budget_categories").insert(joins).execute()
            }
        }
        markSynced(pending, uid: uid, context: context)
    }

    private func pushTransactionLocations(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        // Locations have no back-reference, so gather them via their owning transactions.
        let txns = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.location != nil }))
        let pairs = txns.compactMap { t -> (Transaction, TransactionLocation)? in
            guard let loc = t.location, loc.needsSync else { return nil }
            return (t, loc)
        }
        guard !pairs.isEmpty else { return }
        let rows = pairs.map { (t, loc) in
            SyncTransactionLocationRow(id: loc.id, user_id: uid, transaction_id: t.id,
                                       display_name: loc.displayName, full_address: loc.fullAddress,
                                       short_address: loc.shortAddress, latitude: loc.latitude,
                                       longitude: loc.longitude,
                                       horizontal_accuracy_meters: loc.horizontalAccuracyMeters,
                                       captured_at: loc.capturedAt, source_raw: loc.sourceRaw,
                                       apple_place_id: loc.applePlaceID,
                                       alternate_apple_place_ids: loc.alternateApplePlaceIDs,
                                       point_of_interest_category_raw: loc.pointOfInterestCategoryRaw,
                                       locality: loc.locality, administrative_area: loc.administrativeArea,
                                       country_code: loc.countryCode,
                                       normalized_spatial_key: loc.normalizedSpatialKey,
                                       updated_at: loc.updatedAt, deleted_at: loc.deletedAt)
        }
        try await client.from("transaction_locations").upsert(rows).execute()
        markSynced(pairs.map { $0.1 }, uid: uid, context: context)
    }

    /// Sets `deleted_at` on the server for each locally-deleted row, then clears
    /// the entry. No-ops for rows that were never pushed (update affects 0 rows).
    private func pushDeletions(_ client: SupabaseClient) async throws {
        struct DeletionPatch: Encodable { let deleted_at: Date }
        let patch = DeletionPatch(deleted_at: Date())
        for entry in SyncDeletionQueue.all() {
            try await client.from(entry.table)
                .update(patch)
                .eq("id", value: entry.id.uuidString)
                .execute()
            SyncDeletionQueue.remove(entry)
        }
    }

    private func markSynced(_ models: [any SyncTrackable], uid: UUID, context: ModelContext) {
        // (sync-write guard is held for the whole syncNow operation)
        for case let m as (any SyncTrackable) in models {
            m.needsSync = false
            (m as? any SyncOwned)?.assignOwner(uid)
        }
        try? context.save()
    }

    // MARK: - Pull

    private func pullWallets(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncWalletRow] = try await fetchChanged("wallets", client, uid)
        guard !rows.isEmpty else { return }
        try applyLocal(table: "wallets", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
            if row.deleted_at != nil {
                if let existing = try fetchByID(Wallet.self, id: row.id, in: context) { context.delete(existing) }
                return
            }
            let w = try fetchByID(Wallet.self, id: row.id, in: context) ?? {
                let new = Wallet(name: row.name, currencyCode: row.currency_code, icon: row.icon, colorHex: row.color_hex)
                new.id = row.id
                context.insert(new)
                return new
            }()
            // LWW: keep local if it has a newer un-pushed change.
            if w.needsSync && w.updatedAt > row.updated_at { return }
            w.name = row.name; w.currencyCode = row.currency_code; w.icon = row.icon
            w.colorHex = row.color_hex; w.isArchived = row.is_archived
            w.createdAt = row.created_at; w.updatedAt = row.updated_at
            w.deletedAt = row.deleted_at; w.syncUserID = row.user_id; w.needsSync = false
        }
        try context.save()
    }

    private func pullCategories(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncCategoryRow] = try await fetchChanged("categories", client, uid)
        guard !rows.isEmpty else { return }
        try applyLocal(table: "categories", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
            if row.deleted_at != nil {
                if let existing = try fetchByID(Category.self, id: row.id, in: context) { context.delete(existing) }
                return
            }
            let c = try fetchByID(Category.self, id: row.id, in: context) ?? {
                let new = Category(name: row.name, icon: row.icon ?? "", colorHex: row.color_hex ?? "",
                                   type: TransactionType(rawValue: row.type) ?? .expense, isSystem: row.is_system)
                new.id = row.id
                context.insert(new)
                return new
            }()
            if c.needsSync && c.updatedAt > row.updated_at { return }
            c.name = row.name; c.icon = row.icon ?? ""; c.colorHex = row.color_hex ?? ""
            c.type = TransactionType(rawValue: row.type) ?? c.type; c.isSystem = row.is_system
            c.createdAt = row.created_at; c.updatedAt = row.updated_at
            c.deletedAt = row.deleted_at; c.syncUserID = row.user_id; c.needsSync = false
        }
        try context.save()
    }

    private func pullTransactions(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncTransactionRow] = try await fetchChanged("transactions", client, uid)
        guard !rows.isEmpty else { return }
        var pendingPhotoDownloads: [(UUID, String)] = []
        try applyLocal(table: "transactions", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
            if row.deleted_at != nil {
                if let existing = try fetchByID(Transaction.self, id: row.id, in: context) { context.delete(existing) }
                return
            }
            if let path = row.photo_path { pendingPhotoDownloads.append((row.id, path)) }
            let t = try fetchByID(Transaction.self, id: row.id, in: context) ?? {
                let new = Transaction(amount: row.amount, currencyCode: row.currency_code,
                                      date: row.date, type: TransactionType(rawValue: row.type) ?? .expense,
                                      exchangeRate: row.exchange_rate)
                new.id = row.id
                context.insert(new)
                return new
            }()
            if t.needsSync && t.updatedAt > row.updated_at { return }
            t.type = TransactionType(rawValue: row.type) ?? t.type
            t.date = row.date; t.note = row.note; t.tags = row.tags
            t.excludeFromReports = row.exclude_from_reports
            t.amount = row.amount; t.currencyCode = row.currency_code
            t.exchangeRate = row.exchange_rate; t.storedRate = row.stored_rate
            t.category = try row.category_id.flatMap { try fetchByID(Category.self, id: $0, in: context) }
            t.sourceWallet = try row.source_wallet_id.flatMap { try fetchByID(Wallet.self, id: $0, in: context) }
            t.destinationWallet = try row.destination_wallet_id.flatMap { try fetchByID(Wallet.self, id: $0, in: context) }
            t.event = try row.event_id.flatMap { try fetchByID(Event.self, id: $0, in: context) }
            t.recurringRule = try row.recurring_rule_id.flatMap { try fetchByID(RecurringRule.self, id: $0, in: context) }
            t.debt = try row.debt_id.flatMap { try fetchByID(Debt.self, id: $0, in: context) }
            t.savingsGoal = try row.savings_goal_id.flatMap { try fetchByID(SavingsGoal.self, id: $0, in: context) }
            t.createdAt = row.created_at; t.updatedAt = row.updated_at
            t.deletedAt = row.deleted_at; t.syncUserID = row.user_id; t.needsSync = false
        }
        try context.save()
        // Download receipt images for rows that have a path but no local data.
        for (id, path) in pendingPhotoDownloads {
            guard let t = try fetchByID(Transaction.self, id: id, in: context), t.photoData == nil else { continue }
            if let data = try? await downloadImage(path, client) { t.photoData = data }
        }
        if !pendingPhotoDownloads.isEmpty { try context.save() }
    }

    private func pullEvents(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncEventRow] = try await fetchChanged("events", client, uid)
        guard !rows.isEmpty else { return }
        var pendingCoverDownloads: [(UUID, String)] = []
        try applyLocal(table: "events", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
            if row.deleted_at != nil {
                if let existing = try fetchByID(Event.self, id: row.id, in: context) { context.delete(existing) }
                return
            }
            if let path = row.cover_image_path { pendingCoverDownloads.append((row.id, path)) }
            let e = try fetchByID(Event.self, id: row.id, in: context) ?? {
                let new = Event(title: row.title, startDate: row.start_date)
                new.id = row.id
                context.insert(new)
                return new
            }()
            if e.needsSync && e.updatedAt > row.updated_at { return }
            e.title = row.title; e.startDate = row.start_date; e.endDate = row.end_date
            e.totalBudget = row.total_budget; e.notes = row.notes; e.icon = row.icon
            e.colorHex = row.color_hex; e.location = row.location; e.status = row.status
            e.currencyCode = row.currency_code; e.ledgerRevision = row.ledger_revision
            e.confirmedSettlementRevision = row.confirmed_settlement_revision
            e.ledgerMode = EventLedgerMode(rawValue: row.ledger_mode) ?? .isolatedV1
            e.latitude = row.latitude; e.longitude = row.longitude
            e.updatedAt = row.updated_at; e.deletedAt = row.deleted_at
            e.syncUserID = row.user_id; e.needsSync = false
        }
        try context.save()
        for (id, path) in pendingCoverDownloads {
            guard let e = try fetchByID(Event.self, id: id, in: context), e.coverImageData == nil else { continue }
            if let data = try? await downloadImage(path, client) { e.coverImageData = data }
        }
        if !pendingCoverDownloads.isEmpty { try context.save() }
    }

    private func pullDebts(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncDebtRow] = try await fetchChanged("debts", client, uid)
        guard !rows.isEmpty else { return }
        try applyLocal(table: "debts", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
            if row.deleted_at != nil {
                if let existing = try fetchByID(Debt.self, id: row.id, in: context) { context.delete(existing) }
                return
            }
            let d = try fetchByID(Debt.self, id: row.id, in: context) ?? {
                let new = Debt(personName: row.person_name, totalAmount: row.total_amount,
                               currencyCode: row.currency_code, type: DebtType(rawValue: row.type) ?? .iOwe,
                               dueDate: row.due_date, note: row.note)
                new.id = row.id
                context.insert(new)
                return new
            }()
            if d.needsSync && d.updatedAt > row.updated_at { return }
            d.personName = row.person_name; d.totalAmount = row.total_amount; d.currencyCode = row.currency_code
            d.dueDate = row.due_date; d.type = DebtType(rawValue: row.type) ?? d.type; d.note = row.note
            d.dateCreated = row.date_created; d.isCompleted = row.is_completed
            d.createdAt = row.created_at; d.updatedAt = row.updated_at; d.deletedAt = row.deleted_at
            d.syncUserID = row.user_id; d.needsSync = false
        }
        try context.save()
    }

    private func pullSavingsGoals(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncSavingsGoalRow] = try await fetchChanged("savings_goals", client, uid)
        guard !rows.isEmpty else { return }
        try applyLocal(table: "savings_goals", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
            if row.deleted_at != nil {
                if let existing = try fetchByID(SavingsGoal.self, id: row.id, in: context) { context.delete(existing) }
                return
            }
            let g = try fetchByID(SavingsGoal.self, id: row.id, in: context) ?? {
                let new = SavingsGoal(name: row.name, targetAmount: row.target_amount,
                                      currencyCode: row.currency_code, targetDate: row.target_date,
                                      iconName: row.icon_name, colorHex: row.color_hex)
                new.id = row.id
                context.insert(new)
                return new
            }()
            if g.needsSync && g.updatedAt > row.updated_at { return }
            g.name = row.name; g.goalDescription = row.goal_description; g.targetAmount = row.target_amount
            g.currentAmount = row.current_amount; g.currencyCode = row.currency_code; g.targetDate = row.target_date
            g.createdDate = row.created_date; g.updatedAt = row.updated_at; g.iconName = row.icon_name
            g.colorHex = row.color_hex; g.isCompleted = row.is_completed; g.completedDate = row.completed_date
            g.autoContributeEnabled = row.auto_contribute_enabled
            g.autoContributeAmount = row.auto_contribute_amount
            g.autoContributePeriod = row.auto_contribute_period_raw.flatMap { BudgetPeriodType(rawValue: $0) }
            g.priority = row.priority
            g.linkedWallet = try row.linked_wallet_id.flatMap { try fetchByID(Wallet.self, id: $0, in: context) }
            g.deletedAt = row.deleted_at; g.syncUserID = row.user_id; g.needsSync = false
        }
        try context.save()
    }

    private func pullRecurringRules(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncRecurringRuleRow] = try await fetchChanged("recurring_rules", client, uid)
        guard !rows.isEmpty else { return }
        try applyLocal(table: "recurring_rules", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
            if row.deleted_at != nil {
                if let existing = try fetchByID(RecurringRule.self, id: row.id, in: context) { context.delete(existing) }
                return
            }
            let r = try fetchByID(RecurringRule.self, id: row.id, in: context) ?? {
                let new = RecurringRule(name: row.name, amount: row.amount, currencyCode: row.currency_code,
                                        frequency: Frequency(rawValue: row.frequency) ?? .monthly,
                                        startDate: row.start_date)
                new.id = row.id
                context.insert(new)
                return new
            }()
            if r.needsSync && r.updatedAt > row.updated_at { return }
            r.name = row.name; r.amount = row.amount; r.currencyCode = row.currency_code
            r.frequency = Frequency(rawValue: row.frequency) ?? r.frequency
            r.startDate = row.start_date; r.nextDueDate = row.next_due_date; r.isActive = row.is_active
            r.wallet = try row.wallet_id.flatMap { try fetchByID(Wallet.self, id: $0, in: context) }
            r.category = try row.category_id.flatMap { try fetchByID(Category.self, id: $0, in: context) }
            r.updatedAt = row.updated_at; r.deletedAt = row.deleted_at
            r.syncUserID = row.user_id; r.needsSync = false
        }
        try context.save()
    }

    private func pullEventMembers(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncEventMemberRow] = try await fetchChanged("event_members", client, uid)
        guard !rows.isEmpty else { return }
        var pendingAvatarDownloads: [(UUID, String)] = []
        try applyLocal(table: "event_members", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
            if row.deleted_at != nil {
                if let dead = try fetchByID(EventMember.self, id: row.id, in: context) { context.delete(dead) }
                return
            }
            if let path = row.avatar_path { pendingAvatarDownloads.append((row.id, path)) }
            let existing = try fetchByID(EventMember.self, id: row.id, in: context)
            let m: EventMember
            if let existing { m = existing } else {
                let ev = try row.event_id.flatMap { try fetchByID(Event.self, id: $0, in: context) }
                m = EventMember(name: row.name, event: ev)
                m.id = row.id
                context.insert(m)
            }
            if m.needsSync && m.updatedAt > row.updated_at { return }
            m.name = row.name; m.avatarIcon = row.avatar_icon; m.colorHex = row.color_hex
            m.isArchived = row.is_archived; m.isLocalUser = row.is_local_user; m.isBudgetPool = row.is_budget_pool
            m.sortOrder = row.sort_order; m.createdAt = row.created_at; m.updatedAt = row.updated_at
            m.event = try row.event_id.flatMap { try fetchByID(Event.self, id: $0, in: context) }
            m.deletedAt = row.deleted_at; m.syncUserID = row.user_id; m.needsSync = false
        }
        try context.save()
        for (id, path) in pendingAvatarDownloads {
            guard let m = try fetchByID(EventMember.self, id: id, in: context), m.avatarData == nil else { continue }
            if let data = try? await downloadImage(path, client) { m.avatarData = data }
        }
        if !pendingAvatarDownloads.isEmpty { try context.save() }
    }

    private func pullEventLedgerTransactions(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncEventLedgerTransactionRow] = try await fetchChanged("event_ledger_transactions", client, uid)
        guard !rows.isEmpty else { return }
        try applyLocal(table: "event_ledger_transactions", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
            if row.deleted_at != nil {
                if let dead = try fetchByID(EventLedgerTransaction.self, id: row.id, in: context) { context.delete(dead) }
                return
            }
            let existing = try fetchByID(EventLedgerTransaction.self, id: row.id, in: context)
            let t: EventLedgerTransaction
            if let existing { t = existing } else {
                let ev = try row.event_id.flatMap { try fetchByID(Event.self, id: $0, in: context) }
                t = EventLedgerTransaction(
                    kind: EventLedgerTransactionKind(rawValue: row.kind) ?? .expense, title: row.title,
                    amountMinor: row.amount_minor, paidSource: EventExpensePaidSource(rawValue: row.paid_source) ?? .member,
                    paidByMemberId: row.paid_by_member_id, splitType: EventSplitType(rawValue: row.split_type) ?? .equal,
                    date: row.date, note: row.note, categoryId: row.category_id, categoryName: row.category_name,
                    categoryIcon: row.category_icon, categoryColorHex: row.category_color_hex, event: ev)
                t.id = row.id
                context.insert(t)
            }
            if t.needsSync && t.updatedAt > row.updated_at { return }
            t.kind = EventLedgerTransactionKind(rawValue: row.kind) ?? t.kind
            t.title = row.title; t.amountMinor = row.amount_minor
            t.paidSource = EventExpensePaidSource(rawValue: row.paid_source) ?? t.paidSource
            t.paidByMemberId = row.paid_by_member_id
            t.splitType = EventSplitType(rawValue: row.split_type) ?? t.splitType
            t.date = row.date; t.note = row.note; t.categoryId = row.category_id
            t.categoryName = row.category_name; t.categoryIcon = row.category_icon
            t.categoryColorHex = row.category_color_hex; t.isSplitAll = row.is_split_all; t.isDeleted = row.is_deleted
            t.event = try row.event_id.flatMap { try fetchByID(Event.self, id: $0, in: context) }
            t.createdAt = row.created_at; t.updatedAt = row.updated_at; t.deletedAt = row.deleted_at
            t.syncUserID = row.user_id; t.needsSync = false
        }
        try context.save()
    }

    private func pullEventLedgerParticipants(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncEventLedgerParticipantRow] = try await fetchChanged("event_ledger_participants", client, uid)
        guard !rows.isEmpty else { return }
        try applyLocal(table: "event_ledger_participants", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
            if row.deleted_at != nil {
                if let dead = try fetchByID(EventLedgerParticipant.self, id: row.id, in: context) { context.delete(dead) }
                return
            }
            let existing = try fetchByID(EventLedgerParticipant.self, id: row.id, in: context)
            let p: EventLedgerParticipant
            if let existing { p = existing } else {
                let txn = try row.transaction_id.flatMap { try fetchByID(EventLedgerTransaction.self, id: $0, in: context) }
                let mem = try row.event_member_id.flatMap { try fetchByID(EventMember.self, id: $0, in: context) }
                p = EventLedgerParticipant(memberId: row.member_id, orderIndex: row.order_index, transaction: txn, member: mem)
                p.id = row.id
                context.insert(p)
            }
            if p.needsSync && p.updatedAt > row.updated_at { return }
            p.memberId = row.member_id; p.orderIndex = row.order_index
            p.transaction = try row.transaction_id.flatMap { try fetchByID(EventLedgerTransaction.self, id: $0, in: context) }
            p.member = try row.event_member_id.flatMap { try fetchByID(EventMember.self, id: $0, in: context) }
            p.updatedAt = row.updated_at; p.deletedAt = row.deleted_at
            p.syncUserID = row.user_id; p.needsSync = false
        }
        try context.save()
    }

    private func pullEventSettlementSnapshots(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncEventSettlementSnapshotRow] = try await fetchChanged("event_settlement_snapshots", client, uid)
        guard !rows.isEmpty else { return }
        try applyLocal(table: "event_settlement_snapshots", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
            if row.deleted_at != nil {
                if let dead = try fetchByID(EventSettlementSnapshot.self, id: row.id, in: context) { context.delete(dead) }
                return
            }
            let existing = try fetchByID(EventSettlementSnapshot.self, id: row.id, in: context)
            let s: EventSettlementSnapshot
            if let existing { s = existing } else {
                let ev = try row.event_id.flatMap { try fetchByID(Event.self, id: $0, in: context) }
                s = EventSettlementSnapshot(ledgerRevision: row.ledger_revision, event: ev)
                s.id = row.id
                context.insert(s)
            }
            if s.needsSync && s.updatedAt > row.updated_at { return }
            s.ledgerRevision = row.ledger_revision
            s.event = try row.event_id.flatMap { try fetchByID(Event.self, id: $0, in: context) }
            s.createdAt = row.created_at; s.updatedAt = row.updated_at; s.deletedAt = row.deleted_at
            s.syncUserID = row.user_id; s.needsSync = false
        }
        try context.save()
    }

    private func pullEventSettlementTransfers(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncEventSettlementTransferRow] = try await fetchChanged("event_settlement_transfers", client, uid)
        guard !rows.isEmpty else { return }
        try applyLocal(table: "event_settlement_transfers", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
            if row.deleted_at != nil {
                if let dead = try fetchByID(EventSettlementTransfer.self, id: row.id, in: context) { context.delete(dead) }
                return
            }
            let existing = try fetchByID(EventSettlementTransfer.self, id: row.id, in: context)
            let t: EventSettlementTransfer
            if let existing { t = existing } else {
                let snap = try row.snapshot_id.flatMap { try fetchByID(EventSettlementSnapshot.self, id: $0, in: context) }
                t = EventSettlementTransfer(fromMemberId: row.from_member_id, toMemberId: row.to_member_id,
                                            amountMinor: row.amount_minor, sequence: row.sequence, snapshot: snap)
                t.id = row.id
                context.insert(t)
            }
            if t.needsSync && t.updatedAt > row.updated_at { return }
            t.fromMemberId = row.from_member_id; t.toMemberId = row.to_member_id
            t.amountMinor = row.amount_minor; t.sequence = row.sequence
            t.snapshot = try row.snapshot_id.flatMap { try fetchByID(EventSettlementSnapshot.self, id: $0, in: context) }
            t.updatedAt = row.updated_at; t.deletedAt = row.deleted_at
            t.syncUserID = row.user_id; t.needsSync = false
        }
        try context.save()
    }

    private func pullEventWalletExportRecords(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncEventWalletExportRecordRow] = try await fetchChanged("event_wallet_export_records", client, uid)
        guard !rows.isEmpty else { return }
        try applyLocal(table: "event_wallet_export_records", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
            if row.deleted_at != nil {
                if let dead = try fetchByID(EventWalletExportRecord.self, id: row.id, in: context) { context.delete(dead) }
                return
            }
            let existing = try fetchByID(EventWalletExportRecord.self, id: row.id, in: context)
            let r: EventWalletExportRecord
            if let existing { r = existing } else {
                let ev = try row.event_id.flatMap { try fetchByID(Event.self, id: $0, in: context) }
                let snap = try row.snapshot_id.flatMap { try fetchByID(EventSettlementSnapshot.self, id: $0, in: context) }
                r = EventWalletExportRecord(memberId: row.member_id, walletTransactionId: row.wallet_transaction_id,
                                            amountMinor: row.amount_minor,
                                            direction: EventWalletExportDirection(rawValue: row.direction) ?? .expense,
                                            exportType: EventWalletExportType(rawValue: row.export_type) ?? .settlement,
                                            event: ev, snapshot: snap)
                r.id = row.id
                context.insert(r)
            }
            if r.needsSync && r.updatedAt > row.updated_at { return }
            r.memberId = row.member_id; r.walletTransactionId = row.wallet_transaction_id
            r.amountMinor = row.amount_minor
            r.direction = EventWalletExportDirection(rawValue: row.direction) ?? r.direction
            r.exportType = EventWalletExportType(rawValue: row.export_type) ?? r.exportType
            r.event = try row.event_id.flatMap { try fetchByID(Event.self, id: $0, in: context) }
            r.snapshot = try row.snapshot_id.flatMap { try fetchByID(EventSettlementSnapshot.self, id: $0, in: context) }
            r.createdAt = row.created_at; r.updatedAt = row.updated_at; r.deletedAt = row.deleted_at
            r.syncUserID = row.user_id; r.needsSync = false
        }
        try context.save()
    }

    private func pullBudgets(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncBudgetRow] = try await fetchChanged("budgets", client, uid)
        guard !rows.isEmpty else { return }
        // Category join rows (no cursor; small set). Map budget → category ids.
        let joinRows: [SyncBudgetCategoryRow] = try await client.from("budget_categories")
            .select().eq("user_id", value: uid.uuidString).execute().value
        let joinMap = Dictionary(grouping: joinRows, by: { $0.budget_id }).mapValues { $0.map(\.category_id) }
        try applyLocal(table: "budgets", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
            if row.deleted_at != nil {
                if let dead = try fetchByID(Budget.self, id: row.id, in: context) { context.delete(dead) }
                return
            }
            let existing = try fetchByID(Budget.self, id: row.id, in: context)
            let b: Budget
            if let existing { b = existing } else {
                b = Budget(amountLimit: row.amount_limit)
                b.id = row.id
                context.insert(b)
            }
            if b.needsSync && b.updatedAt > row.updated_at { return }
            b.name = row.name; b.amountLimit = row.amount_limit; b.currencyCode = row.currency_code
            b.periodType = BudgetPeriodType(rawValue: row.period_type_raw) ?? .monthly
            b.startDate = row.start_date; b.createdAt = row.created_at; b.updatedAt = row.updated_at
            b.customEndDate = row.custom_end_date; b.month = row.month; b.year = row.year
            b.isRecurring = row.is_recurring; b.rolloverExcess = row.rollover_excess
            b.rolloverAmount = row.rollover_amount
            b.alertAt50 = row.alert_at_50; b.alertAt80 = row.alert_at_80; b.alertAt100 = row.alert_at_100
            b.alertOnProjectedOverspend = row.alert_on_projected_overspend
            b.lastAlertTriggeredDate = row.last_alert_triggered_date
            b.lastAlertThreshold = row.last_alert_threshold
            b.budgetCategoryType = row.budget_category_type_raw.flatMap { BudgetCategoryType(rawValue: $0) }
            b.category = try row.category_id.flatMap { try fetchByID(Category.self, id: $0, in: context) }
            b.categories = try (joinMap[row.id] ?? []).compactMap { try fetchByID(Category.self, id: $0, in: context) }
            if let raw = row.amount_type_data, let data = raw.data(using: .utf8),
               let amountType = BudgetAmountType.decode(from: data) {
                b.amountType = amountType
            }
            b.deletedAt = row.deleted_at; b.syncUserID = row.user_id; b.needsSync = false
        }
        try context.save()
    }

    private func pullTransactionLocations(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncTransactionLocationRow] = try await fetchChanged("transaction_locations", client, uid)
        guard !rows.isEmpty else { return }
        try applyLocal(table: "transaction_locations", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
            if row.deleted_at != nil {
                if let dead = try fetchByID(TransactionLocation.self, id: row.id, in: context) { context.delete(dead) }
                return
            }
            let existing = try fetchByID(TransactionLocation.self, id: row.id, in: context)
            let loc: TransactionLocation
            if let existing { loc = existing } else {
                loc = TransactionLocation(latitude: row.latitude, longitude: row.longitude,
                                          source: TransactionLocationSource(rawValue: row.source_raw) ?? .manual)
                loc.id = row.id
                context.insert(loc)
            }
            if loc.needsSync && loc.updatedAt > row.updated_at { return }
            loc.displayName = row.display_name; loc.fullAddress = row.full_address
            loc.shortAddress = row.short_address; loc.latitude = row.latitude; loc.longitude = row.longitude
            loc.horizontalAccuracyMeters = row.horizontal_accuracy_meters; loc.capturedAt = row.captured_at
            loc.sourceRaw = row.source_raw; loc.applePlaceID = row.apple_place_id
            loc.alternateApplePlaceIDs = row.alternate_apple_place_ids
            loc.pointOfInterestCategoryRaw = row.point_of_interest_category_raw
            loc.locality = row.locality; loc.administrativeArea = row.administrative_area
            loc.countryCode = row.country_code; loc.normalizedSpatialKey = row.normalized_spatial_key
            loc.updatedAt = row.updated_at; loc.deletedAt = row.deleted_at
            loc.syncUserID = row.user_id; loc.needsSync = false
            // Link to its owning transaction.
            if let tid = row.transaction_id, let t = try fetchByID(Transaction.self, id: tid, in: context) {
                t.location = loc
            }
        }
        try context.save()
    }

    // MARK: - Helpers

    private func fetchChanged<Row: Decodable>(_ table: String, _ client: SupabaseClient, _ uid: UUID) async throws -> [Row] {
        var query = client.from(table).select().eq("user_id", value: uid.uuidString)
        if let cursor = Self.cursorString(for: table) {
            query = query.gt("updated_at", value: cursor)
        }
        return try await query.execute().value
    }

    /// Applies pulled rows under the sync-write guard and advances the cursor.
    private func applyLocal<Row>(
        table: String,
        rows: [Row],
        context: ModelContext,
        rowDate: (Row) -> Date,
        rowID: (Row) -> UUID,
        apply: (Row) throws -> Void
    ) rethrows {
        // (sync-write guard is held for the whole syncNow operation)
        var maxDate = Self.cursorDate(for: table) ?? .distantPast
        for row in rows {
            try apply(row)
            maxDate = max(maxDate, rowDate(row))
        }
        Self.setCursor(maxDate, for: table)
    }

    private func fetchByID<T: PersistentModel>(_ type: T.Type, id: UUID, in context: ModelContext) throws -> T? {
        // Concrete predicates per type (PersistentModel id isn't usable generically in #Predicate).
        if T.self == Wallet.self {
            return try context.fetch(FetchDescriptor<Wallet>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == Category.self {
            return try context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == Transaction.self {
            return try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == Event.self {
            return try context.fetch(FetchDescriptor<Event>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == Debt.self {
            return try context.fetch(FetchDescriptor<Debt>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == SavingsGoal.self {
            return try context.fetch(FetchDescriptor<SavingsGoal>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == RecurringRule.self {
            return try context.fetch(FetchDescriptor<RecurringRule>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == EventMember.self {
            return try context.fetch(FetchDescriptor<EventMember>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == EventLedgerTransaction.self {
            return try context.fetch(FetchDescriptor<EventLedgerTransaction>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == EventLedgerParticipant.self {
            return try context.fetch(FetchDescriptor<EventLedgerParticipant>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == EventSettlementSnapshot.self {
            return try context.fetch(FetchDescriptor<EventSettlementSnapshot>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == EventSettlementTransfer.self {
            return try context.fetch(FetchDescriptor<EventSettlementTransfer>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == EventWalletExportRecord.self {
            return try context.fetch(FetchDescriptor<EventWalletExportRecord>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == Budget.self {
            return try context.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == TransactionLocation.self {
            return try context.fetch(FetchDescriptor<TransactionLocation>(predicate: #Predicate { $0.id == id })).first as? T
        }
        return nil
    }

    // MARK: - Storage (images)

    /// Storage object path. The first folder MUST be the lowercased user id to
    /// satisfy the receipts-bucket RLS policy (compares to auth.uid()::text).
    private func imagePath(_ uid: UUID, _ folder: String, _ id: UUID) -> String {
        "\(uid.uuidString.lowercased())/\(folder)/\(id.uuidString.lowercased()).jpg"
    }

    private func uploadImage(_ data: Data, to path: String, _ client: SupabaseClient) async throws {
        _ = try await client.storage.from("receipts").upload(
            path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
    }

    private func downloadImage(_ path: String, _ client: SupabaseClient) async throws -> Data {
        try await client.storage.from("receipts").download(path: path)
    }

    // MARK: - Cursor persistence (per table, UserDefaults)

    private static func cursorKey(_ table: String) -> String { "syncCursor.v1.\(table)" }

    private static func cursorDate(for table: String) -> Date? {
        let t = UserDefaults.standard.double(forKey: cursorKey(table))
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    private static func cursorString(for table: String) -> String? {
        guard let date = cursorDate(for: table) else { return nil }
        return isoFormatter.string(from: date)
    }

    private static func setCursor(_ date: Date, for table: String) {
        guard date > .distantPast else { return }
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: cursorKey(table))
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

/// Lets `markSynced` stamp the owner uniformly across entity types.
protocol SyncOwned: AnyObject {
    func assignOwner(_ uid: UUID)
}
extension Wallet: SyncOwned { func assignOwner(_ uid: UUID) { syncUserID = uid } }
extension Category: SyncOwned { func assignOwner(_ uid: UUID) { syncUserID = uid } }
extension Transaction: SyncOwned { func assignOwner(_ uid: UUID) { syncUserID = uid } }
extension Event: SyncOwned { func assignOwner(_ uid: UUID) { syncUserID = uid } }
extension Debt: SyncOwned { func assignOwner(_ uid: UUID) { syncUserID = uid } }
extension SavingsGoal: SyncOwned { func assignOwner(_ uid: UUID) { syncUserID = uid } }
extension RecurringRule: SyncOwned { func assignOwner(_ uid: UUID) { syncUserID = uid } }
extension EventMember: SyncOwned { func assignOwner(_ uid: UUID) { syncUserID = uid } }
extension EventLedgerTransaction: SyncOwned { func assignOwner(_ uid: UUID) { syncUserID = uid } }
extension EventLedgerParticipant: SyncOwned { func assignOwner(_ uid: UUID) { syncUserID = uid } }
extension EventSettlementSnapshot: SyncOwned { func assignOwner(_ uid: UUID) { syncUserID = uid } }
extension EventSettlementTransfer: SyncOwned { func assignOwner(_ uid: UUID) { syncUserID = uid } }
extension EventWalletExportRecord: SyncOwned { func assignOwner(_ uid: UUID) { syncUserID = uid } }
extension Budget: SyncOwned { func assignOwner(_ uid: UUID) { syncUserID = uid } }
extension TransactionLocation: SyncOwned { func assignOwner(_ uid: UUID) { syncUserID = uid } }
