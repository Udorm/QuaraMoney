import SwiftData
import Foundation

@Model
final class Event {
    @Attribute(.unique) var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date?
    var totalBudget: Decimal?
    var coverImageData: Data?
    var notes: String?
    
    // Relationships
    @Relationship(deleteRule: .nullify) var transactions: [Transaction]?
    
    init(title: String, startDate: Date) {
        self.id = UUID()
        self.title = title
        self.startDate = startDate
    }
}
