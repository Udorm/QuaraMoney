import SwiftData
import Foundation

enum EventLedgerMode: String, Codable, CaseIterable, Identifiable {
    case legacyLinked
    case isolatedV1
    
    var id: String { rawValue }
}

enum EventSettlementStatus: String, CaseIterable, Identifiable {
    case active
    case readyToSettle
    case settled
    
    var id: String { rawValue }
}

@Model
final class Event {
    var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date?
    var totalBudget: Decimal?
    @Attribute(.externalStorage) var coverImageData: Data?
    var notes: String?
    
    // New properties for enhanced features
    var icon: String = "party.popper"
    var colorHex: String = "007AFF" // System Blue
    var location: String?
    var status: String = "planned" // planned, ongoing, completed
    
    // Isolated event-ledger fields
    var currencyCode: String = "USD"
    var ledgerRevision: Int64 = 0
    var confirmedSettlementRevision: Int64?
    var ledgerMode: EventLedgerMode
    
    // Map Location
    var latitude: Double?
    var longitude: Double?
    
    // Relationships
    @Relationship(deleteRule: .nullify) var transactions: [Transaction]?
    @Relationship(deleteRule: .cascade, inverse: \EventMember.event) var members: [EventMember]?
    @Relationship(deleteRule: .cascade, inverse: \EventLedgerTransaction.event) var ledgerTransactions: [EventLedgerTransaction]?
    @Relationship(deleteRule: .cascade, inverse: \EventSettlementSnapshot.event) var settlementSnapshots: [EventSettlementSnapshot]?
    @Relationship(deleteRule: .cascade, inverse: \EventWalletExportRecord.event) var walletExportRecords: [EventWalletExportRecord]?
    
    init(
        title: String,
        startDate: Date,
        endDate: Date? = nil,
        icon: String = "party.popper",
        colorHex: String = "007AFF",
        location: String? = nil,
        totalBudget: Decimal? = nil,
        currencyCode: String = "USD",
        ledgerMode: EventLedgerMode = EventLedgerMode.isolatedV1,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.icon = icon
        self.colorHex = colorHex
        self.location = location
        self.totalBudget = totalBudget
        self.currencyCode = currencyCode
        self.ledgerMode = ledgerMode
        self.latitude = latitude
        self.longitude = longitude
    }
    
    var settlementStatus: EventSettlementStatus {
        let hasLedgerTransactions = (ledgerTransactions?.contains(where: { !$0.isDeleted && $0.kind == .expense }) ?? false)
        
        guard hasLedgerTransactions else {
            return .active
        }
        
        if confirmedSettlementRevision == ledgerRevision {
            return .settled
        }
        
        return .readyToSettle
    }
}
