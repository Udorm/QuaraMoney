import XCTest
@testable import QuaraMoney

final class EventSettlementEngineTests: XCTestCase {
    func testGreedySettlementProducesNoCircularTransfers() {
        let memberA = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let memberB = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        let memberC = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!
        
        let transaction = EventLedgerTransaction(
            kind: .expense,
            title: "Dinner",
            amountMinor: 600,
            paidSource: .member,
            paidByMemberId: memberA,
            splitType: .equal,
            date: Date(),
            note: nil,
            event: nil
        )
        
        let links = [
            EventLedgerParticipant(memberId: memberA, orderIndex: 0, transaction: transaction, member: nil),
            EventLedgerParticipant(memberId: memberB, orderIndex: 1, transaction: transaction, member: nil),
            EventLedgerParticipant(memberId: memberC, orderIndex: 2, transaction: transaction, member: nil)
        ]
        
        let result = EventSettlementEngine.compute(
            memberIds: [memberA, memberB, memberC],
            transactions: [transaction],
            participantLinks: [transaction.id: links.map(\.memberId)]
        )
        
        XCTAssertTrue(result.walletInstructions.isEmpty)
        XCTAssertEqual(result.instructions.count, 2)
        XCTAssertTrue(result.instructions.allSatisfy { $0.toMemberId == memberA })
        XCTAssertTrue(result.instructions.allSatisfy { $0.fromMemberId != $0.toMemberId })
        XCTAssertEqual(result.instructions.reduce(0) { $0 + $1.amountMinor }, 400)
    }
    
    func testEqualSplitRoundingIsDeterministic() {
        let memberA = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let memberB = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        let memberC = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!
        
        let transaction = EventLedgerTransaction(
            kind: .expense,
            title: "Taxi",
            amountMinor: 100,
            paidSource: .member,
            paidByMemberId: memberA,
            splitType: .equal,
            date: Date(),
            note: nil,
            event: nil
        )
        
        let links = [
            EventLedgerParticipant(memberId: memberA, orderIndex: 0, transaction: transaction, member: nil),
            EventLedgerParticipant(memberId: memberB, orderIndex: 1, transaction: transaction, member: nil),
            EventLedgerParticipant(memberId: memberC, orderIndex: 2, transaction: transaction, member: nil)
        ]
        
        let result = EventSettlementEngine.compute(
            memberIds: [memberA, memberB, memberC],
            transactions: [transaction],
            participantLinks: [transaction.id: links.map(\.memberId)]
        )
        
        let balances = Dictionary(uniqueKeysWithValues: result.balances.map { ($0.memberId, $0.netMinor) })
        XCTAssertEqual(balances[memberA], 66)
        XCTAssertEqual(balances[memberB], -33)
        XCTAssertEqual(balances[memberC], -33)
        XCTAssertEqual(result.instructions.count, 2)
        XCTAssertEqual(result.instructions.map(\.amountMinor).sorted(), [33, 33])
    }
    
    func testContributionAndWalletExpenseUsePoolFirst() {
        let memberA = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let memberB = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        
        let contribution = EventLedgerTransaction(
            kind: .contribution,
            title: "Deposit",
            amountMinor: 100,
            paidSource: .member,
            paidByMemberId: memberA,
            splitType: .equal,
            date: Date(),
            note: nil,
            event: nil
        )
        
        let expense = EventLedgerTransaction(
            kind: .expense,
            title: "Tickets",
            amountMinor: 60,
            paidSource: .eventWallet,
            paidByMemberId: nil,
            splitType: .equal,
            date: Date(),
            note: nil,
            event: nil
        )
        
        let result = EventSettlementEngine.compute(
            memberIds: [memberA, memberB],
            transactions: [contribution, expense],
            participantLinks: [
                expense.id: [memberB]
            ]
        )
        
        XCTAssertEqual(result.totalContributionMinor, 100)
        XCTAssertEqual(result.totalCostMinor, 60)
        XCTAssertEqual(result.walletExpensesMinor, 60)
        XCTAssertEqual(result.walletRemainingMinor, 40)
        
        XCTAssertEqual(result.walletInstructions.count, 1)
        XCTAssertEqual(result.walletInstructions.first?.memberId, memberA)
        XCTAssertEqual(result.walletInstructions.first?.amountMinor, 40)
        XCTAssertEqual(result.walletInstructions.first?.direction, .receiveFromWallet)
        
        XCTAssertEqual(result.instructions.count, 1)
        XCTAssertEqual(result.instructions.first?.fromMemberId, memberB)
        XCTAssertEqual(result.instructions.first?.toMemberId, memberA)
        XCTAssertEqual(result.instructions.first?.amountMinor, 60)
    }
    
