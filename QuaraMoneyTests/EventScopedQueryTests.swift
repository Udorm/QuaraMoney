import XCTest
import SwiftData
@testable import QuaraMoney

@MainActor
final class EventScopedQueryTests: XCTestCase {
    func testEventPredicatesExcludeOtherEventLedgerRows() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let eventA = Event(title: "A", startDate: Date())
        let eventB = Event(title: "B", startDate: Date())
        let memberA = EventMember(name: "A member", event: eventA)
        let memberB = EventMember(name: "B member", event: eventB)
        let transactionA = EventLedgerTransaction(
            title: "A expense",
            amountMinor: 100,
            paidByMemberId: memberA.id,
            splitType: .equal,
            date: Date(),
            event: eventA
        )
        let transactionB = EventLedgerTransaction(
            title: "B expense",
            amountMinor: 200,
            paidByMemberId: memberB.id,
            splitType: .equal,
            date: Date(),
            event: eventB
        )
        let linkA = EventLedgerParticipant(
            memberId: memberA.id,
            orderIndex: 0,
            transaction: transactionA,
            member: memberA
        )
        let linkB = EventLedgerParticipant(
            memberId: memberB.id,
            orderIndex: 0,
            transaction: transactionB,
            member: memberB
        )
        context.insert(eventA)
        context.insert(eventB)
        context.insert(memberA)
        context.insert(memberB)
        context.insert(transactionA)
        context.insert(transactionB)
        context.insert(linkA)
        context.insert(linkB)
        try context.save()

        let members = try context.fetch(FetchDescriptor<EventMember>(
            predicate: EventScopedQuery.members(eventID: eventA.id)
        ))
        let transactions = try context.fetch(FetchDescriptor<EventLedgerTransaction>(
            predicate: EventScopedQuery.transactions(eventID: eventA.id)
        ))
        let links = transactions
            .flatMap { $0.participants ?? [] }
            .filter { $0.deletedAt == nil }

        XCTAssertEqual(members.map(\.id), [memberA.id])
        XCTAssertEqual(transactions.map(\.id), [transactionA.id])
        XCTAssertEqual(links.map(\.id), [linkA.id])
        XCTAssertFalse(links.contains(where: { $0.id == linkB.id }))
    }
}
