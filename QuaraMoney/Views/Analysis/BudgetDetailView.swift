import SwiftUI
import SwiftData
import Charts

struct BudgetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let budget: Budget
    let transactions: [Transaction]
    
    @State private var showEditBudget = false
    @State private var transactionToEdit: Transaction?
    
    // MARK: - ViewModel (owns all budget calculations)
    
    private var vm: BudgetDetailViewModel {
        BudgetDetailViewModel(budget: budget, transactions: transactions)
    }
    
    // MARK: - View-only helpers
    
    private var preferredCurrency: String { vm.preferredCurrency }
    private var relevantTransactions: [Transaction] { vm.relevantTransactions }
    private var totalSpent: Decimal { vm.totalSpent }
    private var budgetLimitConverted: Decimal { vm.budgetLimitConverted }
    private var remaining: Decimal { vm.remaining }
    private var progress: Double { vm.progress }
    private var isOverBudget: Bool { vm.isOverBudget }
    private var dailyAverage: Decimal { vm.dailyAverage }
    private var projectedSpending: Decimal { vm.projectedSpending }
    private var dailyBudget: Decimal { vm.dailyBudget }
    private var budgetIcon: String { vm.budgetIcon }
    
    private var progressColor: Color {
        if isOverBudget {
            return ThemeManager.shared.expenseColor
        } else if progress > 0.8 {
            return .orange
        } else {
            return ThemeManager.shared.incomeColor
        }
    }
    
    var body: some View {
        List {
            // MARK: - Header Section with Donut Chart
            Section {
                VStack(spacing: 24) {
                    // Header Info
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(budget.displayName)
                                    .font(.app(.title2, weight: .bold))
                                
                                // Badges
                                if budget.isRecurring {
                                    Image(systemName: "repeat.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            
                            Text(budget.periodDisplayString)
                                .font(.app(.subheadline))
                                .foregroundStyle(.secondary)
                            
                            if budget.isActive {
                                Text(L10n.Budget.daysLeft(budget.daysRemaining))
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: budgetIcon)
                            .font(.app(.title2))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(progressColor.gradient)
                            .clipShape(Circle())
                            .shadow(color: progressColor.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .padding(.horizontal, 4)
                    
                    // Donut Chart
                    ZStack {
                        Chart {
                            if isOverBudget {
                                SectorMark(
                                    angle: .value("Spent", 100),
                                    innerRadius: .ratio(0.65),
                                    angularInset: 2
                                )
                                .foregroundStyle(ThemeManager.shared.expenseColor.gradient)
                            } else {
                                SectorMark(
                                    angle: .value("Spent", totalSpent),
                                    innerRadius: .ratio(0.65),
                                    angularInset: 2
                                )
                                .foregroundStyle(progressColor.gradient)
                                .cornerRadius(4)
                                
                                SectorMark(
                                    angle: .value("Remaining", max(0, remaining)),
                                    innerRadius: .ratio(0.65),
                                    angularInset: 2
                                )
                                .foregroundStyle(Color(.systemGray5))
                                .cornerRadius(4)
                            }
                        }
                        .frame(height: 220)
                        
                        // Center Label
                        VStack(spacing: 4) {
                            Text("\(Int(progress * 100))%")
                                .font(.app(.largeTitle, weight: .bold))
                                .foregroundStyle(isOverBudget ? ThemeManager.shared.expenseColor : .primary)
                            
                            Text(isOverBudget ? L10n.Budget.overBudgetLabel : L10n.Budget.used)
                                .font(.app(.subheadline, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Budget \(Int(progress * 100)) percent \(isOverBudget ? "over budget" : "used")")
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
            
            // MARK: - Summary Section
            Section(L10n.Budget.summary) {
                HStack {
                    Text(L10n.Budget.limit)
                    Spacer()
                    Text(budgetLimitConverted.formattedAmount(for: preferredCurrency))
                        .foregroundStyle(.secondary)
                }
                
                if budget.rolloverAmount > 0 {
                    HStack {
                        Label(L10n.Budget.rolloverTitle, systemImage: "arrow.up.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Text("+\(budget.rolloverAmount.formattedAmount(for: preferredCurrency))")
                            .foregroundStyle(.green)
                    }
                }
                
                HStack {
                    Text(L10n.Budget.totalSpent)
                    Spacer()
                    Text(totalSpent.formattedAmount(for: preferredCurrency))
                        .foregroundStyle(isOverBudget ? ThemeManager.shared.expenseColor : .primary)
                }
                
                HStack {
                    Text(L10n.Budget.remaining)
                    Spacer()
                    Text(remaining.formattedAmount(for: preferredCurrency))
                        .font(.app(.body, weight: .medium))
                        .foregroundStyle(remaining >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor)
                }
                
                if budget.currencyCode != preferredCurrency {
                    HStack {
                        Text(L10n.Budget.original)
                        Spacer()
                        Text(budget.amountLimit.formattedAmount(for: budget.currencyCode))
                            .foregroundStyle(.secondary)
                            .font(.app(.caption))
                    }
                }
            }
            
            // MARK: - Insights Section
            if budget.isActive {
                Section(L10n.Budget.insights) {
                    // Daily Average
                    HStack {
                        Label(L10n.Budget.dailyAverage, systemImage: "chart.bar.fill")
                        Spacer()
                        Text(dailyAverage.formattedAmount(for: preferredCurrency))
                            .foregroundStyle(.secondary)
                    }
                    
                    // Daily Budget to Stay on Track
                    HStack {
                        Label(L10n.Budget.dailyBudget, systemImage: "target")
                        Spacer()
                        Text(dailyBudget.formattedAmount(for: preferredCurrency))
                            .foregroundStyle(dailyBudget > 0 ? ThemeManager.shared.incomeColor : .secondary)
                    }
                    
                    // Projected Spending
                    HStack {
                        Label(L10n.Budget.projectedTotal, systemImage: "chart.line.uptrend.xyaxis")
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(projectedSpending.formattedAmount(for: preferredCurrency))
                                .foregroundStyle(projectedSpending > budgetLimitConverted ? ThemeManager.shared.expenseColor : .secondary)
                            if projectedSpending > budgetLimitConverted {
                                Text(L10n.Budget.overBy((projectedSpending - budgetLimitConverted).formattedAmount(for: preferredCurrency)))
                                    .font(.app(.caption2))
                                    .foregroundStyle(ThemeManager.shared.expenseColor)
                            }
                        }
                    }
                }
            }
            
            // MARK: - Alert Settings
            Section {
                HStack {
                    Text(L10n.Budget.alerts)
                    Spacer()
                    HStack(spacing: 8) {
                        if budget.alertAt50 {
                            Text("50%")
                                .font(.app(.caption))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.2))
                                .foregroundStyle(Color.accentColor)
                                .cornerRadius(4)
                        }
                        if budget.alertAt80 {
                            Text("80%")
                                .font(.app(.caption))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .cornerRadius(4)
                        }
                        if budget.alertAt100 {
                            Text("100%")
                                .font(.app(.caption))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.2))
                                .foregroundStyle(.red)
                                .cornerRadius(4)
                        }
                        if !budget.alertAt50 && !budget.alertAt80 && !budget.alertAt100 {
                            Text("budget.threshold.none".localized)
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if budget.isRecurring {
                    HStack {
                        Text(L10n.Budget.recurring)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "repeat")
                                .foregroundStyle(Color.accentColor)
                            Text(budget.periodType.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    HStack {
                        Text(L10n.Budget.rolloverTitle)
                        Spacer()
                        Text(budget.rolloverExcess ? L10n.Budget.enabled : L10n.Budget.disabled)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L10n.Settings.title)
            }
            
            // MARK: - Transactions Section
            Section(L10n.Budget.transactions(relevantTransactions.count)) {
                if relevantTransactions.isEmpty {
                    Text(L10n.Budget.noTransactions)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    let periodRange = budget.periodDateRange
                    let budgetCategoryIds = budget.trackedCategoryIds
                    let catInfos = budget.trackedCategoryInfos
                    NavigationLink {
                        FilteredTransactionsDetailView(
                            config: TransactionFilterConfig(
                                title: budget.displayName,
                                startDate: periodRange.start,
                                endDate: periodRange.end,
                                transactionType: .expense,
                                dateRangeDescription: budget.periodDisplayString,
                                categoryIds: budgetCategoryIds.isEmpty ? nil : budgetCategoryIds,
                                categoryInfos: catInfos.isEmpty ? nil : catInfos
                            )
                        )
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(relevantTransactions.count) " + "filteredTransactions.transactionsLabel".localized)
                                    .font(.app(.subheadline, weight: .medium))
                                Text(totalSpent.formattedAmount(for: preferredCurrency))
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.Budget.details)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showEditBudget = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit budget")
            }
        }
        .sheet(isPresented: $showEditBudget) {
            EditBudgetView(budget: budget)
        }
        .sheet(item: $transactionToEdit) { txn in
            AddTransactionContainer(transaction: txn, isNewTransaction: false)
        }
    }
    
    private func deleteTransaction(_ transaction: Transaction) {
        withAnimation {
            modelContext.delete(transaction)
        }
    }
}

#Preview {
    @Previewable @State var budget = Budget(amountLimit: 500, currencyCode: "USD", category: nil, month: 2, year: 2026)
    
    NavigationStack {
        BudgetDetailView(budget: budget, transactions: [])
    }
    .modelContainer(for: [Budget.self, Transaction.self, TransactionLocation.self, Category.self], inMemory: true)
}
