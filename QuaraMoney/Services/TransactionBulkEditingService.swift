import Foundation
import SwiftData

/// One reversible bulk mutation.
///
/// Every mutation in ``TransactionBulkEditingService`` returns one of these so
/// the caller can drive a single Undo affordance without knowing which fields
/// were touched: the mutation itself records precise per-transaction reverts at
/// the moment it captures the old values. Keeping the revert next to the write
/// is what makes "undo everything" cheap — the alternative (a universal field
/// snapshot) has to guess which relationships matter for each kind of edit.
///
/// `@MainActor` because the reverts write to `ModelContext`-owned models.
@MainActor
struct TransactionBulkMutation: Identifiable {
    let id = UUID()

    /// Localized past-tense summary shown in the Undo toast.
    let summary: String

    /// How many transactions the mutation actually wrote to.
    let changedCount: Int

    /// How many selected transactions were ineligible and left untouched.
    let skippedCount: Int

    fileprivate let reverts: [() -> Void]

    /// Reapplies the pre-mutation state and commits it as one save.
    func revert(in modelContext: ModelContext) throws {
        for revert in reverts { revert() }
        try modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
}

/// Applies one mutation to a transaction selection and commits it as a single
/// SwiftData save. Keeping the mutations here makes every transaction-list
/// surface share the same validation, eligibility rules and sync bookkeeping.
///
/// Eligibility is *filtering*, not failure: a mixed selection applies the edit
/// to the rows that can take it and reports the rest via
/// ``TransactionBulkMutation/skippedCount`` so the UI can say "12 of 15".
/// A mutation only throws when nothing at all could be applied.
@MainActor
enum TransactionBulkEditingService {
    enum BulkEditError: Error, Equatable {
        case emptySelection
        case incompatibleCategory
        case invalidTag
        /// Every selected transaction was ineligible for the requested edit.
        case noEligibleTransactions

        @MainActor
        var localizedMessage: String {
            switch self {
            case .emptySelection:
                return "transaction.bulk.error.emptySelection".localized
            case .incompatibleCategory:
                return "transaction.bulk.error.incompatibleCategory".localized
            case .invalidTag:
                return "transaction.bulk.error.invalidTag".localized
            case .noEligibleTransactions:
                return "transaction.bulk.error.noEligible".localized
            }
        }
    }

    // MARK: - Category

    static func changeCategory(
        of transactions: [Transaction],
        to category: Category,
        in modelContext: ModelContext
    ) throws -> TransactionBulkMutation {
        guard !transactions.isEmpty else { throw BulkEditError.emptySelection }
        guard (category.type == .income || category.type == .expense),
              transactions.allSatisfy({
                  $0.type == category.type && $0.debt == nil && $0.deletedAt == nil
              }) else {
            throw BulkEditError.incompatibleCategory
        }

        let timestamp = Date()
        var reverts: [() -> Void] = []
        for transaction in transactions {
            let previousCategory = transaction.category
            let previousUpdatedAt = transaction.updatedAt
            reverts.append {
                transaction.category = previousCategory
                transaction.updatedAt = previousUpdatedAt
                transaction.needsSync = true
            }
            transaction.category = category
            markUpdated(transaction, at: timestamp)
        }
        try commit(modelContext)
        return TransactionBulkMutation(
            summary: "transaction.bulk.undo.category".localized(with: transactions.count),
            changedCount: transactions.count,
            skippedCount: 0,
            reverts: reverts
        )
    }

    // MARK: - Tags

    static func addTag(
        _ rawTag: String,
        to transactions: [Transaction],
        in modelContext: ModelContext
    ) throws -> TransactionBulkMutation {
        try mutateTag(rawTag, on: transactions, in: modelContext, summaryKey: "transaction.bulk.undo.addTag") { tag, note in
            TransactionTagParser.adding(tag: tag, to: note)
        }
    }

    static func removeTag(
        _ rawTag: String,
        from transactions: [Transaction],
        in modelContext: ModelContext
    ) throws -> TransactionBulkMutation {
        try mutateTag(rawTag, on: transactions, in: modelContext, summaryKey: "transaction.bulk.undo.removeTag") { tag, note in
            TransactionTagParser.removing(tag: tag, from: note)
        }
    }

