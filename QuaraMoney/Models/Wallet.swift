import SwiftData
import Foundation

enum WalletKind: String, Codable, CaseIterable, Identifiable {
    case normal
    case savings

    var id: String { rawValue }
}

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

    /// Stored as a raw string because SwiftData predicates/indexes only support
    /// primitive columns reliably. `kind` is the typed public surface.
    var kindRaw: String = WalletKind.normal.rawValue
    var targetAmount: Decimal?
    var targetDate: Date?
    var priority: Int = 0
    var hasCelebrated: Bool = false
    var legacySavingsGoalID: UUID?
    var legacyMigrationCompletedAt: Date?

    var kind: WalletKind {
        get { WalletKind(rawValue: kindRaw) ?? .normal }
        set { kindRaw = newValue.rawValue }
    }

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
        if kind == .savings, (targetAmount ?? 0) <= 0 {
            errors.append(.negativeOrZeroAmount(field: "Savings target"))
        }
        return errors
    }
}
