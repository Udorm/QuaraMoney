import SwiftData
import Foundation

@Model
final class RecurringRule {
    var id: UUID

    // MARK: - Sync metadata (Supabase migration)
    var syncUserID: UUID?
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var needsSync: Bool = true

    var name: String // e.g., "Netflix Subscription"
    var amount: Decimal
    var currencyCode: String
    var frequency: Frequency
    var startDate: Date
    var nextDueDate: Date
    var isActive: Bool = true
    
    // Relationships
    var wallet: Wallet?
    var category: Category?
    @Relationship(deleteRule: .cascade) var generatedTransactions: [Transaction]?
    
    init(name: String, amount: Decimal, currencyCode: String, frequency: Frequency, startDate: Date) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.currencyCode = currencyCode
        self.frequency = frequency
        self.startDate = startDate
        self.nextDueDate = startDate
    }
}
