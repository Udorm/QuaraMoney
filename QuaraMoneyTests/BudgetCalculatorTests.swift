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

    private func makeTransaction(
        amount: Decimal,
        type: TransactionType,
        currency: String = "USD",
        category: AppCategory? = nil,
        date: Date = Date(),
        excludeFromReports: Bool = false
    ) -> Transaction {
        let txn = Transaction(amount: amount, currencyCode: currency, date: date, type: type)
        txn.category = category
        txn.excludeFromReports = excludeFromReports
        context.insert(txn)
        return txn
    }

    private func makeBudget(limit: Decimal, currency: String = "USD", category: AppCategory? = nil, startDate: Date = Date()) -> Budget {
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

        let marchDate = Date()
        _ = makeTransaction(amount: 20, type: .expense, category: cat, date: marchDate)
        _ = makeTransaction(amount: 100, type: .income, category: cat, date: marchDate) // should be ignored

        let spent = BudgetCalculator.calculateSpending(for: budget, transactions: allTransactions(), targetCurrency: "USD")
        XCTAssertEqual(spent, 20, "Only expenses should be counted")
    }

    func testCalculateSpendingFiltersByCategory() {
        let food = makeCategory(name: "Food")
        let transport = makeCategory(name: "Transport")
        let budget = makeBudget(limit: 500, category: food)

        let marchDate = Date()
        _ = makeTransaction(amount: 30, type: .expense, category: food, date: marchDate)
        _ = makeTransaction(amount: 50, type: .expense, category: transport, date: marchDate) // wrong category

        let spent = BudgetCalculator.calculateSpending(for: budget, transactions: allTransactions(), targetCurrency: "USD")
        XCTAssertEqual(spent, 30, "Only expenses matching the budget category should be counted")
    }

    func testCalculateIncomeWithinPeriod() {
        let budget = makeBudget(limit: 500)

        let marchDate = Date()
        let febDate = Calendar.current.date(byAdding: .month, value: -2, to: marchDate)!
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

        let marchDate = Date()
        let food = makeCategory(name: "Food")
        let transport = makeCategory(name: "Transport")
        _ = makeTransaction(amount: 30, type: .expense, category: food, date: marchDate)
        _ = makeTransaction(amount: 50, type: .expense, category: transport, date: marchDate)

        let spent = BudgetCalculator.calculateSpending(for: budget, transactions: allTransactions(), targetCurrency: "USD")
        XCTAssertEqual(spent, 80, "Total budget should include all expense categories")
    }

    func testCalculateSpendingExcludesReports() {
        let cat = makeCategory(name: "Food")
        let budget = makeBudget(limit: 500, category: cat)

        let marchDate = Date()
        _ = makeTransaction(amount: 20, type: .expense, category: cat, date: marchDate)
        _ = makeTransaction(amount: 50, type: .expense, category: cat, date: marchDate, excludeFromReports: true) // excluded from report

        let spent = BudgetCalculator.calculateSpending(for: budget, transactions: allTransactions(), targetCurrency: "USD")
        XCTAssertEqual(spent, 20, "Spending should exclude transactions marked as excludeFromReports")
    }

    func testCalculateIncomeExcludesReports() {
        let budget = makeBudget(limit: 500)

        let marchDate = Date()
        _ = makeTransaction(amount: 1000, type: .income, date: marchDate)
        _ = makeTransaction(amount: 500, type: .income, date: marchDate, excludeFromReports: true) // excluded from report

        let income = BudgetCalculator.calculateIncome(for: budget, transactions: allTransactions())
        XCTAssertEqual(income, 1000, "Income calculation should exclude transactions marked as excludeFromReports")
    }

    // MARK: - Single-pass batch (C2)

    func testSpendingByBudgetMatchesPerBudgetCalculation() {
        let food = makeCategory(name: "Food")
        let transport = makeCategory(name: "Transport")

        let foodBudget = makeBudget(limit: 500, category: food)
        let transportBudget = makeBudget(limit: 300, category: transport)
        let totalBudget = makeBudget(limit: 1000) // no category → all expenses

        let marchDate = Date()
        let febDate = Calendar.current.date(byAdding: .month, value: -2, to: marchDate)!
        _ = makeTransaction(amount: 30, type: .expense, category: food, date: marchDate)
        _ = makeTransaction(amount: 50, type: .expense, category: transport, date: marchDate)
        _ = makeTransaction(amount: 999, type: .expense, category: food, date: febDate) // outside period
        _ = makeTransaction(amount: 20, type: .expense, category: food, date: marchDate, excludeFromReports: true) // excluded
        _ = makeTransaction(amount: 100, type: .income, category: food, date: marchDate) // income ignored

        let budgets = [foodBudget, transportBudget, totalBudget]
        let txns = allTransactions()
        let batch = BudgetCalculator.spendingByBudget(for: budgets, transactions: txns, targetCurrency: "USD")

        // Batch must equal the per-budget method for every budget.
        for budget in budgets {
            let perBudget = BudgetCalculator.calculateSpending(for: budget, transactions: txns, targetCurrency: "USD")
            XCTAssertEqual(batch[budget.id], perBudget, "Batch mismatch for budget \(budget.displayName)")
        }

        XCTAssertEqual(batch[foodBudget.id], 30)
        XCTAssertEqual(batch[transportBudget.id], 50)
        XCTAssertEqual(batch[totalBudget.id], 80) // 30 + 50, excludes income/excluded/out-of-period
    }
}
