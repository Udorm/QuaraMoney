import SwiftData
import Foundation

@Model
final class Wallet {
    @Attribute(.unique) var id: UUID
    var name: String
    var currencyCode: String // e.g., "USD", "KHR"
    var icon: String // SF Symbol name
    var colorHex: String
    var isArchived: Bool = false
    
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
}
