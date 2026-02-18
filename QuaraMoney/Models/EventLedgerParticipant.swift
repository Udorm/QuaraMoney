import SwiftData
import Foundation

@Model
final class EventLedgerParticipant {
    @Attribute(.unique) var id: UUID
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
