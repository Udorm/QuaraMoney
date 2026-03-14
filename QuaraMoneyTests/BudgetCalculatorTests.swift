import XCTest
import SwiftData
@testable import QuaraMoney

// Alias to avoid ambiguity with system Category
private typealias AppCategory = QuaraMoney.Category

@MainActor
final class BudgetCalculatorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        container = TestModelContainer.create()
        context = container.mainContext
    }

    // MARK: - Helpers

    private func makeCategory(name: String) -> AppCategory {
        let cat = AppCategory(name: name, icon: "bag", colorHex: "#FF0000", type: .expense)
        context.insert(cat)
        return cat
    }

    private func makeTransaction(amount: Decimal, type: TransactionType, currency: String = "USD", category: AppCategory? = nil, date: Date = Date()) -> Transaction {
        let txn = Transaction(amount: amount, currencyCode: currency, date: date, type: type)
        txn.category = category
        context.insert(txn)
        return txn
    }

    private func makeBudget(limit: Decimal, currency: String = "USD", category: AppCategory? = nil, startDate: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!) -> Budget {
        let budget = Budget(amountLimit: limit, currencyCode: currency, periodType: .monthly, startDate: startDate, category: category)
        context.insert(budget)
        return budget
    }

    private func allTransactions() -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>()
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Tests

    func testCalculateSpendingFiltersExpensesOnly() {
        let cat = makeCategory(name: "Food")
        let budget = makeBudget(limit: 500, category: cat)

        let marchDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        _ = makeTransaction(amount: 20, type: .expense, category: cat, date: marchDate)
        _ = makeTransaction(amount: 100, type: .income, category: cat, date: marchDate) // should be ignored

        let spent = BudgetCalculator.calculateSpending(for: budget, transactions: allTransactions(), targetCurrency: "USD")
        XCTAssertEqual(spent, 20, "Only expenses should be counted")
    }

    func testCalculateSpendingFiltersByCategory() {
        let food = makeCategory(name: "Food")
        let transport = makeCategory(name: "Transport")
        let budget = makeBudget(limit: 500, category: food)

        let marchDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        _ = makeTransaction(amount: 30, type: .expense, category: food, date: marchDate)
        _ = makeTransaction(amount: 50, type: .expense, category: transport, date: marchDate) // wrong category

        let spent = BudgetCalculator.calculateSpending(for: budget, transactions: allTransactions(), targetCurrency: "USD")
        XCTAssertEqual(spent, 30, "Only expenses matching the budget category should be counted")
    }

    func testCalculateIncomeWithinPeriod() {
        let budget = makeBudget(limit: 500)

        let marchDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let febDate = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 15))!
        _ = makeTransaction(amount: 1000, type: .income, date: marchDate)
        _ = makeTransaction(amount: 500, type: .income, date: febDate) // outside period

        let income = BudgetCalculator.calculateIncome(for: budget, transactions: allTransactions())
        XCTAssertEqual(income, 1000, "Only income within the budget period should be counted")
    }

    func testConvertBudgetLimitFixedAmount() {
        let budget = makeBudget(limit: 200)

        let limit = BudgetCalculator.convertBudgetLimit(for: budget, transactions: [], targetCurrency: "USD")
        XCTAssertEqual(limit, 200)
    }

    func testTotalBudgetIncludesAllExpenses() {
        let budget = makeBudget(limit: 1000)

        let marchDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let food = makeCategory(name: "Food")
        let transport = makeCategory(name: "Transport")
        _ = makeTransaction(amount: 30, type: .expense, category: food, date: marchDate)
        _ = makeTransaction(amount: 50, type: .expense, category: transport, date: marchDate)

        let spent = BudgetCalculator.calculateSpending(for: budget, transactions: allTransactions(), targetCurrency: "USD")
        XCTAssertEqual(spent, 80, "Total budget should include all expense categories")
    }
}
