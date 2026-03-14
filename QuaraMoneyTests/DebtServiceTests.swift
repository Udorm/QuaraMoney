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
}
