import SwiftUI
import SwiftData

/// Compatibility entry point retained for ContentView; the segmented shell is gone.
struct BudgetTabView: View {
    var body: some View { PlanOverviewView() }
}

struct PlanOverviewView: View {
    @Query(filter: #Predicate<Budget> { $0.deletedAt == nil }, sort: \Budget.createdAt)
    private var budgets: [Budget]
    @Query(filter: #Predicate<SavingsGoal> { $0.deletedAt == nil }, sort: \SavingsGoal.priority)
    private var goals: [SavingsGoal]
    @Query(filter: #Predicate<Transaction> { $0.deletedAt == nil }, sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @State private var showAddBudget = false
    @State private var showAddGoal = false
    @State private var budgetSearch = ""
    @State private var savingsSearch = ""
    @State private var showBudgetFilter = false

    private var standingBudgets: [Budget] { budgets.filter { $0.periodType != .custom } }
    private var monthlyTotal: Budget? {
        standingBudgets.filter { $0.periodType == .monthly && $0.targetKind == .total }
            .min { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        let preferredCurrency = CurrencyManager.shared.preferredCurrencyCode
        let ownCurrencySpending = BudgetCalculator.spendingByBudgetCurrency(for: standingBudgets, transactions: transactions)
        let preferredSpending = BudgetCalculator.spendingByBudget(for: standingBudgets, transactions: transactions,
                                                                   targetCurrency: preferredCurrency)
        let preferredLimits = BudgetCalculator.limitsByBudget(for: standingBudgets, transactions: transactions,
                                                               targetCurrency: preferredCurrency)
        let onTrack = standingBudgets.filter {
            let limit = preferredLimits[$0.id] ?? 0
            return limit > 0 && (preferredSpending[$0.id] ?? 0) <= limit
        }.count
        let riskBudget = standingBudgets.filter { (preferredLimits[$0.id] ?? 0) > 0 }.max {
            riskRatio($0, spending: preferredSpending, limits: preferredLimits) <
            riskRatio($1, spending: preferredSpending, limits: preferredLimits)
        }
        let month = monthInsights(preferredCurrency: preferredCurrency)
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    hero(ownCurrencySpending: ownCurrencySpending, onTrack: onTrack,
                         highestRisk: riskBudget, preferredSpending: preferredSpending,
                         preferredLimits: preferredLimits, monthSpending: month.total,
                         preferredCurrency: preferredCurrency)
                    overviewSection(
                        title: "plan.budgets".localized,
                        destination: BudgetListView(searchText: $budgetSearch, isFilterPresented: $showBudgetFilter)
                    ) {
                        ForEach(standingBudgets.prefix(3)) { budget in
                            PlanBudgetSummaryRow(budget: budget, spent: ownCurrencySpending[budget.id] ?? 0, transactions: transactions)
                        }
                    }
                    overviewSection(
                        title: "plan.savings".localized,
                        destination: SavingsGoalListView(searchText: $savingsSearch)
                    ) {
                        ForEach(goals.prefix(3)) { goal in
                            SavingsGoalRowView(goal: goal)
                        }
                    }
                    insightsCard(month: month)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("tab.plan".localized)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("plan.new_budget".localized, systemImage: "chart.pie.fill") { showAddBudget = true }
                        Button("plan.new_goal".localized, systemImage: "target") { showAddGoal = true }
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel("plan.add".localized)
                }
            }
            .sheet(isPresented: $showAddBudget) { AddBudgetView() }
            .sheet(isPresented: $showAddGoal) { AddSavingsGoalView() }
        }
    }

    private func hero(ownCurrencySpending: [UUID: Decimal], onTrack: Int, highestRisk: Budget?,
                      preferredSpending: [UUID: Decimal], preferredLimits: [UUID: Decimal],
                      monthSpending: Decimal, preferredCurrency: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("plan.overview".localized).appFont(size: 15, weight: .semibold).foregroundStyle(.secondary)
            if let budget = monthlyTotal {
                let spent = ownCurrencySpending[budget.id] ?? 0
                Text(max(0, budget.amountLimit - spent).formattedAmount(for: budget.currencyCode))
                    .appFont(size: 32, weight: .bold).monospacedDigit()
                Text("plan.left_this_month".localized).appFont(size: 14, weight: .regular).foregroundStyle(.secondary)
            }
            Text("plan.month_spending".localized(with: monthSpending.formattedAmount(for: preferredCurrency)))
                .appFont(size: 14, weight: .regular).foregroundStyle(.secondary)
            Text("plan.on_track_count".localized(with: onTrack, standingBudgets.count))
                .appFont(size: 17, weight: .semibold)
            if let highestRisk {
                Text("plan.highest_risk".localized(with: highestRisk.displayName,
                    Int(riskRatio(highestRisk, spending: preferredSpending, limits: preferredLimits) * 100)))
                    .appFont(size: 14, weight: .regular).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
    }

    private func overviewSection<Destination: View, Content: View>(
        title: String, destination: Destination, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(destination: destination) {
                HStack { Text(title).appFont(size: 20, weight: .bold); Spacer(); Image(systemName: "chevron.right") }
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
            content()
            if (title == "plan.budgets".localized && standingBudgets.isEmpty) ||
                (title == "plan.savings".localized && goals.isEmpty) {
                AppEmptyStateView("plan.empty_title".localized, systemImage: "target",
                                  description: "plan.empty_message".localized)
            }
        }
    }

    private func insightsCard(month: MonthInsights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("plan.insights".localized, systemImage: "sparkles")
                .appFont(size: 20, weight: .bold)
            Text(month.paceKey.localized).appFont(size: 15, weight: .regular).foregroundStyle(.secondary)
            if let topCategory = month.topCategory {
                Text("plan.top_category".localized(with: topCategory))
                    .appFont(size: 15, weight: .medium)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
    }

    private func riskRatio(_ budget: Budget, spending: [UUID: Decimal], limits: [UUID: Decimal]) -> Double {
        let limit = limits[budget.id] ?? 0
        guard limit > 0 else { return 0 }
        return NSDecimalNumber(decimal: (spending[budget.id] ?? 0) / limit).doubleValue
    }

    private func monthInsights(preferredCurrency: String) -> MonthInsights {
        let calendar = Calendar.current
        let range = BudgetPeriodType.monthly.currentPeriodRange(containing: Date(), calendar: calendar)
        let relevant = transactions.filter { $0.deletedAt == nil && $0.event == nil && !$0.excludeFromReports &&
            $0.type == .expense && $0.date >= range.start && $0.date < range.end }
        let total = TransactionProcessor.calculateTotal(relevant, rates: CurrencyManager.shared.rates,
                                                         targetCurrency: preferredCurrency, typeFilter: .expense)
        var byCategory: [String: Decimal] = [:]
        for transaction in relevant {
            let name = transaction.category?.displayName ?? "category.uncategorized".localized
            byCategory[name, default: 0] += CurrencyManager.shared.convert(amount: transaction.amount,
                from: transaction.currencyCode, to: preferredCurrency)
        }
        let top = byCategory.max { $0.value < $1.value }?.key
        let elapsed = max(1, (calendar.dateComponents([.day], from: range.start, to: Date()).day ?? 0) + 1)
        let totalDays = max(1, calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 1)
        let elapsedFraction = Double(elapsed) / Double(totalDays)
        let budgetProgress: Double
        if let monthlyTotal, monthlyTotal.amountLimit > 0 {
            let spent = BudgetCalculator.calculateSpending(for: monthlyTotal, transactions: transactions,
                                                            targetCurrency: monthlyTotal.currencyCode)
            budgetProgress = NSDecimalNumber(decimal: spent / monthlyTotal.amountLimit).doubleValue
        } else { budgetProgress = elapsedFraction }
        return MonthInsights(total: total, topCategory: top,
                             paceKey: budgetProgress > elapsedFraction ? "plan.over_pace" : "plan.under_pace")
    }
}

private struct MonthInsights { let total: Decimal; let topCategory: String?; let paceKey: String }

private struct PlanBudgetSummaryRow: View {
    let budget: Budget
    let spent: Decimal
    let transactions: [Transaction]
    var body: some View {
        NavigationLink(destination: BudgetDetailView(budget: budget, transactions: transactions)) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(budget.displayName).appFont(size: 17, weight: .semibold)
                    Text(budget.periodType.displayName).appFont(size: 13, weight: .regular).foregroundStyle(.secondary)
                }
                Spacer()
                Text(spent.formattedAmount(for: budget.currencyCode)).appFont(size: 15, weight: .semibold).monospacedDigit()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

#Preview {
    BudgetTabView().modelContainer(for: [Budget.self, SavingsGoal.self, Transaction.self,
        TransactionLocation.self, Category.self, Wallet.self], inMemory: true)
}
