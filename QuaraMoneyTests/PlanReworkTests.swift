import XCTest
import SwiftData
@testable import QuaraMoney

@MainActor
final class PlanReworkTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testCalendarAlignedMonthAndLeapFebruary() {
        let range = BudgetPeriodType.monthly.currentPeriodRange(containing: date(2028, 2, 18), calendar: calendar)
        XCTAssertEqual(range.start, date(2028, 2, 1))
        XCTAssertEqual(range.end, date(2028, 3, 1))
        XCTAssertEqual(calendar.dateComponents([.day], from: range.start, to: range.end).day, 29)
    }

    func testQuarterAndYearBoundaries() {
        let quarter = BudgetPeriodType.quarterly.currentPeriodRange(containing: date(2026, 12, 31), calendar: calendar)
        XCTAssertEqual(quarter.start, date(2026, 10, 1))
        XCTAssertEqual(quarter.end, date(2027, 1, 1))
        let year = BudgetPeriodType.yearly.currentPeriodRange(containing: date(2026, 7, 18), calendar: calendar)
        XCTAssertEqual(year.start, date(2026, 1, 1))
        XCTAssertEqual(year.end, date(2027, 1, 1))
    }

    func testCustomFinalDayIsInclusive() {
        let budget = Budget(amountLimit: 100, periodType: .custom,
                            startDate: date(2026, 7, 1), customEndDate: date(2026, 7, 18))
        let expected = Calendar.current.date(byAdding: .day, value: 1,
            to: Calendar.current.startOfDay(for: budget.customEndDate!))!
        XCTAssertEqual(budget.periodDateRange.end, expected)
    }

    func testNilTargetAndAlertGettersMatchLegacyFields() {
        let category = Category(name: "Food", icon: "fork.knife", colorHex: "#000000", type: .expense)
        let budget = Budget(amountLimit: 100, category: category)
        budget.targetKindRaw = nil
        budget.alertModeRaw = nil
        budget.alertAt80 = false
        budget.alertAt100 = true
        XCTAssertEqual(budget.targetKind, .categories)
        XCTAssertEqual(budget.alertMode, .overOnly)
    }

    func testCustomBudgetsCanShareCategoryAcrossDifferentDateRanges() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let category = Category(name: "Food", icon: "fork.knife", colorHex: "#000000", type: .expense)
        let july = Budget(
            amountLimit: 100,
            periodType: .custom,
            startDate: date(2026, 7, 1),
            customEndDate: date(2026, 7, 31),
            categories: [category]
        )
        let august = Budget(
            amountLimit: 120,
            periodType: .custom,
            startDate: date(2026, 8, 1),
            customEndDate: date(2026, 8, 31),
            categories: [category]
        )

        context.insert(category)
        context.insert(july)
        try context.save()
        context.insert(august)
        try context.save()

        let savedBudgets = try context.fetch(FetchDescriptor<Budget>())
        XCTAssertEqual(savedBudgets.count, 2)
        XCTAssertEqual(Set(july.trackedCategoryIds), [category.id])
        XCTAssertEqual(Set(august.trackedCategoryIds), [category.id])
    }

    func testSingleCategoryStorageDoesNotDetachExistingMultiCategoryBudget() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let category = Category(name: "Food", icon: "fork.knife", colorHex: "#000000", type: .expense)
        let existing = Budget(
            amountLimit: 100,
            periodType: .custom,
            startDate: date(2026, 7, 1),
            customEndDate: date(2026, 7, 31),
            categories: [category]
        )
        let newBudget = Budget(
            amountLimit: 120,
            periodType: .custom,
            startDate: date(2026, 8, 1),
            customEndDate: date(2026, 8, 31)
        )
        newBudget.setTrackedCategories([category], targetKind: .categories)

        context.insert(category)
        context.insert(existing)
        try context.save()
        context.insert(newBudget)
        try context.save()

        XCTAssertEqual(Set(existing.trackedCategoryIds), [category.id])
        XCTAssertEqual(Set(newBudget.trackedCategoryIds), [category.id])
        XCTAssertTrue(newBudget.category === category)
        XCTAssertNil(newBudget.categories)
    }

    func testTransferSideResolverAndWithdrawalLedger() {
        let source = Wallet(name: "USD", currencyCode: "USD", icon: "wallet.pass", colorHex: "#000000")
        let destination = Wallet(name: "KHR", currencyCode: "KHR", icon: "wallet.pass", colorHex: "#000000")
        let goal = SavingsGoal(name: "Goal", targetAmount: 100, currencyCode: "USD")
        let transaction = Transaction(amount: 10, currencyCode: "USD", date: Date(), type: .transfer)
        transaction.sourceWallet = source
        transaction.destinationWallet = destination
        transaction.storedRate = 4000
        transaction.savingsGoal = goal
        XCTAssertEqual(TransferSideAmountResolver.destinationAmount(for: transaction)?.amount, 40_000)
        transaction.savingsIsWithdrawal = true
        XCTAssertEqual(TransferSideAmountResolver.ledgerAmount(for: transaction)?.currencyCode, "USD")
        XCTAssertEqual(TransferSideAmountResolver.ledgerAmount(for: transaction)?.amount, 10)
    }

    func testReconcilerCompletesReactivatesAndFloorsOverWithdrawal() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let wallet = Wallet(name: "Wallet", currencyCode: "USD", icon: "wallet.pass", colorHex: "#000000")
        let goal = SavingsGoal(name: "Goal", targetAmount: 100, currencyCode: "USD")
        context.insert(wallet); context.insert(goal)
        let contribution = Transaction(amount: 120, currencyCode: "USD", date: Date(), type: .transfer)
        contribution.sourceWallet = wallet; contribution.destinationWallet = wallet; contribution.savingsGoal = goal
        context.insert(contribution)
        XCTAssertTrue(SavingsGoalReconciler.reconcile(goal))
        XCTAssertTrue(goal.isCompleted)
        contribution.savingsIsWithdrawal = true
        XCTAssertTrue(SavingsGoalReconciler.reconcile(goal))
        XCTAssertFalse(goal.isCompleted)
        XCTAssertEqual(SavingsGoalReconciler.total(for: goal).total, 0)
    }

    func testDeterministicAlertIdentifier() {
        let id = UUID()
        XCTAssertEqual(BudgetNotificationService.requestIdentifier(budgetID: id, periodKey: "2026-07", threshold: 80),
                       BudgetNotificationService.requestIdentifier(budgetID: id, periodKey: "2026-07", threshold: 80))
    }

    func testPerBudgetCurrencySinglePass() {
        let usd = Budget(amountLimit: 100, currencyCode: "USD", periodType: .monthly, isRecurring: true)
        let khr = Budget(amountLimit: 400_000, currencyCode: "KHR", periodType: .monthly, isRecurring: true)
        let transaction = Transaction(amount: 10, currencyCode: "USD", date: Date(), type: .expense)
        let totals = BudgetCalculator.spendingByBudgetCurrency(
            for: [usd, khr], transactions: [transaction], rates: ["USD": 1, "KHR": 4000]
        )
        XCTAssertEqual(totals[usd.id], 10)
        XCTAssertEqual(totals[khr.id], 40_000)
    }

    func testSuggestionUsesThreeZeroFilledCompletedBucketsAndNoData() async throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let category = Category(name: "Food", icon: "fork.knife", colorHex: "#000000", type: .expense)
        context.insert(category)
        let now = date(2026, 7, 18)
        for (month, amount) in [(4, Decimal(30)), (6, Decimal(60))] {
            let transaction = Transaction(amount: amount, currencyCode: "USD",
                date: date(2026, month, 10), type: .expense)
            transaction.category = category
            context.insert(transaction)
        }
        try context.save()
        let engine = BudgetSuggestionEngine(container: container)
        let suggested = await engine.suggestion(targetKind: .categories,
            categoryIDs: [category.id], periodType: .monthly, currencyCode: "USD",
            rates: ["USD": 1], now: now, calendar: calendar)
        let result = try XCTUnwrap(suggested)
        XCTAssertEqual(result.bucketAmounts, [30, 0, 60])
        XCTAssertEqual(result.averageSpending, 30)
        XCTAssertEqual(result.suggestedAmount, 33)

        let emptySuggestion = await engine.suggestion(targetKind: .categories,
            categoryIDs: [UUID()], periodType: .monthly, currencyCode: "USD",
            rates: ["USD": 1], now: now, calendar: calendar)
        let noData = try XCTUnwrap(emptySuggestion)
        XCTAssertNil(noData.suggestedAmount)
        XCTAssertEqual(noData.confidence, .noData)
    }

    func testPlanMaintenanceUsesInjectedRatesForPercentFreeze() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let now = date(2026, 7, 18)
        let budget = Budget(amountLimit: 0, currencyCode: "USD", periodType: .monthly,
                            startDate: date(2026, 1, 1), isRecurring: true)
        budget.amountType = .percentOfIncome(0.5)
        let income = Transaction(amount: 100, currencyCode: "EUR", date: date(2026, 6, 10), type: .income)
        context.insert(budget); context.insert(income)
        try context.save()
        _ = try PlanDataMaintenance.run(in: context, ownerID: UUID(),
            rates: ["USD": 1, "EUR": 2], calendar: calendar, now: now, commitsMarker: false)
        XCTAssertEqual(budget.amountLimit, 25)
    }
}