    private static func mutateTag(
        _ rawTag: String,
        on transactions: [Transaction],
        in modelContext: ModelContext,
        summaryKey: String,
        transform: (String, String?) -> String?
    ) throws -> TransactionBulkMutation {
        guard !transactions.isEmpty else { throw BulkEditError.emptySelection }
        guard let tag = TransactionTagParser.normalizedTag(rawTag) else {
            throw BulkEditError.invalidTag
        }

        let eligible = transactions.filter { $0.deletedAt == nil }
        guard !eligible.isEmpty else { throw BulkEditError.noEligibleTransactions }

        let timestamp = Date()
        var reverts: [() -> Void] = []
        for transaction in eligible {
            let previousNote = transaction.note
            let previousTags = transaction.tags
            let previousUpdatedAt = transaction.updatedAt
            reverts.append {
                transaction.note = previousNote
                transaction.tags = previousTags
                transaction.updatedAt = previousUpdatedAt
                transaction.needsSync = true
            }
            transaction.note = transform(tag, transaction.note)
            transaction.tags = TransactionTagParser.tags(in: transaction.note)
            markUpdated(transaction, at: timestamp)
        }
        try commit(modelContext)
        return TransactionBulkMutation(
            summary: summaryKey.localized(with: eligible.count),
            changedCount: eligible.count,
            skippedCount: transactions.count - eligible.count,
            reverts: reverts
        )
    }

    // MARK: - Reports inclusion

    /// True when every eligible transaction is already excluded from reports —
    /// the UI uses this to offer "Include" instead of "Exclude", mirroring how
    /// Mail flips Mark as Read/Unread for the current selection.
    static func allExcludedFromReports(_ transactions: [Transaction]) -> Bool {
        let eligible = transactions.filter { $0.deletedAt == nil }
        return !eligible.isEmpty && eligible.allSatisfy(\.excludeFromReports)
    }

    static func setExcludedFromReports(
        _ excluded: Bool,
        for transactions: [Transaction],
        in modelContext: ModelContext
    ) throws -> TransactionBulkMutation {
        guard !transactions.isEmpty else { throw BulkEditError.emptySelection }
        let eligible = transactions.filter { $0.deletedAt == nil }
        guard !eligible.isEmpty else { throw BulkEditError.noEligibleTransactions }

        let timestamp = Date()
        var reverts: [() -> Void] = []
        for transaction in eligible {
            let previousValue = transaction.excludeFromReports
            let previousUpdatedAt = transaction.updatedAt
            reverts.append {
                transaction.excludeFromReports = previousValue
                transaction.updatedAt = previousUpdatedAt
                transaction.needsSync = true
            }
            transaction.excludeFromReports = excluded
            markUpdated(transaction, at: timestamp)
        }
        try commit(modelContext)
        let summaryKey = excluded
            ? "transaction.bulk.undo.excluded"
            : "transaction.bulk.undo.included"
        return TransactionBulkMutation(
            summary: summaryKey.localized(with: eligible.count),
            changedCount: eligible.count,
            skippedCount: transactions.count - eligible.count,
            reverts: reverts
        )
    }

    // MARK: - Wallet

    /// Transactions whose owning wallet can be reassigned in bulk.
    ///
    /// Transfers and adjustments are excluded because their amounts are defined
    /// *relative to a specific wallet pair* — reassigning one side silently
    /// corrupts both balances. Savings-linked rows are excluded because the goal
    /// tracks its own `linkedWallet` and would drift out of sync.
    static func isWalletMoveEligible(_ transaction: Transaction) -> Bool {
        transaction.deletedAt == nil
            && (transaction.type == .income || transaction.type == .expense)
            && transaction.savingsGoal == nil
    }

    /// Reassigns `sourceWallet` on the eligible part of the selection.
    ///
    /// Cross-currency moves keep `amount`/`currencyCode` untouched and re-derive
    /// `storedRate` at today's rate — the same trade-off
    /// `SoftDeleteService.moveOutgoingTransactions` already makes when a wallet
    /// is deleted and its history is rehomed.
    static func move(
        _ transactions: [Transaction],
        toWallet wallet: Wallet,
        in modelContext: ModelContext
    ) throws -> TransactionBulkMutation {
        guard !transactions.isEmpty else { throw BulkEditError.emptySelection }
        let eligible = transactions.filter(isWalletMoveEligible)
        guard !eligible.isEmpty else { throw BulkEditError.noEligibleTransactions }

        let timestamp = Date()
        var reverts: [() -> Void] = []
        var touchedWallets = Set<PersistentIdentifier>()

        for transaction in eligible {
            let previousWallet = transaction.sourceWallet
            let previousExchangeRate = transaction.exchangeRate
            let previousStoredRate = transaction.storedRate
            let previousUpdatedAt = transaction.updatedAt
            reverts.append {
                transaction.sourceWallet = previousWallet
                transaction.exchangeRate = previousExchangeRate
                transaction.storedRate = previousStoredRate
                transaction.updatedAt = previousUpdatedAt
                transaction.needsSync = true
                previousWallet?.invalidateBalanceCache()
                wallet.invalidateBalanceCache()
            }

            if let previousWallet, !touchedWallets.contains(previousWallet.persistentModelID) {
                touchedWallets.insert(previousWallet.persistentModelID)
                previousWallet.invalidateBalanceCache()
            }

            transaction.sourceWallet = wallet
            let rate = SoftDeleteService.conversionRate(
                from: transaction.currencyCode,
                to: wallet.currencyCode
            )
            transaction.storedRate = rate
            transaction.exchangeRate = rate
            markUpdated(transaction, at: timestamp)
        }
        wallet.invalidateBalanceCache()

        try commit(modelContext)
        return TransactionBulkMutation(
            summary: "transaction.bulk.undo.wallet".localized(with: eligible.count),
            changedCount: eligible.count,
            skippedCount: transactions.count - eligible.count,
            reverts: reverts
        )
    }

