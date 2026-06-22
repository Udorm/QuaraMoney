import Foundation
import SwiftData

/// Centralized soft-delete with explicit cascade semantics.
///
/// Why soft delete: deletions must replicate to other devices. A hard
/// `context.delete` removes the row, so there's nothing to push; it also fires
/// SwiftData's referential rules (e.g. Category→Transaction `.deny`), which is
/// what crashed the pull on the receiving device. Setting `deletedAt` instead
/// turns a deletion into an ordinary field change that syncs like any edit, and
/// trips no delete rules.
///
/// Reads must exclude tombstones with `deletedAt == nil` (see `#Predicate`
/// filters on `@Query`/`FetchDescriptor`). `markSoftDeleted()` also stamps
/// `needsSync`/`updatedAt` so the push picks it up.
@MainActor
enum SoftDeleteService {

    /// What to do with a wallet's transactions when the wallet is deleted.
    enum WalletDeletionStrategy {
        /// Move the transactions to another wallet (preserves history).
        case move(to: Wallet)
        /// Soft-delete the transactions along with the wallet.
        case deleteTransactions
    }

    // MARK: - Transaction

    /// Soft-deletes a transaction and its owned location, refreshing affected
    /// wallet balances.
    static func deleteTransaction(_ transaction: Transaction) {
        transaction.sourceWallet?.invalidateBalanceCache()
        transaction.destinationWallet?.invalidateBalanceCache()
        transaction.location?.markSoftDeleted()
        transaction.markSoftDeleted()
    }

    // MARK: - Category

    /// Soft-deletes a category. Its transactions are **kept** (history is never
    /// destroyed) and become uncategorized, mirroring a `.nullify` rule.
    static func deleteCategory(_ category: Category) {
        category.transactions?.forEach { txn in
            txn.category = nil          // uncategorize — do NOT delete the transaction
            txn.updatedAt = Date()
            txn.needsSync = true
        }
        category.markSoftDeleted()
    }

    // MARK: - Wallet

    /// Soft-deletes a wallet, either moving its transactions to another wallet
    /// or soft-deleting them too.
    static func deleteWallet(_ wallet: Wallet, strategy: WalletDeletionStrategy) {
        switch strategy {
        case .move(let target):
            moveOutgoingTransactions(from: wallet, to: target)
            moveIncomingTransfers(from: wallet, to: target)
            target.invalidateBalanceCache()
        case .deleteTransactions:
            wallet.outgoingTransactions?.forEach { deleteTransaction($0) }
            // Incoming transfers are `.nullify` — just detach the destination.
            wallet.incomingTransactions?.forEach { txn in
                txn.destinationWallet = nil
                txn.updatedAt = Date(); txn.needsSync = true
            }
        }
        wallet.invalidateBalanceCache()
        wallet.markSoftDeleted()
    }

    // MARK: - Debt

    /// Soft-deletes a debt and its cascade-linked wallet transactions.
    static func deleteDebt(_ debt: Debt) {
        debt.transactions?.forEach { deleteTransaction($0) }
        debt.markSoftDeleted()
    }

    // MARK: - Event

    /// Soft-deletes an event and all its owned children (members, ledger
    /// transactions + participants, settlement snapshots + transfers, export
    /// records). Personal wallet transactions linked to the event are detached
    /// (`.nullify`) and kept.
    static func deleteEvent(_ event: Event) {
        event.transactions?.forEach { txn in
            txn.event = nil
            txn.updatedAt = Date(); txn.needsSync = true
            txn.sourceWallet?.invalidateBalanceCache()
            txn.destinationWallet?.invalidateBalanceCache()
        }
        event.members?.forEach { $0.markSoftDeleted() }
        event.ledgerTransactions?.forEach { lt in
            lt.participants?.forEach { $0.markSoftDeleted() }
            lt.markSoftDeleted()
        }
        event.settlementSnapshots?.forEach { snap in
            snap.transfers?.forEach { $0.markSoftDeleted() }
            snap.markSoftDeleted()
        }
        event.walletExportRecords?.forEach { $0.markSoftDeleted() }
        event.markSoftDeleted()
    }

    // MARK: - Generic single-entity soft delete

    static func delete(_ model: any SyncTrackable) {
        model.markSoftDeleted()
    }

    // MARK: - Wallet-move helpers

    private static func moveOutgoingTransactions(from wallet: Wallet, to target: Wallet) {
        wallet.outgoingTransactions?.forEach { txn in
            if txn.type == .transfer {
                recomputeTransferRate(txn, newSourceCurrency: target.currencyCode)
            }
            txn.sourceWallet = target
            txn.updatedAt = Date(); txn.needsSync = true
        }
    }

    private static func moveIncomingTransfers(from wallet: Wallet, to target: Wallet) {
        wallet.incomingTransactions?.forEach { txn in
            guard txn.type == .transfer else { return }
            recomputeIncomingTransferRate(txn, newDestCurrency: target.currencyCode)
            txn.destinationWallet = target
            txn.updatedAt = Date(); txn.needsSync = true
        }
    }

    /// Recomputes a transfer's stored rate after its **source** wallet changes
    /// currency. storedRate is dest-per-source units.
    private static func recomputeTransferRate(_ txn: Transaction, newSourceCurrency: String) {
        let destCurrency = txn.destinationWallet?.currencyCode ?? newSourceCurrency
        txn.storedRate = rate(from: newSourceCurrency, to: destCurrency)
        txn.exchangeRate = txn.storedRate ?? 1.0
    }

    /// Recomputes a transfer's stored rate after its **destination** wallet
    /// changes currency.
    private static func recomputeIncomingTransferRate(_ txn: Transaction, newDestCurrency: String) {
        let sourceCurrency = txn.sourceWallet?.currencyCode ?? newDestCurrency
        txn.storedRate = rate(from: sourceCurrency, to: newDestCurrency)
        txn.exchangeRate = txn.storedRate ?? 1.0
    }

    /// dest-per-source conversion using current rates, falling back to constants.
    private static func rate(from source: String, to dest: String) -> Decimal {
        if source == dest { return 1.0 }
        let manager = CurrencyManager.shared
        if let s = manager.rates[source], let d = manager.rates[dest], s > 0 {
            return Decimal(d / s)
        }
        let fallback = CurrencyManager.fallbackRates
        if let s = fallback[source], let d = fallback[dest], s > 0 {
            return Decimal(d / s)
        }
        return 1.0
    }
}
