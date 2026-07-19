import Foundation

// MARK: - Plain snapshots

nonisolated struct PlanDateRange: Sendable, Equatable {
    let start: Date
    let end: Date

    var isValid: Bool { start < end }

    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

nonisolated struct PlanCategorySnapshot: Sendable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let icon: String
    let colorHex: String
}

nonisolated enum PlanTransactionKind: String, Sendable, Equatable {
    case income
    case expense
    case transfer
    case adjustment
}

/// The transaction fields needed by Plan calculations. No SwiftData models
/// cross an actor boundary.
nonisolated struct PlanTransactionSnapshot: Sendable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let kind: PlanTransactionKind
    let amount: Decimal
    let currencyCode: String
    let categoryID: UUID?
    let isDeleted: Bool
    let isEventLinked: Bool
    let isExcludedFromReports: Bool
    let sourceWalletIsArchived: Bool
}

nonisolated struct PlanBudgetSnapshot: Sendable, Equatable, Identifiable {
    let id: UUID
    let amountLimit: Decimal
    let currencyCode: String
    let targetKind: BudgetTargetKind
    let periodType: BudgetPeriodType
    let startDate: Date
    let customEndDate: Date?
    let weekStartDay: Int?
    let createdAt: Date
    let categories: [PlanCategorySnapshot]

    var categoryIDs: Set<UUID> { Set(categories.map(\.id)) }
    var isStanding: Bool { periodType != .custom }
    var needsAttention: Bool {
        amountLimit <= 0 || (targetKind == .categories && categories.isEmpty)
    }

    func periodRange(containing date: Date, calendar baseCalendar: Calendar) -> PlanDateRange {
        if periodType == .custom {
            let start = baseCalendar.startOfDay(for: startDate)
            let inclusiveEnd = baseCalendar.startOfDay(for: customEndDate ?? startDate)
            let end = baseCalendar.date(byAdding: .day, value: 1, to: inclusiveEnd) ?? inclusiveEnd
            return PlanDateRange(start: start, end: end)
        }

        var calendar = baseCalendar
        if periodType == .weekly, let weekStartDay {
            calendar.firstWeekday = weekStartDay
        }
        let range = periodType.currentPeriodRange(containing: date, calendar: calendar)
        return PlanDateRange(start: range.start, end: range.end)
    }

    var monthlyEquivalentLimit: Decimal? {
        guard periodType != .custom else { return nil }
        switch periodType {
        case .weekly: return amountLimit * Decimal(52) / Decimal(12)
        case .biweekly: return amountLimit * Decimal(26) / Decimal(12)
        case .monthly: return amountLimit
        case .quarterly: return amountLimit / Decimal(3)
        case .yearly: return amountLimit / Decimal(12)
        case .custom: return nil
        }
    }
}

nonisolated struct PlanSavingsGoalSnapshot: Sendable, Equatable, Identifiable {
    let id: UUID
    let targetAmount: Decimal
    let currencyCode: String
    let currentAmount: Decimal
    let startingBalanceCurrencyCode: String
    let targetDate: Date?
    let createdDate: Date
    let iconName: String
    let colorHex: String
    let priority: Int
}

// MARK: - Budget relevance and projections

/// One relevance predicate for every redesigned budget surface. Archived
/// wallets are intentionally not rejected: spending remains part of the budget
/// after its source wallet is archived.
nonisolated enum BudgetTransactionRelevance {
    static func isRelevant(
        _ transaction: PlanTransactionSnapshot,
        to budget: PlanBudgetSnapshot,
        in range: PlanDateRange
    ) -> Bool {
        isRelevant(
            transaction,
            targetKind: budget.targetKind,
            categoryIDs: budget.categoryIDs,
            in: range
        )
    }

    static func isRelevant(
        _ transaction: PlanTransactionSnapshot,
        targetKind: BudgetTargetKind,
        categoryIDs: Set<UUID>,
        in range: PlanDateRange
    ) -> Bool {
        guard !transaction.isDeleted,
              !transaction.isEventLinked,
              !transaction.isExcludedFromReports,
              transaction.kind == .expense,
              range.contains(transaction.date) else {
            return false
        }

        if targetKind == .total { return true }
        guard let categoryID = transaction.categoryID else { return false }
        return categoryIDs.contains(categoryID)
    }

    static func isReportExpense(_ transaction: PlanTransactionSnapshot, in range: PlanDateRange) -> Bool {
        !transaction.isDeleted &&
            !transaction.isEventLinked &&
            !transaction.isExcludedFromReports &&
            transaction.kind == .expense &&
            range.contains(transaction.date)
    }
}

