import SwiftData
import Foundation

@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var type: TransactionType // .income or .expense only
    
    // Relationships
    @Relationship(deleteRule: .deny) var transactions: [Transaction]?
    @Relationship(deleteRule: .cascade) var budgets: [Budget]?
    @Relationship(deleteRule: .nullify) var recurringRules: [RecurringRule]?
    
    init(name: String, icon: String, colorHex: String, type: TransactionType) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.type = type
    }
}
