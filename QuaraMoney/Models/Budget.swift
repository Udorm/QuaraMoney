import SwiftData
import Foundation

@Model
final class Budget {
    @Attribute(.unique) var id: UUID
    var amountLimit: Decimal
    var month: Int // 1-12
    var year: Int // 2026
    
    // Relationships
    @Relationship(deleteRule: .nullify) var category: Category?
    
    init(amountLimit: Decimal, category: Category?, month: Int, year: Int) {
        self.id = UUID()
        self.amountLimit = amountLimit
        self.category = category
        self.month = month
        self.year = year
    }
}
