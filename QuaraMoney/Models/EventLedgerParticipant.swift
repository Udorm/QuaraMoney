import SwiftData
import Foundation

@Model
final class EventLedgerParticipant {
    var id: UUID

    // MARK: - Sync metadata (Supabase migration)
    var syncUserID: UUID?
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var needsSync: Bool = true

    var memberId: UUID
    var orderIndex: Int
    
    // Relationships
    var transaction: EventLedgerTransaction?
    var member: EventMember?
    
    init(memberId: UUID, orderIndex: Int, transaction: EventLedgerTransaction?, member: EventMember?) {
        self.id = UUID()
        self.memberId = memberId
        self.orderIndex = orderIndex
        self.transaction = transaction
        self.member = member
    }
}
