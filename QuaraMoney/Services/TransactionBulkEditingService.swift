import Foundation
import SwiftData

/// Applies one mutation to a transaction selection and commits it as a single
/// SwiftData save. Keeping the mutations here makes every transaction-list
/// surface share the same validation and sync bookkeeping.
@MainActor
enum TransactionBulkEditingService {
    enum BulkEditError: Error, Equatable {
        case emptySelection
        case incompatibleCategory
        case invalidTag

        @MainActor
        var localizedMessage: String {
            switch self {
            case .emptySelection:
                return "transaction.bulk.error.emptySelection".localized
            case .incompatibleCategory:
                return "transaction.bulk.error.incompatibleCategory".localized
            case .invalidTag:
                return "transaction.bulk.error.invalidTag".localized
            }
        }
    }

    static func changeCategory(
        of transactions: [Transaction],
        to category: Category,
        in modelContext: ModelContext
    ) throws {
        guard !transactions.isEmpty else { throw BulkEditError.emptySelection }
        guard (category.type == .income || category.type == .expense),
              transactions.allSatisfy({
                  $0.type == category.type && $0.debt == nil && $0.deletedAt == nil
              }) else {
            throw BulkEditError.incompatibleCategory
        }

        let timestamp = Date()
        for transaction in transactions {
            transaction.category = category
            markUpdated(transaction, at: timestamp)
        }
        try commit(modelContext)
    }

    static func addTag(
        _ rawTag: String,
        to transactions: [Transaction],
        in modelContext: ModelContext
    ) throws {
        guard !transactions.isEmpty else { throw BulkEditError.emptySelection }
        guard let tag = TransactionTagParser.normalizedTag(rawTag) else {
            throw BulkEditError.invalidTag
        }

        let timestamp = Date()
        for transaction in transactions where transaction.deletedAt == nil {
            transaction.note = TransactionTagParser.adding(tag: tag, to: transaction.note)
            transaction.tags = TransactionTagParser.tags(in: transaction.note)
            markUpdated(transaction, at: timestamp)
        }
        try commit(modelContext)
    }

    static func removeTag(
        _ rawTag: String,
        from transactions: [Transaction],
        in modelContext: ModelContext
    ) throws {
        guard !transactions.isEmpty else { throw BulkEditError.emptySelection }
        guard let tag = TransactionTagParser.normalizedTag(rawTag) else {
            throw BulkEditError.invalidTag
        }

        let timestamp = Date()
        for transaction in transactions where transaction.deletedAt == nil {
            transaction.note = TransactionTagParser.removing(tag: tag, from: transaction.note)
            transaction.tags = TransactionTagParser.tags(in: transaction.note)
            markUpdated(transaction, at: timestamp)
        }
        try commit(modelContext)
    }

    private static func markUpdated(_ transaction: Transaction, at timestamp: Date) {
        transaction.updatedAt = timestamp
        transaction.needsSync = true
    }

    private static func commit(_ modelContext: ModelContext) throws {
        try modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
}
