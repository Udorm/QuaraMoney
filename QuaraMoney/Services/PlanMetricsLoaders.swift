import Foundation
import SwiftData
import Observation

// MARK: - Loader results

nonisolated struct PlanBudgetListItemState: Sendable, Equatable, Identifiable {
    var id: UUID { budgetID }
    let budgetID: UUID
    let range: PlanDateRange
    let projection: BudgetSpendingProjection
    let isUpcoming: Bool
    let isEnded: Bool
    let needsAttention: Bool
    let isDuplicateTotal: Bool
}

nonisolated struct PlanBudgetDetailState: Sendable, Equatable {
    let budgetID: UUID
    let range: PlanDateRange
    let projection: BudgetSpendingProjection
    let trend: BudgetTrendSeries
    let isUpcoming: Bool
    let isEnded: Bool
    let daysUntilStart: Int
    let daysLeftIncludingToday: Int
}

nonisolated struct PlanBudgetDetailLoadResult: Sendable {
    let state: PlanBudgetDetailState
    let recentTransactionIDs: [PersistentIdentifier]
}

nonisolated struct PlanSavingsListItemState: Sendable, Equatable, Identifiable {
    var id: UUID { goalID }
    let goalID: UUID
    let metrics: SavingsGoalMetrics
}

nonisolated struct PlanSavingsLedgerDisplayRow: Sendable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let isWithdrawal: Bool
    let originalAmount: Decimal
    let originalCurrencyCode: String
    let convertedAmount: Decimal?
    let goalCurrencyCode: String
}

nonisolated struct PlanSavingsDetailState: Sendable, Equatable {
    let goalID: UUID
    let metrics: SavingsGoalMetrics
    let progressSeries: SavingsProgressSeries
    let ledgerRows: [PlanSavingsLedgerDisplayRow]
}

// MARK: - Private-context loaders

