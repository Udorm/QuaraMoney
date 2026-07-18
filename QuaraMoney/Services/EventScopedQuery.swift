import Foundation
import SwiftData

/// Shared predicates for event-ledger screens. Keeping these in one place makes
/// the database scoping directly unit-testable and prevents a regression back
/// to fetching the global ledger then filtering it in each view body.
enum EventScopedQuery {
    static func members(eventID: UUID) -> Predicate<EventMember> {
        #Predicate { member in
            member.deletedAt == nil && member.event?.id == eventID
        }
    }

    static func transactions(eventID: UUID) -> Predicate<EventLedgerTransaction> {
        #Predicate { transaction in
            transaction.deletedAt == nil && transaction.event?.id == eventID
        }
    }
}