nonisolated struct BudgetSpendingProjection: Sendable, Equatable {
    let spent: Decimal
    let limit: Decimal
    let progress: Decimal
    let isDeterminate: Bool
    let relevantTransactionIDs: [UUID]

    var remaining: Decimal { max(0, limit - spent) }
    var overage: Decimal { max(0, spent - limit) }
    var isOnTrack: Bool? {
        guard isDeterminate, limit > 0 else { return nil }
        return spent <= limit
    }

    static func compute(
        budget: PlanBudgetSnapshot,
        transactions: [PlanTransactionSnapshot],
        rates: [String: Double],
        range: PlanDateRange
    ) -> BudgetSpendingProjection {
        var spent: Decimal = 0
        var isDeterminate = true
        var ids: [UUID] = []

        for transaction in transactions where BudgetTransactionRelevance.isRelevant(transaction, to: budget, in: range) {
            ids.append(transaction.id)
            if let converted = CurrencyManager.convertOrNil(
                amount: transaction.amount,
                from: transaction.currencyCode,
                to: budget.currencyCode,
                rates: rates
            ) {
                spent += converted
            } else {
                isDeterminate = false
            }
        }

        let limit = budget.amountLimit
        let progress = limit > 0 ? spent / limit : 0
        return BudgetSpendingProjection(
            spent: spent,
            limit: limit,
            progress: progress,
            isDeterminate: isDeterminate,
            relevantTransactionIDs: ids
        )
    }
}

nonisolated struct BudgetTrendPoint: Sendable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let cumulativeSpent: Decimal
}

nonisolated struct BudgetTrendSeries: Sendable, Equatable {
    let points: [BudgetTrendPoint]
    let isDeterminate: Bool
    let isDegenerate: Bool

    static func compute(
        budget: PlanBudgetSnapshot,
        transactions: [PlanTransactionSnapshot],
        rates: [String: Double],
        range: PlanDateRange,
        now: Date,
        calendar: Calendar
    ) -> BudgetTrendSeries {
        let totalDays = calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 0
        guard totalDays > 1 else {
            return BudgetTrendSeries(points: [], isDeterminate: true, isDegenerate: true)
        }

        var byDay: [Date: Decimal] = [:]
        var isDeterminate = true
        for transaction in transactions where BudgetTransactionRelevance.isRelevant(transaction, to: budget, in: range) {
            guard let converted = CurrencyManager.convertOrNil(
                amount: transaction.amount,
                from: transaction.currencyCode,
                to: budget.currencyCode,
                rates: rates
            ) else {
                isDeterminate = false
                continue
            }
            byDay[calendar.startOfDay(for: transaction.date), default: 0] += converted
        }

        let todayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let displayEnd = min(range.end, max(range.start, todayEnd))
        var cursor = range.start
        var cumulative: Decimal = 0
        var points: [BudgetTrendPoint] = []
        while cursor < displayEnd {
            cumulative += byDay[cursor, default: 0]
            points.append(BudgetTrendPoint(date: cursor, cumulativeSpent: cumulative))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }

        return BudgetTrendSeries(
            points: points,
            isDeterminate: isDeterminate,
            isDegenerate: false
        )
    }
}

// MARK: - Budget list range assembly and duplicate policy

nonisolated enum PlanBudgetSegment: String, CaseIterable, Sendable, Identifiable {
    case active
    case ended
    var id: String { rawValue }
}

