import Foundation
import SwiftData

/// Maps a synced model instance to its Supabase table name.
enum SyncTableRegistry {
    static func tableName(for model: AnyObject) -> String? {
        switch model {
        case is Wallet: return "wallets"
        case is Category: return "categories"
        case is Transaction: return "transactions"
        case is Event: return "events"
        case is Debt: return "debts"
        case is SavingsGoal: return "savings_goals"
        case is RecurringRule: return "recurring_rules"
        case is EventMember: return "event_members"
        case is EventLedgerTransaction: return "event_ledger_transactions"
        case is EventLedgerParticipant: return "event_ledger_participants"
        case is EventSettlementSnapshot: return "event_settlement_snapshots"
        case is EventSettlementTransfer: return "event_settlement_transfers"
        case is EventWalletExportRecord: return "event_wallet_export_records"
        case is Budget: return "budgets"
        case is TransactionLocation: return "transaction_locations"
        default: return nil
        }
    }

    static func tableName(forEntityName entityName: String) -> String? {
        switch entityName {
        case "Wallet": return "wallets"
        case "Category": return "categories"
        case "Transaction": return "transactions"
        case "Event": return "events"
        case "Debt": return "debts"
        case "SavingsGoal": return "savings_goals"
        case "RecurringRule": return "recurring_rules"
        case "EventMember": return "event_members"
        case "EventLedgerTransaction": return "event_ledger_transactions"
        case "EventLedgerParticipant": return "event_ledger_participants"
        case "EventSettlementSnapshot": return "event_settlement_snapshots"
        case "EventSettlementTransfer": return "event_settlement_transfers"
        case "EventWalletExportRecord": return "event_wallet_export_records"
        case "Budget": return "budgets"
        case "TransactionLocation": return "transaction_locations"
        default: return nil
        }
    }

}

/// Durable queue of locally-deleted rows awaiting a server tombstone (deleted_at).
///
/// Local deletions are hard deletes (SwiftData cascades work), so we cannot rely
/// on a row still existing to push it. Instead the `willSave` hook records each
/// deleted row's table + id here; the sync engine sets `deleted_at` on the server
/// for each, then other devices hard-delete their copies on pull.
///
/// Backed by UserDefaults (deletions are infrequent) to survive relaunches.
enum SyncDeletionQueue {
    struct Entry: Codable, Hashable {
        let table: String
        let id: UUID
    }

    private static let key = "pendingDeletions.v1"

    static func enqueue(table: String, id: UUID) {
        var entries = all()
        let entry = Entry(table: table, id: id)
        guard !entries.contains(entry) else { return }
        entries.append(entry)
        save(entries)
    }

    static func all() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }

    static func remove(_ entry: Entry) {
        var entries = all()
        entries.removeAll { $0 == entry }
        save(entries)
    }

    /// Drops all queued deletions (used when switching accounts on a device).
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func save(_ entries: [Entry]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: key)
    }
}