/// Context-bound half of the Plan metrics layer. Every method creates or is
/// handed a private ModelContext, fetches SwiftData models, and returns plain
/// Sendable screen state. The pure calculations live in `PlanMetrics.swift`.
nonisolated enum PlanMetricsLoader {
    static func loadOverview(
        context: ModelContext,
        preferredCurrency: String,
        rates: [String: Double],
        now: Date,
        calendar: Calendar
    ) throws -> PlanOverviewMetrics {
        let budgets = try fetchBudgetSnapshots(context: context)
        let goals = try fetchGoalSnapshots(context: context)

        let month = BudgetPeriodType.monthly.currentPeriodRange(containing: now, calendar: calendar)
        var ranges = [PlanDateRange(start: month.start, end: month.end)]
        let activeBudgets = BudgetListRangeAssembler.budgets(
            from: budgets,
            segment: .active,
            now: now,
            calendar: calendar
        )
        ranges.append(contentsOf: BudgetListRangeAssembler.ranges(for: activeBudgets, now: now, calendar: calendar))
        let records = try fetchBudgetTransactions(
            context: context,
            ranges: BudgetListRangeAssembler.merge(ranges)
        )
        let ledgerRows = try fetchSavingsLedgerRows(
            context: context,
            goalIDs: Set(goals.map(\.id))
        )

        return PlanOverviewMetrics.compute(
            budgets: budgets,
            budgetTransactions: records.map(\.snapshot),
            goals: goals,
            ledgerRows: ledgerRows,
            preferredCurrency: preferredCurrency,
            rates: rates,
            now: now,
            calendar: calendar
        )
    }

    static func loadBudgetList(
        context: ModelContext,
        segment: PlanBudgetSegment,
        rates: [String: Double],
        now: Date,
        calendar: Calendar
    ) throws -> [PlanBudgetListItemState] {
        let allBudgets = try fetchBudgetSnapshots(context: context)
        let budgets = BudgetListRangeAssembler.budgets(
            from: allBudgets,
            segment: segment,
            now: now,
            calendar: calendar
        )
        let mergedRanges = BudgetListRangeAssembler.merge(
            BudgetListRangeAssembler.ranges(for: budgets, now: now, calendar: calendar)
        )
        let transactions = try fetchBudgetTransactions(context: context, ranges: mergedRanges).map(\.snapshot)
        let duplicateIDs = PlanBudgetDuplicateDetector.duplicateTotalIDs(in: allBudgets)

        return budgets.map { budget in
            let range = budget.periodRange(containing: now, calendar: calendar)
            return PlanBudgetListItemState(
                budgetID: budget.id,
                range: range,
                projection: BudgetSpendingProjection.compute(
                    budget: budget,
                    transactions: transactions,
                    rates: rates,
                    range: range
                ),
                isUpcoming: now < range.start,
                isEnded: now >= range.end,
                needsAttention: budget.needsAttention,
                isDuplicateTotal: duplicateIDs.contains(budget.id)
            )
        }
        .sorted { lhs, rhs in
            guard let left = budgets.first(where: { $0.id == lhs.budgetID }),
                  let right = budgets.first(where: { $0.id == rhs.budgetID }) else {
                return lhs.budgetID.uuidString < rhs.budgetID.uuidString
            }
            if left.isStanding != right.isStanding { return left.isStanding }
            if lhs.range.start != rhs.range.start { return lhs.range.start < rhs.range.start }
            return PlanBudgetDuplicateDetector.canonicalOrder(left, right)
        }
    }

    static func loadBudgetDetail(
        context: ModelContext,
        budgetID: UUID,
        rates: [String: Double],
        now: Date,
        calendar: Calendar
    ) throws -> PlanBudgetDetailLoadResult? {
        guard let budget = try fetchBudgetSnapshots(context: context).first(where: { $0.id == budgetID }) else {
            return nil
        }
        let range = budget.periodRange(containing: now, calendar: calendar)
        let records = try fetchBudgetTransactions(context: context, ranges: [range])
        let snapshots = records.map(\.snapshot)
        let projection = BudgetSpendingProjection.compute(
            budget: budget,
            transactions: snapshots,
            rates: rates,
            range: range
        )
        let trend = BudgetTrendSeries.compute(
            budget: budget,
            transactions: snapshots,
            rates: rates,
            range: range,
            now: now,
            calendar: calendar
        )
        let relevantIDs = Set(projection.relevantTransactionIDs)
        let recentIDs = records
            .filter { relevantIDs.contains($0.snapshot.id) }
            .sorted {
                if $0.snapshot.date != $1.snapshot.date { return $0.snapshot.date > $1.snapshot.date }
                return $0.snapshot.id.uuidString < $1.snapshot.id.uuidString
            }
            .prefix(5)
            .map(\.persistentID)

        let today = calendar.startOfDay(for: now)
        let daysUntilStart = max(0, calendar.dateComponents([.day], from: today, to: range.start).day ?? 0)
        let daysLeft = now < range.start
            ? 0
            : max(0, calendar.dateComponents([.day], from: today, to: range.end).day ?? 0)
        return PlanBudgetDetailLoadResult(
            state: PlanBudgetDetailState(
                budgetID: budgetID,
                range: range,
                projection: projection,
                trend: trend,
                isUpcoming: now < range.start,
                isEnded: now >= range.end,
                daysUntilStart: daysUntilStart,
                daysLeftIncludingToday: daysLeft
            ),
            recentTransactionIDs: recentIDs
        )
    }

    static func loadSavingsList(
        context: ModelContext,
        segment: PlanSavingsSegment,
        rates: [String: Double],
        now: Date,
        calendar: Calendar
    ) throws -> [PlanSavingsListItemState] {
        let goals = try fetchGoalSnapshots(context: context)
        let ledgerRows = try fetchSavingsLedgerRows(context: context, goalIDs: Set(goals.map(\.id)))
        let grouped = Dictionary(grouping: ledgerRows, by: \.goalID)

        return goals.compactMap { goal in
            let ledger = SavingsLedgerCalculator.calculate(
                startingBalance: goal.currentAmount,
                startingCurrencyCode: goal.startingBalanceCurrencyCode,
                goalCurrencyCode: goal.currencyCode,
                rows: grouped[goal.id] ?? [],
                rates: rates
            )
            let metrics = SavingsGoalMetrics.compute(
                goal: goal,
                ledgerResult: ledger,
                now: now,
                calendar: calendar
            )
            let belongs = switch segment {
            case .active: metrics.isCompleted != true
            case .completed: metrics.isCompleted == true
            }
            return belongs ? PlanSavingsListItemState(goalID: goal.id, metrics: metrics) : nil
        }
        .sorted { lhs, rhs in
            guard let left = goals.first(where: { $0.id == lhs.goalID }),
                  let right = goals.first(where: { $0.id == rhs.goalID }) else {
                return lhs.goalID.uuidString < rhs.goalID.uuidString
            }
            if left.priority != right.priority { return left.priority < right.priority }
            if left.createdDate != right.createdDate { return left.createdDate < right.createdDate }
            return left.id.uuidString < right.id.uuidString
        }
    }

    static func loadSavingsDetail(
        context: ModelContext,
        goalID: UUID,
        rates: [String: Double],
        now: Date,
        calendar: Calendar
    ) throws -> PlanSavingsDetailState? {
        guard let goal = try fetchGoalSnapshots(context: context).first(where: { $0.id == goalID }) else {
            return nil
        }
        let rows = try fetchSavingsLedgerRows(context: context, goalIDs: [goalID])
        let ledger = SavingsLedgerCalculator.calculate(
            startingBalance: goal.currentAmount,
            startingCurrencyCode: goal.startingBalanceCurrencyCode,
            goalCurrencyCode: goal.currencyCode,
            rows: rows,
            rates: rates
        )
        let metrics = SavingsGoalMetrics.compute(goal: goal, ledgerResult: ledger, now: now, calendar: calendar)
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let windowStart = calendar.date(byAdding: .month, value: -11, to: currentMonth) ?? currentMonth
        let series = SavingsProgressSeries.compute(
            goal: goal,
            rows: rows,
            windowStart: windowStart,
            now: now,
            calendar: calendar,
            rates: rates
        )
        let displayRows = rows.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }.map { row in
            PlanSavingsLedgerDisplayRow(
                id: row.id,
                date: row.date,
                isWithdrawal: row.isWithdrawal,
                originalAmount: row.amount,
                originalCurrencyCode: row.currencyCode,
                convertedAmount: SavingsLedgerCalculator.convertStrict(
                    row.amount,
                    from: row.currencyCode,
                    to: goal.currencyCode,
                    rates: rates
                ),
                goalCurrencyCode: goal.currencyCode
            )
        }
        return PlanSavingsDetailState(
            goalID: goalID,
            metrics: metrics,
            progressSeries: series,
            ledgerRows: displayRows
        )
    }

    // MARK: Snapshot building

    static func fetchBudgetSnapshots(context: ModelContext) throws -> [PlanBudgetSnapshot] {
        let descriptor = FetchDescriptor<Budget>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor).map { budget in
            let models: [Category]
            if let categories = budget.categories, !categories.isEmpty {
                models = categories.filter { $0.deletedAt == nil }
            } else if let category = budget.category, category.deletedAt == nil {
                models = [category]
            } else {
                models = []
            }
            return PlanBudgetSnapshot(
                id: budget.id,
                amountLimit: budget.amountLimit,
                currencyCode: budget.currencyCode,
                targetKind: budget.targetKind,
                periodType: budget.periodType,
                startDate: budget.startDate,
                customEndDate: budget.customEndDate,
                weekStartDay: budget.weekStartDay,
                createdAt: budget.createdAt,
                categories: models.map {
                    PlanCategorySnapshot(id: $0.id, name: $0.name, icon: $0.icon, colorHex: $0.colorHex)
                }
            )
        }
    }

    static func fetchGoalSnapshots(context: ModelContext) throws -> [PlanSavingsGoalSnapshot] {
        let descriptor = FetchDescriptor<SavingsGoal>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.priority), SortDescriptor(\.createdDate)]
        )
        return try context.fetch(descriptor).map { goal in
            PlanSavingsGoalSnapshot(
                id: goal.id,
                targetAmount: goal.targetAmount,
                currencyCode: goal.currencyCode,
                currentAmount: goal.currentAmount,
                startingBalanceCurrencyCode: goal.startingBalanceCurrencyCode ?? goal.currencyCode,
                targetDate: goal.targetDate,
                createdDate: goal.createdDate,
                iconName: goal.iconName,
                colorHex: goal.colorHex,
                priority: goal.priority
            )
        }
    }

    static func fetchSavingsLedgerRows(
        context: ModelContext,
        goalIDs: Set<UUID>
    ) throws -> [SavingsLedgerEntrySnapshot] {
        guard !goalIDs.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.date)]
        )
        return try context.fetch(descriptor).compactMap { transaction in
            guard transaction.type == .transfer,
                  let goalID = transaction.savingsGoal?.id,
                  goalIDs.contains(goalID),
                  let side = TransferSideAmountResolver.ledgerAmount(for: transaction) else {
                return nil
            }
            return SavingsLedgerEntrySnapshot(
                id: transaction.id,
                goalID: goalID,
                date: transaction.date,
                amount: side.amount,
                currencyCode: side.currencyCode,
                isWithdrawal: transaction.savingsIsWithdrawal
            )
        }
    }

    private struct BudgetTransactionRecord {
        let snapshot: PlanTransactionSnapshot
        let persistentID: PersistentIdentifier
    }

    /// Every Plan budget query opts into archived-wallet inclusion explicitly.
    private static func fetchBudgetTransactions(
        context: ModelContext,
        ranges: [PlanDateRange]
    ) throws -> [BudgetTransactionRecord] {
        var records: [UUID: BudgetTransactionRecord] = [:]
        for range in ranges where range.isValid {
            let descriptor = TransactionProcessor.makeDescriptor(
                startDate: range.start,
                endDate: range.end,
                excludeArchivedWallets: false
            )
            for transaction in try context.fetch(descriptor) {
                records[transaction.id] = BudgetTransactionRecord(
                    snapshot: transactionSnapshot(transaction),
                    persistentID: transaction.persistentModelID
                )
            }
        }
        return Array(records.values)
    }

    private static func transactionSnapshot(_ transaction: Transaction) -> PlanTransactionSnapshot {
        let kind: PlanTransactionKind = switch transaction.type {
        case .income: .income
        case .expense: .expense
        case .transfer: .transfer
        case .adjustment: .adjustment
        }
        return PlanTransactionSnapshot(
            id: transaction.id,
            date: transaction.date,
            kind: kind,
            amount: transaction.amount,
            currencyCode: transaction.currencyCode,
            categoryID: transaction.category?.id,
            isDeleted: transaction.deletedAt != nil,
            isEventLinked: transaction.event != nil,
            isExcludedFromReports: transaction.excludeFromReports,
            sourceWalletIsArchived: transaction.sourceWallet?.isArchived == true
        )
    }
}

