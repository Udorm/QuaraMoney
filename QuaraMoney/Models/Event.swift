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
    
    // New properties for enhanced features
    var icon: String = "party.popper"
    var colorHex: String = "007AFF" // System Blue
    var location: String?
    var status: String = "planned" // planned, ongoing, completed
    
    // Relationships
    @Relationship(deleteRule: .nullify) var transactions: [Transaction]?
    
    init(title: String, startDate: Date, endDate: Date? = nil, icon: String = "party.popper", colorHex: String = "007AFF", location: String? = nil, totalBudget: Decimal? = nil) {
        self.id = UUID()
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.icon = icon
        self.colorHex = colorHex
        self.location = location
        self.totalBudget = totalBudget
    }
}
