import XCTest
@testable import QuaraMoney

@MainActor
final class PlanMetricsLayerTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func category(_ id: UUID = UUID()) -> PlanCategorySnapshot {
        PlanCategorySnapshot(id: id, name: "Food", icon: "fork.knife", colorHex: "#FF0000")
    }

    private func budget(
        id: UUID = UUID(),
        limit: Decimal = 100,
        currency: String = "USD",
        target: BudgetTargetKind = .total,
        period: BudgetPeriodType = .monthly,
        start: Date? = nil,
        end: Date? = nil,
        created: Date? = nil,
        categories: [PlanCategorySnapshot] = []
    ) -> PlanBudgetSnapshot {
        PlanBudgetSnapshot(
            id: id,
            amountLimit: limit,
            currencyCode: currency,
            targetKind: target,
            periodType: period,
            startDate: start ?? date(2026, 1, 1),
            customEndDate: end,
            weekStartDay: 2,
            createdAt: created ?? date(2026, 1, 1),
            categories: categories
        )
    }

    private func transaction(
        id: UUID = UUID(),
        on transactionDate: Date? = nil,
        kind: PlanTransactionKind = .expense,
        amount: Decimal = 10,
        currency: String = "USD",
        categoryID: UUID? = nil,
        deleted: Bool = false,
        eventLinked: Bool = false,
        excluded: Bool = false,
        archived: Bool = false
    ) -> PlanTransactionSnapshot {
        PlanTransactionSnapshot(
            id: id,
            date: transactionDate ?? date(2026, 7, 10),
            kind: kind,
            amount: amount,
            currencyCode: currency,
            categoryID: categoryID,
            isDeleted: deleted,
            isEventLinked: eventLinked,
            isExcludedFromReports: excluded,
            sourceWalletIsArchived: archived
        )
    }

    private func goal(
        id: UUID = UUID(),
        target: Decimal = 100,
        currency: String = "USD",
        current: Decimal = 0,
        startingCurrency: String = "USD",
        targetDate: Date? = nil,
        created: Date? = nil
    ) -> PlanSavingsGoalSnapshot {
        PlanSavingsGoalSnapshot(
            id: id,
            targetAmount: target,
            currencyCode: currency,
            currentAmount: current,
            startingBalanceCurrencyCode: startingCurrency,
            targetDate: targetDate,
            createdDate: created ?? date(2026, 1, 1),
            iconName: "target",
            colorHex: "#00AA00",
            priority: 0
        )
    }

    private func overview(
        budgets: [PlanBudgetSnapshot] = [],
        transactions: [PlanTransactionSnapshot] = [],
        goals: [PlanSavingsGoalSnapshot] = [],
        rows: [SavingsLedgerEntrySnapshot] = [],
        rates: [String: Double] = ["USD": 1, "KHR": 4_000]
    ) -> PlanOverviewMetrics {
        PlanOverviewMetrics.compute(
            budgets: budgets,
            budgetTransactions: transactions,
            goals: goals,
            ledgerRows: rows,
            preferredCurrency: "USD",
            rates: rates,
            now: date(2026, 7, 18),
            calendar: calendar
        )
    }

    func testMonthlyEquivalentForEveryStandingPeriod() {
        XCTAssertEqual(budget(limit: 120, period: .weekly).monthlyEquivalentLimit, 520)
        XCTAssertEqual(budget(limit: 120, period: .biweekly).monthlyEquivalentLimit, 260)
        XCTAssertEqual(budget(limit: 120, period: .monthly).monthlyEquivalentLimit, 120)
        XCTAssertEqual(budget(limit: 120, period: .quarterly).monthlyEquivalentLimit, 40)
        XCTAssertEqual(budget(limit: 120, period: .yearly).monthlyEquivalentLimit, 10)
        XCTAssertNil(budget(limit: 120, period: .custom).monthlyEquivalentLimit)
    }

    func testOverviewCanonicalTotalFiltersInvalidAndUsesPeriodPriority() {
        let metrics = overview(budgets: [
            budget(limit: 0, period: .monthly),
            budget(limit: 1_200, period: .yearly, created: date(2025, 1, 1)),
            budget(limit: 240, period: .weekly, created: date(2026, 1, 2))
        ])

        XCTAssertEqual(metrics.budgets.mode, .aggregateWithLimit)
        XCTAssertEqual(metrics.budgets.limit, 1_040)
    }

    func testOverviewCanonicalTotalUsesCreationAndUUIDTieBreakers() {
        let later = budget(limit: 900, period: .monthly, created: date(2026, 2, 1))
        let earlier = budget(limit: 700, period: .monthly, created: date(2026, 1, 1))
        XCTAssertEqual(overview(budgets: [later, earlier]).budgets.limit, 700)

        let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let low = budget(id: lowID, limit: 300, period: .monthly)
        let high = budget(id: highID, limit: 400, period: .monthly)
        XCTAssertEqual(overview(budgets: [high, low]).budgets.limit, 300)
    }

    func testOverviewUnionsDisjointCategoryBudgetsWithoutDoubleCounting() {
        let foodID = UUID()
        let travelID = UUID()
        let food = category(foodID)
        let travel = category(travelID)
        let metrics = overview(
            budgets: [
                budget(limit: 100, target: .categories, categories: [food]),
                budget(limit: 200, target: .categories, categories: [travel])
            ],
            transactions: [
                transaction(amount: 10, categoryID: foodID),
                transaction(amount: 20, categoryID: travelID),
                transaction(amount: 99, categoryID: UUID())
            ]
        )

        XCTAssertEqual(metrics.budgets.mode, .aggregateWithLimit)
        XCTAssertEqual(metrics.budgets.spent, 30)
        XCTAssertEqual(metrics.budgets.limit, 300)
    }

    func testOverviewDegradesOverlappingCategoriesToSpendingOnly() {
        let foodID = UUID()
        let food = category(foodID)
        let metrics = overview(
            budgets: [
                budget(limit: 100, target: .categories, categories: [food]),
                budget(limit: 200, target: .categories, categories: [food])
            ],
            transactions: [transaction(amount: 25, categoryID: foodID)]
        )

        XCTAssertEqual(metrics.budgets.mode, .spendingOnly)
        XCTAssertEqual(metrics.budgets.spent, 25)
        XCTAssertNil(metrics.budgets.limit)
    }

    func testOverviewNoValidTotalNeedsAttention() {
        let metrics = overview(budgets: [budget(limit: 0, target: .total)])
        XCTAssertEqual(metrics.budgets.mode, .attention)
        XCTAssertFalse(metrics.budgets.isDeterminate)
    }

    func testOverviewPropagatesFXIndeterminacy() {
        let metrics = overview(
            budgets: [budget(limit: 100)],
            transactions: [transaction(amount: 20, currency: "ZZZ")],
            rates: ["USD": 1]
        )
        XCTAssertFalse(metrics.budgets.isDeterminate)
        XCTAssertGreaterThan(metrics.budgets.unknownCount, 0)
    }

    func testOverviewSavingsEmptyAllCompletedAndUnknownActiveStates() {
        XCTAssertEqual(overview().savings.mode, .empty)

        let completed = overview(goals: [goal(target: 100, current: 120)]).savings
        XCTAssertEqual(completed.mode, .allCompleted)
        XCTAssertEqual(completed.saved, 120)

        let unknown = overview(
            goals: [goal(target: 100, current: 50, startingCurrency: "EUR")],
            rates: ["USD": 1]
        ).savings
        XCTAssertEqual(unknown.mode, .active)
        XCTAssertFalse(unknown.isDeterminate)
        XCTAssertEqual(unknown.unknownCount, 1)
    }

    func testBudgetProjectionCrossCurrencyAndIndeterminateClassification() {
        let item = budget(limit: 50_000, currency: "KHR")
        let range = PlanDateRange(start: date(2026, 7, 1), end: date(2026, 8, 1))
        let determinate = BudgetSpendingProjection.compute(
            budget: item,
            transactions: [transaction(amount: 10, currency: "USD")],
            rates: ["USD": 1, "KHR": 4_000],
            range: range
        )
        XCTAssertEqual(determinate.spent, 40_000)
        XCTAssertEqual(determinate.progress, Decimal(string: "0.8"))
        XCTAssertEqual(determinate.isOnTrack, true)

        let unknown = BudgetSpendingProjection.compute(
            budget: item,
            transactions: [transaction(amount: 10, currency: "ZZZ")],
            rates: ["KHR": 4_000],
            range: range
        )
        XCTAssertFalse(unknown.isDeterminate)
        XCTAssertNil(unknown.isOnTrack)
    }

    func testConvertOrNilRejectsEveryInvalidRateShape() {
        let invalidRates: [Double] = [0, -1, .nan, .infinity, -.infinity]
        for invalid in invalidRates {
            XCTAssertNil(CurrencyManager.convertOrNil(
                amount: 10, from: "EUR", to: "USD", rates: ["EUR": invalid, "USD": 1]
            ))
            XCTAssertNil(CurrencyManager.convertOrNil(
                amount: 10, from: "EUR", to: "USD", rates: ["EUR": 1, "USD": invalid]
            ))
        }
    }

    func testSharedRelevancePredicateIncludesArchivedAndRejectsAllOtherInvalidRows() {
        let item = budget()
        let range = PlanDateRange(start: date(2026, 7, 1), end: date(2026, 8, 1))
        XCTAssertTrue(BudgetTransactionRelevance.isRelevant(
            transaction(archived: true), to: item, in: range
        ))
        XCTAssertFalse(BudgetTransactionRelevance.isRelevant(
            transaction(deleted: true), to: item, in: range
        ))
        XCTAssertFalse(BudgetTransactionRelevance.isRelevant(
            transaction(eventLinked: true), to: item, in: range
        ))
        XCTAssertFalse(BudgetTransactionRelevance.isRelevant(
            transaction(excluded: true), to: item, in: range
        ))
        XCTAssertFalse(BudgetTransactionRelevance.isRelevant(
            transaction(kind: .income), to: item, in: range
        ))
    }

    func testRangeAssemblyIncludesEndedCustomAndDoesNotSpanGaps() {
        let ended = budget(
            period: .custom,
            start: date(2026, 1, 1),
            end: date(2026, 1, 3)
        )
        let selected = BudgetListRangeAssembler.budgets(
            from: [ended], segment: .ended, now: date(2026, 7, 18), calendar: calendar
        )
        XCTAssertEqual(selected.map(\.id), [ended.id])
        XCTAssertEqual(
            BudgetListRangeAssembler.ranges(for: selected, now: date(2026, 7, 18), calendar: calendar),
            [PlanDateRange(start: date(2026, 1, 1), end: date(2026, 1, 4))]
        )

        let merged = BudgetListRangeAssembler.merge([
            PlanDateRange(start: date(2026, 1, 1), end: date(2026, 1, 3)),
            PlanDateRange(start: date(2026, 1, 3), end: date(2026, 1, 5)),
            PlanDateRange(start: date(2026, 1, 4), end: date(2026, 1, 7)),
            PlanDateRange(start: date(2026, 1, 10), end: date(2026, 1, 12))
        ])
        XCTAssertEqual(merged, [
            PlanDateRange(start: date(2026, 1, 1), end: date(2026, 1, 7)),
            PlanDateRange(start: date(2026, 1, 10), end: date(2026, 1, 12))
        ])
    }

    func testDuplicateDetectionExcludesEditedBudget() {
        let existing = budget(period: .monthly)
        XCTAssertFalse(PlanBudgetDuplicateDetector.isDuplicateTotal(
            periodType: .monthly,
            targetKind: .total,
            budgets: [existing],
            excluding: existing.id
        ))
        XCTAssertTrue(PlanBudgetDuplicateDetector.isDuplicateTotal(
            periodType: .monthly,
            targetKind: .total,
            budgets: [existing],
            excluding: nil
        ))
    }

    func testSavingsMetricsDerivesRemainingMonthlyTargetBehindAndUnknownClaims() {
        let item = goal(
            target: 100,
            targetDate: date(2026, 7, 1),
            created: date(2026, 1, 1)
        )
        let result = SavingsLedgerCalculator.Result(
            total: 20, rawTotal: 20, hasUnconvertedRows: false
        )
        let metrics = SavingsGoalMetrics.compute(
            goal: item, ledgerResult: result, now: date(2026, 4, 1), calendar: calendar
        )
        XCTAssertEqual(metrics.remaining, 80)
        XCTAssertEqual(metrics.monthlyTarget, Decimal(80) / Decimal(3))
        XCTAssertEqual(metrics.isBehind, true)
        XCTAssertEqual(metrics.isCompleted, false)

        let unknown = SavingsGoalMetrics.compute(
            goal: item,
            ledgerResult: .init(total: 20, rawTotal: 20, hasUnconvertedRows: true),
            now: date(2026, 4, 1),
            calendar: calendar
        )
        XCTAssertNil(unknown.isCompleted)
        XCTAssertNil(unknown.isBehind)
    }

    func testSavingsCalculatorUsesStampedLegacyStartingCurrency() {
        let result = SavingsLedgerCalculator.calculate(
            startingBalance: 40_000,
            startingCurrencyCode: "KHR",
            goalCurrencyCode: "USD",
            rows: [],
            rates: ["USD": 1, "KHR": 4_000]
        )
        XCTAssertEqual(result.total, 10)
        XCTAssertTrue(result.isDeterminate)
    }

    func testSavingsChartKeepsRawSignedBalanceFloorsPointsAndTiesUpcomingToLedger() {
        let goalID = UUID()
        let item = goal(id: goalID, current: 10)
        let rows = [
            SavingsLedgerEntrySnapshot(id: UUID(), goalID: goalID, date: date(2025, 12, 1), amount: 5, currencyCode: "USD", isWithdrawal: false),
            SavingsLedgerEntrySnapshot(id: UUID(), goalID: goalID, date: date(2025, 12, 2), amount: 20, currencyCode: "USD", isWithdrawal: true),
            SavingsLedgerEntrySnapshot(id: UUID(), goalID: goalID, date: date(2026, 1, 10), amount: 3, currencyCode: "USD", isWithdrawal: false),
            SavingsLedgerEntrySnapshot(id: UUID(), goalID: goalID, date: date(2026, 2, 10), amount: 10, currencyCode: "USD", isWithdrawal: false),
            SavingsLedgerEntrySnapshot(id: UUID(), goalID: goalID, date: date(2026, 3, 1), amount: 4, currencyCode: "USD", isWithdrawal: false)
        ]
        let series = SavingsProgressSeries.compute(
            goal: item,
            rows: rows,
            windowStart: date(2026, 1, 1),
            now: date(2026, 2, 15),
            calendar: calendar,
            rates: ["USD": 1]
        )
        let ledger = SavingsLedgerCalculator.calculate(
            startingBalance: 10,
            startingCurrencyCode: "USD",
            goalCurrencyCode: "USD",
            rows: rows,
            rates: ["USD": 1]
        )
        XCTAssertEqual(series.points.map(\.saved), [0, 8, 12])
        XCTAssertEqual(series.points.last?.isUpcoming, true)
        XCTAssertEqual(series.points.last?.saved, ledger.total)
    }
}
