import SwiftData
import Foundation

enum EventSplitType: String, Codable, CaseIterable, Identifiable {
    case equal
    
    var id: String { rawValue }
}

enum EventLedgerTransactionKind: String, Codable, CaseIterable, Identifiable {
    case expense
    case contribution
    
    var id: String { rawValue }
}

enum EventExpensePaidSource: String, Codable, CaseIterable, Identifiable {
    case member
    case eventWallet
    
    var id: String { rawValue }
}

@Model
final class EventLedgerTransaction {
    var id: UUID
    var kind: EventLedgerTransactionKind
    var title: String
    var amountMinor: Int64
    var paidSource: EventExpensePaidSource
    var paidByMemberId: UUID?
    var splitType: EventSplitType
    var date: Date
    var note: String?
    var categoryId: UUID?
    var categoryName: String?
    var categoryIcon: String?
    var categoryColorHex: String?
    var isSplitAll: Bool = false
    var isDeleted: Bool = false
    var createdAt: Date
    var updatedAt: Date
    
    // Relationships
    var event: Event?
    @Relationship(deleteRule: .cascade, inverse: \EventLedgerParticipant.transaction) var participants: [EventLedgerParticipant]?
    
    init(
        kind: EventLedgerTransactionKind = .expense,
        title: String,
        amountMinor: Int64,
        paidSource: EventExpensePaidSource = .member,
        paidByMemberId: UUID?,
        splitType: EventSplitType,
        date: Date,
        note: String? = nil,
        categoryId: UUID? = nil,
        categoryName: String? = nil,
        categoryIcon: String? = nil,
        categoryColorHex: String? = nil,
        event: Event?
    ) {
        self.id = UUID()
        self.kind = kind
        self.title = title
        self.amountMinor = amountMinor
        self.paidSource = paidSource
        self.paidByMemberId = paidByMemberId
        self.splitType = splitType
        self.date = date
        self.note = note
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.categoryIcon = categoryIcon
        self.categoryColorHex = categoryColorHex
        self.event = event
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