    // MARK: - Location

    /// Sets (or, with `nil`, clears) the location on the selection.
    ///
    /// Existing `TransactionLocation` rows are mutated in place rather than
    /// replaced: the relationship is `.cascade`, so swapping in a fresh object
    /// would leave the old row orphaned in the store and unreferenced by sync.
    static func setLocation(
        _ selection: TransactionLocationSelection?,
        for transactions: [Transaction],
        in modelContext: ModelContext
    ) throws -> TransactionBulkMutation {
        guard !transactions.isEmpty else { throw BulkEditError.emptySelection }
        let eligible = transactions.filter { $0.deletedAt == nil }
        guard !eligible.isEmpty else { throw BulkEditError.noEligibleTransactions }

        let timestamp = Date()
        var reverts: [() -> Void] = []

        for transaction in eligible {
            let previousUpdatedAt = transaction.updatedAt
            let existing = transaction.location

            if let selection {
                if let existing {
                    let previousValues = TransactionLocationSelection(location: existing)
                    let previousDeletedAt = existing.deletedAt
                    reverts.append {
                        previousValues.apply(to: existing)
                        existing.deletedAt = previousDeletedAt
                        existing.updatedAt = previousUpdatedAt
                        existing.needsSync = true
                        transaction.location = existing
                        transaction.updatedAt = previousUpdatedAt
                        transaction.needsSync = true
                    }
                    selection.apply(to: existing)
                    existing.deletedAt = nil
                    existing.updatedAt = timestamp
                    existing.needsSync = true
                } else {
                    let created = selection.makePersistentLocation()
                    modelContext.insert(created)
                    reverts.append {
                        created.markSoftDeleted()
                        transaction.location = nil
                        transaction.updatedAt = previousUpdatedAt
                        transaction.needsSync = true
                    }
                    transaction.location = created
                }
            } else {
                guard let existing else { continue }
                let previousDeletedAt = existing.deletedAt
                reverts.append {
                    existing.deletedAt = previousDeletedAt
                    existing.updatedAt = previousUpdatedAt
                    existing.needsSync = true
                    transaction.location = existing
                    transaction.updatedAt = previousUpdatedAt
                    transaction.needsSync = true
                }
                existing.markSoftDeleted()
                transaction.location = nil
            }
            markUpdated(transaction, at: timestamp)
        }

        guard !reverts.isEmpty else { throw BulkEditError.noEligibleTransactions }
        try commit(modelContext)
        let summaryKey = selection == nil
            ? "transaction.bulk.undo.locationCleared"
            : "transaction.bulk.undo.location"
        return TransactionBulkMutation(
            summary: summaryKey.localized(with: reverts.count),
            changedCount: reverts.count,
            skippedCount: transactions.count - reverts.count,
            reverts: reverts
        )
    }

    // MARK: - Delete

    /// Soft-deletes the selection.
    ///
    /// Debt anchors are skipped rather than failing the whole batch — deleting
    /// one would orphan its debt, and the single-row delete paths already
    /// redirect the user to Debts & Loans for that case.
    static func delete(
        _ transactions: [Transaction],
        in modelContext: ModelContext
    ) throws -> TransactionBulkMutation {
        guard !transactions.isEmpty else { throw BulkEditError.emptySelection }
        let eligible = transactions.filter { $0.deletedAt == nil && !$0.isDebtAnchor }
        guard !eligible.isEmpty else { throw BulkEditError.noEligibleTransactions }

        var reverts: [() -> Void] = []
        for transaction in eligible {
            reverts.append {
                SoftDeleteService.restoreTransaction(transaction)
            }
            SoftDeleteService.deleteTransaction(transaction)
        }
        try commit(modelContext)
        return TransactionBulkMutation(
            summary: "transaction.bulk.undo.deleted".localized(with: eligible.count),
            changedCount: eligible.count,
            skippedCount: transactions.count - eligible.count,
            reverts: reverts
        )
    }

    // MARK: - Helpers

    private static func markUpdated(_ transaction: Transaction, at timestamp: Date) {
        transaction.updatedAt = timestamp
        transaction.needsSync = true
    }

    private static func commit(_ modelContext: ModelContext) throws {
        try modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
}