// MARK: - Generation-checked screen stores

@MainActor
@Observable
final class PlanOverviewStore {
    private(set) var metrics: PlanOverviewMetrics?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    func configure(modelContext: ModelContext) { container = modelContext.container }

    func refresh(now: Date = Date(), calendar: Calendar = .current) {
        guard let container else { return }
        let rates = CurrencyManager.shared.rates
        let preferred = CurrencyManager.shared.preferredCurrencyCode
        generation += 1
        let requestGeneration = generation
        task?.cancel()
        isLoading = metrics == nil
        task = Task.detached(priority: .userInitiated) {
            do {
                let context = ModelContext(container)
                let result = try PlanMetricsLoader.loadOverview(
                    context: context,
                    preferredCurrency: preferred,
                    rates: rates,
                    now: now,
                    calendar: calendar
                )
                guard !Task.isCancelled else { return }
                await self.apply(result, generation: requestGeneration)
            } catch {
                await self.apply(error: error, generation: requestGeneration)
            }
        }
    }

    private func apply(_ result: PlanOverviewMetrics, generation requestGeneration: Int) {
        guard requestGeneration == generation else { return }
        metrics = result
        isLoading = false
        errorMessage = nil
    }

    private func apply(error: Error, generation requestGeneration: Int) {
        guard requestGeneration == generation else { return }
        isLoading = false
        errorMessage = error.localizedDescription
    }
}

