import SwiftData
import Foundation

enum EventWalletExportDirection: String, Codable, CaseIterable, Identifiable {
    case income
    case expense
    
    var id: String { rawValue }
}

enum EventWalletExportType: String, Codable, CaseIterable, Identifiable {
    case spending
    case settlement
    
    var id: String { rawValue }
}

@Model
final class EventWalletExportRecord {
    var id: UUID

    // MARK: - Sync metadata (Supabase migration)
    var syncUserID: UUID?
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var needsSync: Bool = true

    var memberId: UUID
    var walletTransactionId: UUID
    var amountMinor: Int64
    var direction: EventWalletExportDirection
    var exportType: EventWalletExportType
    var createdAt: Date
    
    // Relationships
    var event: Event?
    var snapshot: EventSettlementSnapshot?
    
    init(
        memberId: UUID,
        walletTransactionId: UUID,
        amountMinor: Int64,
        direction: EventWalletExportDirection,
        exportType: EventWalletExportType = .settlement,
        event: Event?,
        snapshot: EventSettlementSnapshot?
    ) {
        self.id = UUID()
        self.memberId = memberId
        self.walletTransactionId = walletTransactionId
        self.amountMinor = amountMinor
        self.direction = direction
        self.exportType = exportType
        self.event = event
        self.snapshot = snapshot
        self.createdAt = Date()
    }
}