nonisolated enum PlanSavingsSegment: String, CaseIterable, Sendable, Identifiable {
    case active
    case completed
    var id: String { rawValue }
}

nonisolated enum BudgetListRangeAssembler {
    static func budgets(
        from allBudgets: [PlanBudgetSnapshot],
        segment: PlanBudgetSegment,
        now: Date,
        calendar: Calendar
    ) -> [PlanBudgetSnapshot] {
        allBudgets.filter { budget in
            let range = budget.periodRange(containing: now, calendar: calendar)
            switch segment {
            case .active:
                return budget.isStanding || now < range.end
            case .ended:
                return !budget.isStanding && now >= range.end
            }
        }
    }

    static func ranges(
        for budgets: [PlanBudgetSnapshot],
        now: Date,
        calendar: Calendar
    ) -> [PlanDateRange] {
        budgets.map { $0.periodRange(containing: now, calendar: calendar) }.filter(\.isValid)
    }

    /// Merges overlap and exact adjacency only. A real gap always starts a new
    /// fetch interval, preventing a sparse history from collapsing into one
    /// unbounded min-to-max query.
    static func merge(_ ranges: [PlanDateRange]) -> [PlanDateRange] {
        let sorted = ranges.filter(\.isValid).sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.end < $1.end
        }
        guard var current = sorted.first else { return [] }
        var merged: [PlanDateRange] = []

        for next in sorted.dropFirst() {
            if next.start <= current.end {
                current = PlanDateRange(start: current.start, end: max(current.end, next.end))
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }
}

nonisolated enum PlanBudgetDuplicateDetector {
    static func canonicalOrder(_ lhs: PlanBudgetSnapshot, _ rhs: PlanBudgetSnapshot) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func duplicateTotalIDs(in budgets: [PlanBudgetSnapshot]) -> Set<UUID> {
        let totals = budgets.filter { $0.isStanding && $0.targetKind == .total }
        let groups = Dictionary(grouping: totals, by: \.periodType)
        var duplicates = Set<UUID>()
        for group in groups.values where group.count > 1 {
            let sorted = group.sorted(by: canonicalOrder)
            duplicates.formUnion(sorted.dropFirst().map(\.id))
        }
        return duplicates
    }

    static func isDuplicateTotal(
        periodType: BudgetPeriodType,
        targetKind: BudgetTargetKind,
        budgets: [PlanBudgetSnapshot],
        excluding budgetID: UUID?
    ) -> Bool {
        guard targetKind == .total, periodType != .custom else { return false }
        return budgets.contains {
            $0.id != budgetID && $0.isStanding && $0.targetKind == .total && $0.periodType == periodType
        }
    }
}

// MARK: - Savings metrics and chart

nonisolated struct SavingsGoalMetrics: Sendable, Equatable {
    let saved: Decimal
    let remaining: Decimal
    let progress: Decimal
    let monthlyTarget: Decimal?
    let isCompleted: Bool?
    let isBehind: Bool?
    let isDeterminate: Bool

    static func compute(
        goal: PlanSavingsGoalSnapshot,
        ledgerResult: SavingsLedgerCalculator.Result,
        now: Date,
        calendar: Calendar
    ) -> SavingsGoalMetrics {
        let saved = ledgerResult.total
        let remaining = max(0, goal.targetAmount - saved)
        let progress = goal.targetAmount > 0 ? saved / goal.targetAmount : 0
        let isDeterminate = ledgerResult.isDeterminate
        let completed = isDeterminate ? saved >= goal.targetAmount : nil

        let monthlyTarget: Decimal?
        if let targetDate = goal.targetDate, targetDate > now, remaining > 0 {
            let months = calendar.dateComponents([.month], from: now, to: targetDate).month ?? 0
            monthlyTarget = months > 0 ? remaining / Decimal(months) : remaining
        } else {
            monthlyTarget = nil
        }

        let behind: Bool?
        if !isDeterminate {
            behind = nil
        } else if let targetDate = goal.targetDate {
            let totalDays = calendar.dateComponents([.day], from: goal.createdDate, to: targetDate).day ?? 0
            let daysRemaining = calendar.dateComponents([.day], from: now, to: targetDate).day ?? 0
            if totalDays > 0, daysRemaining > 0 {
                let elapsed = Decimal(max(0, totalDays - daysRemaining))
                let expected = elapsed / Decimal(totalDays)
                behind = progress < expected * Decimal(string: "0.9")!
            } else {
                behind = false
            }
        } else {
            behind = false
        }

        return SavingsGoalMetrics(
            saved: saved,
            remaining: remaining,
            progress: progress,
            monthlyTarget: monthlyTarget,
            isCompleted: completed,
            isBehind: behind,
            isDeterminate: isDeterminate
        )
    }
}

nonisolated struct SavingsProgressPoint: Sendable, Equatable, Identifiable {
    let id: String
    let date: Date
    let saved: Decimal
    let isUpcoming: Bool
}

nonisolated struct SavingsProgressSeries: Sendable, Equatable {
    let points: [SavingsProgressPoint]
    let isDeterminate: Bool

    static func compute(
        goal: PlanSavingsGoalSnapshot,
        rows: [SavingsLedgerEntrySnapshot],
        windowStart: Date,
        now: Date,
        calendar: Calendar,
        rates: [String: Double]
    ) -> SavingsProgressSeries {
        var rawRunning: Decimal = 0
        var isDeterminate = true

        if goal.currentAmount != 0 {
            if let converted = SavingsLedgerCalculator.convertStrict(
                goal.currentAmount,
                from: goal.startingBalanceCurrencyCode,
                to: goal.currencyCode,
                rates: rates
            ) {
                rawRunning += converted
            } else {
                isDeterminate = false
            }
        }

        let goalRows = rows.filter { $0.goalID == goal.id }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }
        var currentRows: [SavingsLedgerEntrySnapshot] = []
        var futureRows: [SavingsLedgerEntrySnapshot] = []

        for row in goalRows {
            guard let converted = SavingsLedgerCalculator.convertStrict(
                row.amount,
                from: row.currencyCode,
                to: goal.currencyCode,
                rates: rates
            ) else {
                isDeterminate = false
                continue
            }
            let signed = row.isWithdrawal ? -converted : converted
            if row.date < windowStart {
                rawRunning += signed
            } else if row.date <= now {
                currentRows.append(row)
            } else {
                futureRows.append(row)
            }
        }

        let startMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: windowStart)) ?? windowStart
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        var cursor = startMonth
        var points: [SavingsProgressPoint] = []

        while cursor <= currentMonth {
            let next = calendar.date(byAdding: .month, value: 1, to: cursor) ?? cursor
            for row in currentRows where row.date >= cursor && row.date < next {
                if let converted = SavingsLedgerCalculator.convertStrict(
                    row.amount,
                    from: row.currencyCode,
                    to: goal.currencyCode,
                    rates: rates
                ) {
                    rawRunning += row.isWithdrawal ? -converted : converted
                }
            }
            points.append(SavingsProgressPoint(
                id: "month-\(cursor.timeIntervalSinceReferenceDate)",
                date: cursor,
                saved: max(0, rawRunning),
                isUpcoming: false
            ))
            guard next > cursor else { break }
            cursor = next
        }

        if !futureRows.isEmpty {
            for row in futureRows {
                if let converted = SavingsLedgerCalculator.convertStrict(
                    row.amount,
                    from: row.currencyCode,
                    to: goal.currencyCode,
                    rates: rates
                ) {
                    rawRunning += row.isWithdrawal ? -converted : converted
                }
            }
            let upcomingDate = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? now
            points.append(SavingsProgressPoint(
                id: "upcoming",
                date: upcomingDate,
                saved: max(0, rawRunning),
                isUpcoming: true
            ))
        }

        return SavingsProgressSeries(points: points, isDeterminate: isDeterminate)
    }
}