@MainActor
@Observable
final class PlanBudgetListStore {
    private(set) var items: [PlanBudgetListItemState] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var requestedSegment: PlanBudgetSegment = .active

    func configure(modelContext: ModelContext) { container = modelContext.container }

    func refresh(segment: PlanBudgetSegment, now: Date = Date(), calendar: Calendar = .current) {
        guard let container else { return }
        requestedSegment = segment
        let rates = CurrencyManager.shared.rates
        generation += 1
        let requestGeneration = generation
        isLoading = true
        task?.cancel()
        task = Task.detached(priority: .userInitiated) {
            do {
                let context = ModelContext(container)
                let result = try PlanMetricsLoader.loadBudgetList(
                    context: context,
                    segment: segment,
                    rates: rates,
                    now: now,
                    calendar: calendar
                )
                guard !Task.isCancelled else { return }
                await self.apply(result, segment: segment, generation: requestGeneration)
            } catch {
                await self.apply(error: error, segment: segment, generation: requestGeneration)
            }
        }
    }

    private func apply(_ result: [PlanBudgetListItemState], segment: PlanBudgetSegment, generation requestGeneration: Int) {
        guard requestGeneration == generation, segment == requestedSegment else { return }
        items = result
        isLoading = false
        hasLoaded = true
        errorMessage = nil
    }

    private func apply(error: Error, segment: PlanBudgetSegment, generation requestGeneration: Int) {
        guard requestGeneration == generation, segment == requestedSegment else { return }
        isLoading = false
        hasLoaded = true
        errorMessage = error.localizedDescription
    }
}

