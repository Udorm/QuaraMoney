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

    private init() {}

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

        do {
            // Push parents → children.
            try await pushWallets(context, client, uid)
            try await pushCategories(context, client, uid)
            try await pushTransactions(context, client, uid)

            // Pull parents → children.
            try await pullWallets(context, client, uid)
            try await pullCategories(context, client, uid)
            try await pullTransactions(context, client, uid)

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
        let rows = pending.map { t in
            SyncTransactionRow(
                id: t.id, user_id: uid, type: t.type.rawValue, date: t.date, note: t.note,
                tags: t.tags, exclude_from_reports: t.excludeFromReports, amount: t.amount,
                currency_code: t.currencyCode, exchange_rate: t.exchangeRate, stored_rate: t.storedRate,
                photo_path: nil, // Storage upload added in a later increment
                category_id: t.category?.id,
                event_id: nil, source_wallet_id: t.sourceWallet?.id,
                destination_wallet_id: t.destinationWallet?.id,
                recurring_rule_id: nil, debt_id: nil, savings_goal_id: nil,
                created_at: t.createdAt, updated_at: t.updatedAt, deleted_at: t.deletedAt)
        }
        try await client.from("transactions").upsert(rows).execute()
        markSynced(pending, uid: uid, context: context)
    }

    private func markSynced(_ models: [any SyncTrackable], uid: UUID, context: ModelContext) {
        SyncMutationTracker.isApplyingSyncChanges = true
        defer { SyncMutationTracker.isApplyingSyncChanges = false }
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
        try applyLocal(table: "transactions", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
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
            t.createdAt = row.created_at; t.updatedAt = row.updated_at
            t.deletedAt = row.deleted_at; t.syncUserID = row.user_id; t.needsSync = false
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
        SyncMutationTracker.isApplyingSyncChanges = true
        defer { SyncMutationTracker.isApplyingSyncChanges = false }
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
        }
        return nil
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
