import SwiftData
import Foundation

@Model
final class Wallet {
    var id: UUID

    // MARK: - Sync metadata (Supabase migration)
    var syncUserID: UUID?
    var deletedAt: Date?
    var needsSync: Bool = true

    var name: String
    var currencyCode: String // e.g., "USD", "KHR"
    var icon: String // SF Symbol name
    var colorHex: String
    var isArchived: Bool = false

    // Timestamps (for future sync readiness)
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    // MARK: - Performance: Cached Balance
    /// Cached balance value for performance - avoids O(n) computation on every access
    /// Note: Using internal instead of private so extension can access. Prefix indicates internal use.
    @Transient var _cachedBalance: Decimal?
    @Transient var _balanceCacheStale: Bool = true
    
    // Relationships
    // Explicitly separate outgoing (source) and incoming (destination) for accurate balance
    @Relationship(deleteRule: .cascade, inverse: \Transaction.sourceWallet) 
    var outgoingTransactions: [Transaction]?
    
    @Relationship(deleteRule: .nullify, inverse: \Transaction.destinationWallet) 
    var incomingTransactions: [Transaction]?
    
    @Relationship(deleteRule: .nullify) var recurringRules: [RecurringRule]?
    
    init(name: String, currencyCode: String, icon: String, colorHex: String) {
        self.id = UUID()
        self.name = name
        self.currencyCode = currencyCode
        self.icon = icon
        self.colorHex = colorHex
    }

    // MARK: - Validation

    func validate() -> [ModelValidationError] {
        var errors: [ModelValidationError] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyName(field: "Wallet name"))
        }
        if currencyCode.count != 3 { errors.append(.invalidCurrencyCode) }
        return errors
    }
}