@MainActor
@Observable
final class PlanBudgetDetailStore {
    private(set) var state: PlanBudgetDetailState?
    private(set) var recentTransactions: [Transaction] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        container = modelContext.container
    }

    func refresh(budgetID: UUID, now: Date = Date(), calendar: Calendar = .current) {
        guard let container else { return }
        let rates = CurrencyManager.shared.rates
        generation += 1
        let requestGeneration = generation
        isLoading = state == nil
        task?.cancel()
        task = Task.detached(priority: .userInitiated) {
            do {
                let context = ModelContext(container)
                let result = try PlanMetricsLoader.loadBudgetDetail(
                    context: context,
                    budgetID: budgetID,
                    rates: rates,
                    now: now,
                    calendar: calendar
                )
                guard !Task.isCancelled else { return }
                await self.apply(result, generation: requestGeneration)
            } catch {
                await self.apply(error: error, generation: requestGeneration)
            }
        }
    }

    private func apply(_ result: PlanBudgetDetailLoadResult?, generation requestGeneration: Int) {
        guard requestGeneration == generation else { return }
        state = result?.state
        if let modelContext, let result {
            recentTransactions = result.recentTransactionIDs.compactMap {
                modelContext.model(for: $0) as? Transaction
            }
        } else {
            recentTransactions = []
        }
        isLoading = false
        errorMessage = nil
    }

    private func apply(error: Error, generation requestGeneration: Int) {
        guard requestGeneration == generation else { return }
        isLoading = false
        errorMessage = error.localizedDescription
    }
}

@MainActor
@Observable
final class PlanSavingsListStore {
    private(set) var items: [PlanSavingsListItemState] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var requestedSegment: PlanSavingsSegment = .active

    func configure(modelContext: ModelContext) { container = modelContext.container }

    func refresh(segment: PlanSavingsSegment, now: Date = Date(), calendar: Calendar = .current) {
        guard let container else { return }
        requestedSegment = segment
        let rates = CurrencyManager.shared.rates
        generation += 1
        let requestGeneration = generation
        isLoading = true
        task?.cancel()
        task = Task.detached(priority: .userInitiated) {
            do {
                let context = ModelContext(container)
                let result = try PlanMetricsLoader.loadSavingsList(
                    context: context,
                    segment: segment,
                    rates: rates,
                    now: now,
                    calendar: calendar
                )
                guard !Task.isCancelled else { return }
                await self.apply(result, segment: segment, generation: requestGeneration)
            } catch {
                await self.apply(error: error, segment: segment, generation: requestGeneration)
            }
        }
    }

    private func apply(_ result: [PlanSavingsListItemState], segment: PlanSavingsSegment, generation requestGeneration: Int) {
        guard requestGeneration == generation, segment == requestedSegment else { return }
        items = result
        isLoading = false
        hasLoaded = true
        errorMessage = nil
    }

    private func apply(error: Error, segment: PlanSavingsSegment, generation requestGeneration: Int) {
        guard requestGeneration == generation, segment == requestedSegment else { return }
        isLoading = false
        hasLoaded = true
        errorMessage = error.localizedDescription
    }
}

@MainActor
@Observable
final class PlanSavingsDetailStore {
    private(set) var state: PlanSavingsDetailState?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    func configure(modelContext: ModelContext) { container = modelContext.container }

    func refresh(goalID: UUID, now: Date = Date(), calendar: Calendar = .current) {
        guard let container else { return }
        let rates = CurrencyManager.shared.rates
        generation += 1
        let requestGeneration = generation
        isLoading = state == nil
        task?.cancel()
        task = Task.detached(priority: .userInitiated) {
            do {
                let context = ModelContext(container)
                let result = try PlanMetricsLoader.loadSavingsDetail(
                    context: context,
                    goalID: goalID,
                    rates: rates,
                    now: now,
                    calendar: calendar
                )
                guard !Task.isCancelled else { return }
                await self.apply(result, generation: requestGeneration)
            } catch {
                await self.apply(error: error, generation: requestGeneration)
            }
        }
    }

    private func apply(_ result: PlanSavingsDetailState?, generation requestGeneration: Int) {
        guard requestGeneration == generation else { return }
        state = result
        isLoading = false
        errorMessage = nil
    }

    private func apply(error: Error, generation requestGeneration: Int) {
        guard requestGeneration == generation else { return }
        isLoading = false
        errorMessage = error.localizedDescription
    }
}
