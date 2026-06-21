import XCTest
import SwiftData
@testable import QuaraMoney

@MainActor
final class DebtServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: DebtService!

    override func setUp() {
        super.setUp()
        container = TestModelContainer.create()
        context = container.mainContext
        service = DebtService(modelContext: context)
    }

    override func tearDown() {
        container = nil
        context = nil
        service = nil
        super.tearDown()
    }

    // MARK: - createDebt

    func testCreateDebtSuccess() throws {
        let debt = try service.createDebt(
            person: "Alice",
            amount: Decimal(100),
            currency: "USD",
            dueDate: nil,
            note: "Test",
            sourceWallet: nil
        )

        XCTAssertEqual(debt.personName, "Alice")
        XCTAssertEqual(debt.totalAmount, Decimal(100))
        XCTAssertEqual(debt.currencyCode, "USD")
        XCTAssertEqual(debt.type, .owedToMe)
        XCTAssertFalse(debt.isCompleted)
    }

    func testCreateDebtTrimsWhitespace() throws {
        let debt = try service.createDebt(
            person: "  Bob  ",
            amount: Decimal(50),
            currency: "USD",
            dueDate: nil,
            note: nil,
            sourceWallet: nil
        )

        XCTAssertEqual(debt.personName, "Bob")
    }

    func testCreateDebtEmptyNameThrows() {
        XCTAssertThrowsError(try service.createDebt(
            person: "",
            amount: Decimal(100),
            currency: "USD",
            dueDate: nil,
            note: nil,
            sourceWallet: nil
        )) { error in
            XCTAssertEqual(error as? DebtServiceError, .invalidPersonName)
        }
    }

    func testCreateDebtZeroAmountThrows() {
        XCTAssertThrowsError(try service.createDebt(
            person: "Alice",
            amount: Decimal(0),
            currency: "USD",
            dueDate: nil,
            note: nil,
            sourceWallet: nil
        )) { error in
            XCTAssertEqual(error as? DebtServiceError, .invalidAmount)
        }
    }

    func testCreateDebtNegativeAmountThrows() {
        XCTAssertThrowsError(try service.createDebt(
            person: "Alice",
            amount: Decimal(-10),
            currency: "USD",
            dueDate: nil,
            note: nil,
            sourceWallet: nil
        )) { error in
            XCTAssertEqual(error as? DebtServiceError, .invalidAmount)
        }
    }

    // MARK: - createLoan

    func testCreateLoanSuccess() throws {
        let debt = try service.createLoan(
            person: "Charlie",
            amount: Decimal(200),
            currency: "KHR",
            dueDate: Date().addingTimeInterval(86400 * 30),
            note: "Monthly loan",
            destinationWallet: nil
        )

        XCTAssertEqual(debt.personName, "Charlie")
        XCTAssertEqual(debt.totalAmount, Decimal(200))
        XCTAssertEqual(debt.type, .iOwe)
    }

    // MARK: - recordRepayment

    func testRecordRepaymentSuccess() throws {
        let debt = try service.createDebt(
            person: "Alice",
            amount: Decimal(100),
            currency: "USD",
            dueDate: nil,
            note: nil,
            sourceWallet: nil
        )

        try service.recordRepayment(for: debt, amount: Decimal(50), sourceWallet: nil)

        XCTAssertEqual(debt.remainingAmount, Decimal(50))
        XCTAssertFalse(debt.isCompleted)
    }

    func testRecordFullRepaymentCompletesDebt() throws {
        let debt = try service.createDebt(
            person: "Alice",
            amount: Decimal(100),
            currency: "USD",
            dueDate: nil,
            note: nil,
            sourceWallet: nil
        )

        try service.recordRepayment(for: debt, amount: Decimal(100), sourceWallet: nil)

        XCTAssertTrue(debt.isCompleted)
    }

    func testRecordRepaymentExceedingRemainingThrows() throws {
        let debt = try service.createDebt(
            person: "Alice",
            amount: Decimal(100),
            currency: "USD",
            dueDate: nil,
            note: nil,
            sourceWallet: nil
        )

        XCTAssertThrowsError(try service.recordRepayment(
            for: debt,
            amount: Decimal(150),
            sourceWallet: nil
        )) { error in
            XCTAssertEqual(error as? DebtServiceError, .repaymentExceedsRemaining)
        }
    }

    // MARK: - updateDebt

    func testUpdateDebtSuccess() throws {
        let debt = try service.createDebt(
            person: "Alice",
            amount: Decimal(100),
            currency: "USD",
            dueDate: nil,
            note: nil,
            sourceWallet: nil
        )

        let dueDate = Date().addingTimeInterval(86400 * 7)
        try service.updateDebt(debt, person: "Alice Smith", dueDate: dueDate, note: "Updated")

        XCTAssertEqual(debt.personName, "Alice Smith")
        XCTAssertNotNil(debt.dueDate)
        XCTAssertEqual(debt.note, "Updated")
    }

    func testUpdatePrincipalAmount() throws {
        let debt = try service.createDebt(
            person: "Alice",
            amount: Decimal(100),
            currency: "USD",
            dueDate: nil,
            note: nil,
            sourceWallet: nil
        )

        try service.updateDebt(debt, person: "Alice", dueDate: nil, note: nil, newPrincipalAmount: Decimal(150))

        XCTAssertEqual(debt.currentTotalAmount, Decimal(150))
        XCTAssertEqual(debt.remainingAmount, Decimal(150))
        XCTAssertEqual(debt.totalAmount, Decimal(150))
    }

    func testUpdatePrincipalBelowPaidThrows() throws {
        let debt = try service.createDebt(
            person: "Alice",
            amount: Decimal(100),
            currency: "USD",
            dueDate: nil,
            note: nil,
            sourceWallet: nil
        )
        try service.recordRepayment(for: debt, amount: Decimal(60), sourceWallet: nil)

        XCTAssertThrowsError(
            try service.updateDebt(debt, person: "Alice", dueDate: nil, note: nil, newPrincipalAmount: Decimal(50))
        ) { error in
            XCTAssertEqual(error as? DebtServiceError, .amountBelowPaid)
        }
    }

    // MARK: - Currency-aware ledger (approach A)

    /// A repayment recorded in a different currency than the debt must be
    /// converted into the debt's currency before it counts against the balance.
    func testCrossCurrencyRepaymentConvertsToDebtCurrency() throws {
        // $100 USD owed to me.
        let debt = try service.createDebt(
            person: "Alice",
            amount: Decimal(100),
            currency: "USD",
            dueDate: nil,
            note: nil,
            sourceWallet: nil
        )

        // Repayment of 4000 KHR ≈ $1 USD at the reference rate (KHR = 4000/USD).
        let repayment = Transaction(amount: Decimal(4000), currencyCode: "KHR", date: Date(), type: .income)
        repayment.debt = debt
        context.insert(repayment)

        XCTAssertEqual(debt.amountPaid, Decimal(1))
        XCTAssertEqual(debt.remainingAmount, Decimal(99))
    }

    /// `reconcile()` re-derives the cached total and completion flag from the
    /// live transactions after a linked transaction is edited directly.
    func testReconcileUpdatesTotalAndCompletion() throws {
        let debt = try service.createDebt(
            person: "Alice",
            amount: Decimal(100),
            currency: "USD",
            dueDate: nil,
            note: nil,
            sourceWallet: nil
        )
        try service.recordRepayment(for: debt, amount: Decimal(100), sourceWallet: nil)
        XCTAssertTrue(debt.isCompleted)

        // Simulate editing the principal advance up to $200 from the main editor.
        debt.principalTransaction?.amount = Decimal(200)
        debt.reconcile()

        XCTAssertEqual(debt.totalAmount, Decimal(200))
        XCTAssertEqual(debt.remainingAmount, Decimal(100))
        XCTAssertFalse(debt.isCompleted)
    }
}
