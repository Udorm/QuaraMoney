import XCTest
import SwiftData
@testable import QuaraMoney

@MainActor
final class TransactionProcessorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private let rates: [String: Double] = [
        "USD": 1.0,
        "KHR": 4000.0,
        "EUR": 0.92
    ]

    override func setUp() {
        super.setUp()
        container = TestModelContainer.create()
        context = container.mainContext
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeWallet(name: String = "Test Wallet", currency: String = "USD") -> Wallet {
        let wallet = Wallet(name: name, currencyCode: currency, icon: "wallet.pass", colorHex: "#007AFF")
        context.insert(wallet)
        return wallet
    }

    private func makeTransaction(
        amount: Decimal,
        currency: String = "USD",
        type: TransactionType = .expense,
        date: Date = Date(),
        wallet: Wallet? = nil,
        excludeFromReports: Bool = false
    ) -> Transaction {
        let txn = Transaction(amount: amount, currencyCode: currency, date: date, type: type)
        txn.sourceWallet = wallet
        txn.excludeFromReports = excludeFromReports
        context.insert(txn)
        return txn
    }

    // MARK: - calculateTotals

    func testCalculateTotalsIncomesAndExpenses() {
        let wallet = makeWallet()
        let income = makeTransaction(amount: 1000, type: .income, wallet: wallet)
        let expense = makeTransaction(amount: 300, type: .expense, wallet: wallet)

        let totals = TransactionProcessor.calculateTotals(
            [income, expense],
            rates: rates,
            targetCurrency: "USD"
        )

        XCTAssertEqual(totals.income, Decimal(1000))
        XCTAssertEqual(totals.expense, Decimal(300))
    }

    func testCalculateTotalsExcludesReports() {
        let wallet = makeWallet()
        let included = makeTransaction(amount: 500, type: .expense, wallet: wallet)
        let excluded = makeTransaction(amount: 200, type: .expense, wallet: wallet, excludeFromReports: true)

        let totals = TransactionProcessor.calculateTotals(
            [included, excluded],
            rates: rates,
            targetCurrency: "USD"
        )

        XCTAssertEqual(totals.expense, Decimal(500))
    }

    func testCalculateTotalsTransfersAreNeutral() {
        let wallet = makeWallet()
        let transfer = makeTransaction(amount: 1000, type: .transfer, wallet: wallet)

        let totals = TransactionProcessor.calculateTotals(
            [transfer],
            rates: rates,
            targetCurrency: "USD"
        )

        XCTAssertEqual(totals.income, Decimal(0))
        XCTAssertEqual(totals.expense, Decimal(0))
    }

    func testCalculateTotalsMultiCurrency() {
        let wallet = makeWallet()
        let usdExpense = makeTransaction(amount: 100, currency: "USD", type: .expense, wallet: wallet)
        let khrExpense = makeTransaction(amount: 400000, currency: "KHR", type: .expense, wallet: wallet)

        let totals = TransactionProcessor.calculateTotals(
            [usdExpense, khrExpense],
            rates: rates,
            targetCurrency: "USD"
        )

        // 100 USD + 400000 KHR (= 100 USD at rate 4000) = 200 USD
        XCTAssertEqual(totals.expense, Decimal(200))
    }

    // MARK: - groupByDayObjects

    func testGroupByDaySeparatesDays() {
        let wallet = makeWallet()
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        let txn1 = makeTransaction(amount: 100, type: .expense, date: today, wallet: wallet)
        let txn2 = makeTransaction(amount: 200, type: .expense, date: yesterday, wallet: wallet)

        let sections = TransactionProcessor.groupByDayObjects(
            [txn1, txn2],
            rates: rates,
            targetCurrency: "USD"
        )

        XCTAssertEqual(sections.count, 2)
    }

    func testGroupByDaySameDayGrouped() {
        let wallet = makeWallet()
        let today = Date()

        let txn1 = makeTransaction(amount: 100, type: .expense, date: today, wallet: wallet)
        let txn2 = makeTransaction(amount: 200, type: .income, date: today, wallet: wallet)

        let sections = TransactionProcessor.groupByDayObjects(
            [txn1, txn2],
            rates: rates,
            targetCurrency: "USD"
        )

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.transactions.count, 2)
    }

    func testGroupByDayEmptyTransactions() {
        let sections = TransactionProcessor.groupByDayObjects(
            [],
            rates: rates,
            targetCurrency: "USD"
        )

        XCTAssertTrue(sections.isEmpty)
    }
}