    func testNetBalancesMatchWalletRemainingAndTransferNetsZero() {
        let memberA = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let memberB = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        let memberC = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!
        
        let contributionA = EventLedgerTransaction(
            kind: .contribution,
            title: "A deposit",
            amountMinor: 500,
            paidSource: .member,
            paidByMemberId: memberA,
            splitType: .equal,
            date: Date(),
            note: nil,
            event: nil
        )
        
        let expenseWallet = EventLedgerTransaction(
            kind: .expense,
            title: "Hotel",
            amountMinor: 300,
            paidSource: .eventWallet,
            paidByMemberId: nil,
            splitType: .equal,
            date: Date(),
            note: nil,
            event: nil
        )
        
        let expensePersonal = EventLedgerTransaction(
            kind: .expense,
            title: "Fuel",
            amountMinor: 210,
            paidSource: .member,
            paidByMemberId: memberB,
            splitType: .equal,
            date: Date(),
            note: nil,
            event: nil
        )
        
        let participantsAll = [
            EventLedgerParticipant(memberId: memberA, orderIndex: 0, transaction: expenseWallet, member: nil),
            EventLedgerParticipant(memberId: memberB, orderIndex: 1, transaction: expenseWallet, member: nil),
            EventLedgerParticipant(memberId: memberC, orderIndex: 2, transaction: expenseWallet, member: nil)
        ]
        
        let participantsAB = [
            EventLedgerParticipant(memberId: memberA, orderIndex: 0, transaction: expensePersonal, member: nil),
            EventLedgerParticipant(memberId: memberB, orderIndex: 1, transaction: expensePersonal, member: nil)
        ]
        
        let result = EventSettlementEngine.compute(
            memberIds: [memberA, memberB, memberC],
            transactions: [contributionA, expenseWallet, expensePersonal],
            participantLinks: [
                expenseWallet.id: participantsAll.map(\.memberId),
                expensePersonal.id: participantsAB.map(\.memberId)
            ]
        )
        
        XCTAssertEqual(result.balances.reduce(0) { $0 + $1.netMinor }, result.walletRemainingMinor)
        XCTAssertEqual(result.balances.reduce(0) { $0 + $1.transferNetMinor }, 0)
    }
    
    func testSingleCoordinatorModeCreatesOneCounterpartyPerMember() {
        let memberA = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let memberB = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")! // coordinator
        let memberC = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!
        
        let transaction = EventLedgerTransaction(
            kind: .expense,
            title: "Dinner",
            amountMinor: 600,
            paidSource: .member,
            paidByMemberId: memberA,
            splitType: .equal,
            date: Date(),
            note: nil,
            event: nil
        )
        let links = [
            EventLedgerParticipant(memberId: memberA, orderIndex: 0, transaction: transaction, member: nil),
            EventLedgerParticipant(memberId: memberB, orderIndex: 1, transaction: transaction, member: nil),
            EventLedgerParticipant(memberId: memberC, orderIndex: 2, transaction: transaction, member: nil)
        ]
        
        let result = EventSettlementEngine.compute(
            memberIds: [memberA, memberB, memberC],
            transactions: [transaction],
            participantLinks: [transaction.id: links.map(\.memberId)],
            options: EventSettlementOptions(strategy: .singleCoordinator(coordinatorMemberId: memberB))
        )
        
        XCTAssertEqual(result.instructions.count, 2)
        XCTAssertTrue(result.instructions.allSatisfy { $0.fromMemberId == memberB || $0.toMemberId == memberB })
        XCTAssertTrue(result.instructions.allSatisfy { $0.fromMemberId != $0.toMemberId })
    }
}
