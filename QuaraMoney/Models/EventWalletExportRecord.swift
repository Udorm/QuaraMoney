import SwiftData
import Foundation

enum EventWalletExportDirection: String, Codable, CaseIterable, Identifiable {
    case income
    case expense
    
    var id: String { rawValue }
}

@Model
final class EventWalletExportRecord {
    @Attribute(.unique) var id: UUID
    var memberId: UUID
    var walletTransactionId: UUID
    var amountMinor: Int64
    var direction: EventWalletExportDirection
    var createdAt: Date
    
    // Relationships
    var event: Event?
    var snapshot: EventSettlementSnapshot?
    
    init(
        memberId: UUID,
        walletTransactionId: UUID,
        amountMinor: Int64,
        direction: EventWalletExportDirection,
        event: Event?,
        snapshot: EventSettlementSnapshot?
    ) {
        self.id = UUID()
        self.memberId = memberId
        self.walletTransactionId = walletTransactionId
        self.amountMinor = amountMinor
        self.direction = direction
        self.event = event
        self.snapshot = snapshot
        self.createdAt = Date()
    }
}