// MARK: - Overview metrics

nonisolated enum PlanBudgetOverviewMode: Sendable, Equatable {
    case empty
    case attention
    case aggregateWithLimit
    case spendingOnly
}

nonisolated struct PlanBudgetOverviewMetrics: Sendable, Equatable {
    let mode: PlanBudgetOverviewMode
    let spent: Decimal
    let limit: Decimal?
    let currencyCode: String
    let progress: Decimal?
    let itemCount: Int
    let onTrackCount: Int
    let classifiedCount: Int
    let unknownCount: Int
    let isDeterminate: Bool
}

nonisolated enum PlanSavingsOverviewMode: Sendable, Equatable {
    case empty
    case active
    case allCompleted
}

nonisolated struct PlanSavingsOverviewMetrics: Sendable, Equatable {
    let mode: PlanSavingsOverviewMode
    let saved: Decimal
    let target: Decimal?
    let currencyCode: String
    let progress: Decimal?
    let activeCount: Int
    let completedCount: Int
    let unknownCount: Int
    let isDeterminate: Bool
}

nonisolated struct PlanOverviewMetrics: Sendable, Equatable {
    let budgets: PlanBudgetOverviewMetrics
    let savings: PlanSavingsOverviewMetrics

    static func compute(
        budgets: [PlanBudgetSnapshot],
        budgetTransactions: [PlanTransactionSnapshot],
        goals: [PlanSavingsGoalSnapshot],
        ledgerRows: [SavingsLedgerEntrySnapshot],
        preferredCurrency: String,
        rates: [String: Double],
        now: Date,
        calendar: Calendar
    ) -> PlanOverviewMetrics {
        PlanOverviewMetrics(
            budgets: computeBudgets(
                budgets: budgets,
                transactions: budgetTransactions,
                preferredCurrency: preferredCurrency,
                rates: rates,
                now: now,
                calendar: calendar
            ),
            savings: computeSavings(
                goals: goals,
                ledgerRows: ledgerRows,
                preferredCurrency: preferredCurrency,
                rates: rates,
                now: now,
                calendar: calendar
            )
        )
    }

    private static func computeBudgets(
        budgets: [PlanBudgetSnapshot],
        transactions: [PlanTransactionSnapshot],
        preferredCurrency: String,
        rates: [String: Double],
        now: Date,
        calendar: Calendar
    ) -> PlanBudgetOverviewMetrics {
        guard !budgets.isEmpty else {
            return PlanBudgetOverviewMetrics(
                mode: .empty, spent: 0, limit: nil, currencyCode: preferredCurrency,
                progress: nil, itemCount: 0, onTrackCount: 0,
                classifiedCount: 0, unknownCount: 0, isDeterminate: true
            )
        }

        let classifiable = budgets.filter { budget in
            if budget.isStanding { return true }
            let range = budget.periodRange(containing: now, calendar: calendar)
            return range.contains(now)
        }
        var onTrackCount = 0
        var classifiedCount = 0
        var unknownCount = 0
        for budget in classifiable {
            let range = budget.periodRange(containing: now, calendar: calendar)
            let projection = BudgetSpendingProjection.compute(
                budget: budget,
                transactions: transactions,
                rates: rates,
                range: range
            )
            if let isOnTrack = projection.isOnTrack {
                classifiedCount += 1
                if isOnTrack { onTrackCount += 1 }
            } else {
                unknownCount += 1
            }
        }

        let standingTotals = budgets.filter { $0.isStanding && $0.targetKind == .total }
        let validTotals = standingTotals.filter { $0.amountLimit > 0 && !$0.needsAttention }
        let canonical = validTotals.sorted(by: canonicalTotalOrder).first
        let monthTuple = BudgetPeriodType.monthly.currentPeriodRange(containing: now, calendar: calendar)
        let monthRange = PlanDateRange(start: monthTuple.start, end: monthTuple.end)

        if let canonical, let monthlyLimit = canonical.monthlyEquivalentLimit {
            let result = sumExpenses(
                transactions: transactions,
                range: monthRange,
                categoryIDs: nil,
                targetCurrency: canonical.currencyCode,
                rates: rates
            )
            return PlanBudgetOverviewMetrics(
                mode: .aggregateWithLimit,
                spent: result.total,
                limit: monthlyLimit,
                currencyCode: canonical.currencyCode,
                progress: monthlyLimit > 0 ? result.total / monthlyLimit : nil,
                itemCount: budgets.count,
                onTrackCount: onTrackCount,
                classifiedCount: classifiedCount,
                unknownCount: unknownCount + (result.isDeterminate ? 0 : 1),
                isDeterminate: result.isDeterminate
            )
        }

        if !standingTotals.isEmpty {
            return PlanBudgetOverviewMetrics(
                mode: .attention, spent: 0, limit: nil, currencyCode: preferredCurrency,
                progress: nil, itemCount: budgets.count, onTrackCount: onTrackCount,
                classifiedCount: classifiedCount, unknownCount: unknownCount,
                isDeterminate: false
            )
        }

        let categoryBudgets = budgets.filter {
            $0.isStanding && $0.targetKind == .categories && $0.amountLimit > 0 && !$0.categories.isEmpty
        }
        guard !categoryBudgets.isEmpty else {
            return PlanBudgetOverviewMetrics(
                mode: .attention, spent: 0, limit: nil, currencyCode: preferredCurrency,
                progress: nil, itemCount: budgets.count, onTrackCount: onTrackCount,
                classifiedCount: classifiedCount, unknownCount: unknownCount,
                isDeterminate: false
            )
        }

        let union = categoryBudgets.reduce(into: Set<UUID>()) { $0.formUnion($1.categoryIDs) }
        let hasOverlap = categoryScopesOverlap(categoryBudgets)
        let spending = sumExpenses(
            transactions: transactions,
            range: monthRange,
            categoryIDs: union,
            targetCurrency: preferredCurrency,
            rates: rates
        )

        if hasOverlap {
            return PlanBudgetOverviewMetrics(
                mode: .spendingOnly, spent: spending.total, limit: nil,
                currencyCode: preferredCurrency, progress: nil, itemCount: budgets.count,
                onTrackCount: onTrackCount, classifiedCount: classifiedCount,
                unknownCount: unknownCount + (spending.isDeterminate ? 0 : 1),
                isDeterminate: spending.isDeterminate
            )
        }

        var limit: Decimal = 0
        var limitDeterminate = true
        for budget in categoryBudgets {
            guard let monthly = budget.monthlyEquivalentLimit,
                  let converted = CurrencyManager.convertOrNil(
                    amount: monthly,
                    from: budget.currencyCode,
                    to: preferredCurrency,
                    rates: rates
                  ) else {
                limitDeterminate = false
                continue
            }
            limit += converted
        }
        let determinate = spending.isDeterminate && limitDeterminate
        return PlanBudgetOverviewMetrics(
            mode: .aggregateWithLimit, spent: spending.total, limit: limit,
            currencyCode: preferredCurrency, progress: limit > 0 ? spending.total / limit : nil,
            itemCount: budgets.count, onTrackCount: onTrackCount,
            classifiedCount: classifiedCount,
            unknownCount: unknownCount + (determinate ? 0 : 1),
            isDeterminate: determinate
        )
    }

    private static func computeSavings(
        goals: [PlanSavingsGoalSnapshot],
        ledgerRows: [SavingsLedgerEntrySnapshot],
        preferredCurrency: String,
        rates: [String: Double],
        now: Date,
        calendar: Calendar
    ) -> PlanSavingsOverviewMetrics {
        guard !goals.isEmpty else {
            return PlanSavingsOverviewMetrics(
                mode: .empty, saved: 0, target: nil, currencyCode: preferredCurrency,
                progress: nil, activeCount: 0, completedCount: 0,
                unknownCount: 0, isDeterminate: true
            )
        }

        let computed = goals.map { goal -> (PlanSavingsGoalSnapshot, SavingsGoalMetrics) in
            let rows = ledgerRows.filter { $0.goalID == goal.id }
            let ledger = SavingsLedgerCalculator.calculate(
                startingBalance: goal.currentAmount,
                startingCurrencyCode: goal.startingBalanceCurrencyCode,
                goalCurrencyCode: goal.currencyCode,
                rows: rows,
                rates: rates
            )
            return (goal, SavingsGoalMetrics.compute(goal: goal, ledgerResult: ledger, now: now, calendar: calendar))
        }

        let completedCount = computed.filter { $0.1.isCompleted == true }.count
        if completedCount == goals.count {
            var saved: Decimal = 0
            var determinate = true
            for (goal, metrics) in computed {
                guard let converted = SavingsLedgerCalculator.convertStrict(
                    metrics.saved,
                    from: goal.currencyCode,
                    to: preferredCurrency,
                    rates: rates
                ) else {
                    determinate = false
                    continue
                }
                saved += converted
            }
            return PlanSavingsOverviewMetrics(
                mode: .allCompleted, saved: saved, target: nil,
                currencyCode: preferredCurrency, progress: nil, activeCount: 0,
                completedCount: completedCount, unknownCount: determinate ? 0 : 1,
                isDeterminate: determinate
            )
        }

        var saved: Decimal = 0
        var target: Decimal = 0
        var activeCount = 0
        var unknownCount = 0
        for (goal, metrics) in computed where metrics.isCompleted != true {
            guard metrics.isDeterminate,
                  let convertedSaved = SavingsLedgerCalculator.convertStrict(
                    metrics.saved, from: goal.currencyCode, to: preferredCurrency, rates: rates
                  ),
                  let convertedTarget = SavingsLedgerCalculator.convertStrict(
                    goal.targetAmount, from: goal.currencyCode, to: preferredCurrency, rates: rates
                  ) else {
                unknownCount += 1
                continue
            }
            activeCount += 1
            saved += convertedSaved
            target += convertedTarget
        }

        return PlanSavingsOverviewMetrics(
            mode: .active, saved: saved, target: target,
            currencyCode: preferredCurrency, progress: target > 0 ? saved / target : nil,
            activeCount: activeCount, completedCount: completedCount,
            unknownCount: unknownCount, isDeterminate: unknownCount == 0
        )
    }

    private static func canonicalTotalOrder(_ lhs: PlanBudgetSnapshot, _ rhs: PlanBudgetSnapshot) -> Bool {
        let priorities: [BudgetPeriodType: Int] = [
            .monthly: 0, .weekly: 1, .biweekly: 2, .quarterly: 3, .yearly: 4, .custom: 5
        ]
        let left = priorities[lhs.periodType] ?? 99
        let right = priorities[rhs.periodType] ?? 99
        if left != right { return left < right }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func categoryScopesOverlap(_ budgets: [PlanBudgetSnapshot]) -> Bool {
        for leftIndex in budgets.indices {
            for rightIndex in budgets.indices where rightIndex > leftIndex {
                if !budgets[leftIndex].categoryIDs.isDisjoint(with: budgets[rightIndex].categoryIDs) {
                    return true
                }
            }
        }
        return false
    }

    private static func sumExpenses(
        transactions: [PlanTransactionSnapshot],
        range: PlanDateRange,
        categoryIDs: Set<UUID>?,
        targetCurrency: String,
        rates: [String: Double]
    ) -> (total: Decimal, isDeterminate: Bool) {
        var total: Decimal = 0
        var isDeterminate = true
        for transaction in transactions where BudgetTransactionRelevance.isReportExpense(transaction, in: range) {
            if let categoryIDs {
                guard let categoryID = transaction.categoryID, categoryIDs.contains(categoryID) else { continue }
            }
            if let converted = CurrencyManager.convertOrNil(
                amount: transaction.amount,
                from: transaction.currencyCode,
                to: targetCurrency,
                rates: rates
            ) {
                total += converted
            } else {
                isDeterminate = false
            }
        }
        return (total, isDeterminate)
    }
}
