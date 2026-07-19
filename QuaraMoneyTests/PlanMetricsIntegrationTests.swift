import SwiftData
import XCTest
@testable import QuaraMoney

@MainActor
final class PlanMetricsIntegrationTests: XCTestCase {
    private enum ExpectedFailure: Error { case save }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testBudgetLoaderCountsArchivedWalletSpending() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let wallet = Wallet(name: "Archived", currencyCode: "USD", icon: "wallet.pass", colorHex: "#000000")
        wallet.isArchived = true
        let budget = Budget(
            amountLimit: 100,
            currencyCode: "USD",
            periodType: .monthly,
            startDate: date(2026, 1, 1),
            isRecurring: true
        )
        let expense = Transaction(amount: 30, currencyCode: "USD", date: date(2026, 7, 10), type: .expense)
        expense.sourceWallet = wallet
        context.insert(wallet)
        context.insert(budget)
        context.insert(expense)
        try context.save()

        let items = try PlanMetricsLoader.loadBudgetList(
            context: context,
            segment: .active,
            rates: ["USD": 1],
            now: date(2026, 7, 18),
            calendar: calendar
        )
        XCTAssertEqual(items.first(where: { $0.budgetID == budget.id })?.projection.spent, 30)
    }

    func testSavingsLedgerCalculatorMatchesReconciler() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let wallet = Wallet(name: "Wallet", currencyCode: "USD", icon: "wallet.pass", colorHex: "#000000")
        let goal = SavingsGoal(name: "Goal", targetAmount: 100, currencyCode: "USD")
        goal.currentAmount = 10
        goal.startingBalanceCurrencyCode = "USD"
        let contribution = Transaction(amount: 30, currencyCode: "USD", date: date(2026, 7, 1), type: .transfer)
        contribution.sourceWallet = wallet
        contribution.destinationWallet = wallet
        contribution.savingsGoal = goal
        let withdrawal = Transaction(amount: 5, currencyCode: "USD", date: date(2026, 7, 2), type: .transfer)
        withdrawal.sourceWallet = wallet
        withdrawal.destinationWallet = wallet
        withdrawal.savingsGoal = goal
        withdrawal.savingsIsWithdrawal = true
        context.insert(wallet)
        context.insert(goal)
        context.insert(contribution)
        context.insert(withdrawal)
        try context.save()

        let rows = [
            SavingsLedgerEntrySnapshot(id: contribution.id, goalID: goal.id, date: contribution.date, amount: 30, currencyCode: "USD", isWithdrawal: false),
            SavingsLedgerEntrySnapshot(id: withdrawal.id, goalID: goal.id, date: withdrawal.date, amount: 5, currencyCode: "USD", isWithdrawal: true)
        ]
        let pure = SavingsLedgerCalculator.calculate(
            startingBalance: 10,
            startingCurrencyCode: "USD",
            goalCurrencyCode: "USD",
            rows: rows,
            rates: ["USD": 1]
        )
        let reconciled = SavingsGoalReconciler.total(for: goal, rates: ["USD": 1])
        XCTAssertEqual(reconciled.total, pure.total)
        XCTAssertEqual(reconciled.hasUnconvertedRows, pure.hasUnconvertedRows)
    }

    func testCompletedGoalStillAcceptsContributionAndWithdrawalLedgerRows() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let wallet = Wallet(name: "Wallet", currencyCode: "USD", icon: "wallet.pass", colorHex: "#000000")
        let goal = SavingsGoal(name: "Goal", targetAmount: 100, currencyCode: "USD")
        let initial = Transaction(amount: 100, currencyCode: "USD", date: date(2026, 7, 1), type: .transfer)
        initial.sourceWallet = wallet
        initial.destinationWallet = wallet
        initial.savingsGoal = goal
        context.insert(wallet)
        context.insert(goal)
        context.insert(initial)
        try context.save()
        XCTAssertTrue(SavingsGoalReconciler.reconcile(goal))
        XCTAssertTrue(goal.isCompleted)

        let extra = Transaction(amount: 10, currencyCode: "USD", date: date(2026, 7, 2), type: .transfer)
        extra.sourceWallet = wallet
        extra.destinationWallet = wallet
        extra.savingsGoal = goal
        context.insert(extra)
        XCTAssertEqual(SavingsGoalReconciler.total(for: goal, rates: ["USD": 1]).total, 110)
        XCTAssertTrue(goal.isCompleted)

        let withdrawal = Transaction(amount: 20, currencyCode: "USD", date: date(2026, 7, 3), type: .transfer)
        withdrawal.sourceWallet = wallet
        withdrawal.destinationWallet = wallet
        withdrawal.savingsGoal = goal
        withdrawal.savingsIsWithdrawal = true
        context.insert(withdrawal)
        XCTAssertTrue(SavingsGoalReconciler.reconcile(goal))
        XCTAssertEqual(SavingsGoalReconciler.total(for: goal, rates: ["USD": 1]).total, 90)
        XCTAssertFalse(goal.isCompleted)
    }

    func testSeeAllSafeConversionSummarySortAndLegacyDefaults() {
        let base = TransactionFilterConfig(
            title: "Budget",
            startDate: date(2026, 7, 1),
            endDate: date(2026, 8, 1),
            dateRangeDescription: "July"
        )
        let explicitLegacy = TransactionFilterConfig(
            title: "Budget",
            startDate: date(2026, 7, 1),
            endDate: date(2026, 8, 1),
            dateRangeDescription: "July",
            reportExclusionPolicy: .include,
            archivedWalletPolicy: .exclude,
            summaryCurrencyCode: nil,
            conversionPolicy: .legacyFallback,
            budgetRelevancePolicy: .disabled
        )
        XCTAssertEqual(base, explicitLegacy)

        let usd = Transaction(amount: 10, currencyCode: "USD", date: date(2026, 7, 1), type: .expense)
        let unknown = Transaction(amount: 999, currencyCode: "ZZZ", date: date(2026, 7, 2), type: .expense)
        let total = FilteredTransactionsViewModel.total(
            transactions: [usd, unknown],
            rates: ["USD": 1],
            targetCurrency: "USD",
            typeFilter: .expense,
            policy: .rateChecked
        )
        XCTAssertEqual(total.total, 10)
        XCTAssertFalse(total.isDeterminate)
        XCTAssertTrue(FilteredTransactionsViewModel.amountSort(
            usd, unknown, ascending: false, currency: "USD", rates: ["USD": 1], policy: .rateChecked
        ))

        let planConfig = TransactionFilterConfig(
            title: "Budget",
            startDate: date(2026, 7, 1),
            endDate: date(2026, 8, 1),
            dateRangeDescription: "July",
            summaryCurrencyCode: "KHR",
            conversionPolicy: .rateChecked,
            budgetRelevancePolicy: .sharedPredicate
        )
        XCTAssertEqual(planConfig.summaryCurrencyCode, "KHR")
        XCTAssertEqual(planConfig.budgetRelevancePolicy, .sharedPredicate)
    }

    func testCurrencyChangeResolverCoversConvertKeepAndCancel() {
        XCTAssertEqual(PlanCurrencyChangeResolver.resolve(
            amount: 10,
            from: "USD",
            to: "KHR",
            rates: ["USD": 1, "KHR": 4_000],
            decision: .convert
        ), 40_000)
        XCTAssertEqual(PlanCurrencyChangeResolver.resolve(
            amount: 10,
            from: "USD",
            to: "KHR",
            rates: [:],
            decision: .keepNumber
        ), 10)
        XCTAssertNil(PlanCurrencyChangeResolver.resolve(
            amount: 10,
            from: "USD",
            to: "KHR",
            rates: ["USD": 1, "KHR": 4_000],
            decision: .cancel
        ))
        XCTAssertNil(PlanCurrencyChangeResolver.resolve(
            amount: 10,
            from: "USD",
            to: "ZZZ",
            rates: ["USD": 1],
            decision: .convert
        ))
    }

    func testMutationHelperRestoresEditCreateAndDeleteFailures() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let budget = Budget(amountLimit: 100)
        context.insert(budget)
        try context.save()
        var notificationCount = 0
        let failing = PlanMutationExecutor(
            saveContext: { _ in throw ExpectedFailure.save },
            postUpdate: { notificationCount += 1 }
        )

        XCTAssertThrowsError(try failing.perform(
            in: context,
            apply: { budget.amountLimit = 200 },
            rollback: { budget.amountLimit = 100 }
        ))
        XCTAssertEqual(budget.amountLimit, 100)

        var created: Budget?
        XCTAssertThrowsError(try failing.perform(
            in: context,
            apply: {
                let value = Budget(amountLimit: 50)
                created = value
                context.insert(value)
            },
            rollback: {
                if let created { context.delete(created) }
            }
        ))
        XCTAssertTrue(context.deletedModelsArray.contains {
            $0.persistentModelID == created?.persistentModelID
        })

        budget.updatedAt = date(2026, 1, 1)
        budget.needsSync = false
        XCTAssertThrowsError(try failing.softDelete(budget, in: context))
        XCTAssertNil(budget.deletedAt)
        XCTAssertEqual(budget.updatedAt, date(2026, 1, 1))
        XCTAssertFalse(budget.needsSync)
        XCTAssertEqual(notificationCount, 0)
    }
}
