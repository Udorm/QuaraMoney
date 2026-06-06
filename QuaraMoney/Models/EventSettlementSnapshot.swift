import SwiftData
import Foundation

@Model
final class EventSettlementSnapshot {
    var id: UUID
    var ledgerRevision: Int64
    var createdAt: Date
    
    // Relationships
    var event: Event?
    @Relationship(deleteRule: .cascade, inverse: \EventSettlementTransfer.snapshot) var transfers: [EventSettlementTransfer]?
    
    init(ledgerRevision: Int64, event: Event?) {
        self.id = UUID()
        self.ledgerRevision = ledgerRevision
        self.event = event
        self.createdAt = Date()
    }
}

@Model
final class EventSettlementTransfer {
    var id: UUID
    var fromMemberId: UUID
    var toMemberId: UUID
    var amountMinor: Int64
    var sequence: Int
    
    // Relationships
    var snapshot: EventSettlementSnapshot?
    
    init(fromMemberId: UUID, toMemberId: UUID, amountMinor: Int64, sequence: Int, snapshot: EventSettlementSnapshot?) {
        self.id = UUID()
        self.fromMemberId = fromMemberId
        self.toMemberId = toMemberId
        self.amountMinor = amountMinor
        self.sequence = sequence
        self.snapshot = snapshot
    }
}
