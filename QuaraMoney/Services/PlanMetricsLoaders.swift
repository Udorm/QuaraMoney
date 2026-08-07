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
        let legacyCalculation = PlanOverviewMetrics.compute(
            budgets: budgets,
            budgetTransactions: records.map(\.snapshot),
            goals: [],
            ledgerRows: [],
            preferredCurrency: preferredCurrency,
            rates: rates,
            now: now,
            calendar: calendar
        )
        return PlanOverviewMetrics(
            budgets: legacyCalculation.budgets,
            savings: try loadSavingsWalletOverview(
                context: context,
                preferredCurrency: preferredCurrency,
                rates: rates
            )
        )
    }

    private static func loadSavingsWalletOverview(
        context: ModelContext,
        preferredCurrency: String,
        rates: [String: Double]
    ) throws -> PlanSavingsOverviewMetrics {
        let wallets = try context.fetch(FetchDescriptor<Wallet>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))
        let savings = wallets.filter { $0.isSavings && !$0.isArchived }
        let adopted = Set(savings.compactMap(\.legacySavingsGoalID))
        let pending = try context.fetch(FetchDescriptor<SavingsGoal>(
            predicate: #Predicate { $0.deletedAt == nil }
        )).filter { !adopted.contains($0.id) }.count
        guard !savings.isEmpty || pending > 0 else {
            return PlanSavingsOverviewMetrics(
                mode: .empty, saved: 0, target: nil, currencyCode: preferredCurrency,
                progress: nil, activeCount: 0, completedCount: 0,
                unknownCount: 0, isDeterminate: true
            )
        }

        let completed = savings.filter(\.isSavingsReached)
        let active = savings.filter { !$0.isSavingsReached }
        let included = active.isEmpty ? completed : active
        var saved: Decimal = 0
        var target: Decimal = 0
        var unknown = pending
        for wallet in included {
            guard let convertedSaved = CurrencyManager.convertOrNil(
                amount: wallet.balance,
                from: wallet.currencyCode,
                to: preferredCurrency,
                rates: rates
            ) else {
                unknown += 1
                continue
            }
            saved += convertedSaved
            if !active.isEmpty, let targetAmount = wallet.targetAmount,
               let convertedTarget = CurrencyManager.convertOrNil(
                   amount: targetAmount,
                   from: wallet.currencyCode,
                   to: preferredCurrency,
                   rates: rates
               ) {
                target += convertedTarget
            } else if !active.isEmpty {
                unknown += 1
            }
        }

        let mode: PlanSavingsOverviewMode = active.isEmpty && pending == 0 ? .allCompleted : .active
        return PlanSavingsOverviewMetrics(
            mode: mode, saved: saved, target: mode == .active ? target : nil,
            currencyCode: preferredCurrency,
            progress: mode == .active && target > 0 ? min(1, max(0, saved / target)) : nil,
            activeCount: active.count, completedCount: completed.count,
            unknownCount: unknown, isDeterminate: unknown == 0
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
                let leftAmount = CurrencyManager.convertOrNil(
                    amount: $0.snapshot.amount,
                    from: $0.snapshot.currencyCode,
                    to: budget.currencyCode,
                    rates: rates
                )
                let rightAmount = CurrencyManager.convertOrNil(
                    amount: $1.snapshot.amount,
                    from: $1.snapshot.currencyCode,
                    to: budget.currencyCode,
                    rates: rates
                )
                if let leftAmount, let rightAmount, leftAmount != rightAmount {
                    return leftAmount > rightAmount
                }
                if leftAmount != nil, rightAmount == nil { return true }
                if leftAmount == nil, rightAmount != nil { return false }
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

    // MARK: Snapshot building

    static func fetchBudgetSnapshots(context: ModelContext) throws -> [PlanBudgetSnapshot] {
        let descriptor = FetchDescriptor<Budget>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor).map { budget in
            let models = budget.effectiveTrackedCategories
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
