import SwiftUI
import SwiftData
import Charts

struct BudgetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let budget: Budget
    let transactions: [Transaction]
    
    @State private var showEditBudget = false
    @State private var transactionToEdit: Transaction?
    
    private var preferredCurrency: String {
        CurrencyManager.shared.preferredCurrencyCode
    }
    
    /// Transactions relevant to this budget (filtered by category, period, expense type)
    private var relevantTransactions: [Transaction] {
        let periodRange = budget.periodDateRange
        
        return transactions.filter { txn in
            guard txn.type == .expense,
                  txn.date >= periodRange.start && txn.date < periodRange.end else {
                return false
            }
            
            // Check if transaction matches budget target
            if budget.isTotalBudget {
                return true
            } else if let categoryId = budget.category?.id {
                return txn.category?.id == categoryId
            } else if let group = budget.categoryGroup {
                return group.categoryIds.contains(txn.category?.id ?? UUID())
            }
            
            return false
        }.sorted { $0.date > $1.date }
    }
    
    /// Total spending converted to preferred currency
    private var totalSpent: Decimal {
        relevantTransactions.reduce(Decimal.zero) { total, txn in
            let converted = CurrencyManager.shared.convert(
                amount: txn.amount,
                from: txn.currencyCode,
                to: preferredCurrency
            )
            return total + converted
        }
    }
    
    /// Budget limit converted to preferred currency
    private var budgetLimitConverted: Decimal {
        CurrencyManager.shared.convert(
            amount: budget.effectiveLimit,
            from: budget.currencyCode,
            to: preferredCurrency
        )
    }
    
    /// Remaining amount
    private var remaining: Decimal {
        budgetLimitConverted - totalSpent
    }
    
    /// Progress ratio (0.0 to 1.0+)
    private var progress: Double {
        guard budgetLimitConverted > 0 else { return 0 }
        return Double(truncating: totalSpent as NSNumber) / Double(truncating: budgetLimitConverted as NSNumber)
    }
    
    private var isOverBudget: Bool {
        totalSpent > budgetLimitConverted
    }
    
    private var progressColor: Color {
        if isOverBudget {
            return ThemeManager.shared.expenseColor
        } else if progress > 0.8 {
            return .orange
        } else {
            return ThemeManager.shared.incomeColor
        }
    }
    
    /// Daily spending average
    private var dailyAverage: Decimal {
        let daysElapsed = budget.totalDays - budget.daysRemaining
        guard daysElapsed > 0 else { return 0 }
        return totalSpent / Decimal(daysElapsed)
    }
    
    /// Projected spending at current rate
    private var projectedSpending: Decimal {
        dailyAverage * Decimal(budget.totalDays)
    }
    
    /// Daily budget to stay on track
    private var dailyBudget: Decimal {
        guard budget.daysRemaining > 0 else { return 0 }
        return max(remaining, 0) / Decimal(budget.daysRemaining)
    }
    
    private var budgetIcon: String {
        if let category = budget.category {
            return category.icon
        } else if let group = budget.categoryGroup {
            return group.iconName
        } else {
            return "sum"
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
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                // Badges
                                if budget.isRecurring {
                                    Image(systemName: "repeat.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            
                            Text(budget.periodDisplayString)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            if budget.isActive {
                                Text("\(budget.daysRemaining) days remaining")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: budgetIcon)
                            .font(.title2)
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
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(isOverBudget ? ThemeManager.shared.expenseColor : .primary)
                            
                            Text(isOverBudget ? "Over Budget" : "Used")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
            
            // MARK: - Summary Section
            Section("Summary") {
                HStack {
                    Text("Budget Limit")
                    Spacer()
                    Text(budgetLimitConverted.formatted(.currency(code: preferredCurrency)))
                        .foregroundStyle(.secondary)
                }
                
                if budget.rolloverAmount > 0 {
                    HStack {
                        Label("Rollover", systemImage: "arrow.up.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Text("+\(budget.rolloverAmount.formatted(.currency(code: preferredCurrency)))")
                            .foregroundStyle(.green)
                    }
                }
                
                HStack {
                    Text("Spent")
                    Spacer()
                    Text(totalSpent.formatted(.currency(code: preferredCurrency)))
                        .foregroundStyle(isOverBudget ? ThemeManager.shared.expenseColor : .primary)
                }
                
                HStack {
                    Text("Remaining")
                    Spacer()
                    Text(remaining.formatted(.currency(code: preferredCurrency)))
                        .foregroundStyle(remaining >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor)
                        .fontWeight(.medium)
                }
                
                if budget.currencyCode != preferredCurrency {
                    HStack {
                        Text("Original Budget")
                        Spacer()
                        Text(budget.amountLimit.formatted(.currency(code: budget.currencyCode)))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            
            // MARK: - Insights Section
            if budget.isActive {
                Section("Insights") {
                    // Daily Average
                    HStack {
                        Label("Daily Average", systemImage: "chart.bar.fill")
                        Spacer()
                        Text(dailyAverage.formatted(.currency(code: preferredCurrency)))
                            .foregroundStyle(.secondary)
                    }
                    
                    // Daily Budget to Stay on Track
                    HStack {
                        Label("Daily Budget", systemImage: "target")
                        Spacer()
                        Text(dailyBudget.formatted(.currency(code: preferredCurrency)))
                            .foregroundStyle(dailyBudget > 0 ? ThemeManager.shared.incomeColor : .secondary)
                    }
                    
                    // Projected Spending
                    HStack {
                        Label("Projected Total", systemImage: "chart.line.uptrend.xyaxis")
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(projectedSpending.formatted(.currency(code: preferredCurrency)))
                                .foregroundStyle(projectedSpending > budgetLimitConverted ? ThemeManager.shared.expenseColor : .secondary)
                            if projectedSpending > budgetLimitConverted {
                                Text("Over by \((projectedSpending - budgetLimitConverted).formatted(.currency(code: preferredCurrency)))")
                                    .font(.caption2)
                                    .foregroundStyle(ThemeManager.shared.expenseColor)
                            }
                        }
                    }
                }
            }
            
            // MARK: - Linked Savings Goal
            if let goal = budget.savingsGoal {
                Section {
                    NavigationLink {
                        SavingsGoalDetailView(goal: goal)
                    } label: {
                        HStack {
                            Image(systemName: goal.iconName)
                                .foregroundStyle(Color(hex: goal.colorHex) ?? .blue)
                                .frame(width: 30)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(goal.name)
                                    .font(.headline)
                                
                                ProgressView(value: goal.progress)
                                    .tint(Color(hex: goal.colorHex) ?? .blue)
                                
                                Text("\(goal.progressPercent) of \(goal.targetAmount.formatted(.currency(code: goal.currencyCode)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if goal.isCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Linked Savings Goal")
                }
            }
            
            // MARK: - Alert Settings
            Section {
                HStack {
                    Text("Alerts")
                    Spacer()
                    HStack(spacing: 8) {
                        if budget.alertAt50 {
                            Text("50%")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundStyle(.blue)
                                .cornerRadius(4)
                        }
                        if budget.alertAt80 {
                            Text("80%")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .cornerRadius(4)
                        }
                        if budget.alertAt100 {
                            Text("100%")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.2))
                                .foregroundStyle(.red)
                                .cornerRadius(4)
                        }
                        if !budget.alertAt50 && !budget.alertAt80 && !budget.alertAt100 {
                            Text("None")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if budget.isRecurring {
                    HStack {
                        Text("Recurring")
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "repeat")
                                .foregroundStyle(.blue)
                            Text(budget.periodType.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Rollover")
                        Spacer()
                        Text(budget.rolloverExcess ? "Enabled" : "Disabled")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Settings")
            }
            
            // MARK: - Transactions Section
            if relevantTransactions.isEmpty {
                Section("Transactions (0)") {
                    Text("No transactions yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            } else {
                TransactionListView(
                    transactions: relevantTransactions,
                    onEdit: { txn in
                        transactionToEdit = txn
                    },
                    onDelete: { txn in
                        deleteTransaction(txn)
                    }
                )
            }
        }
        .navigationTitle("Budget Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditBudget = true
                } label: {
                    Text("Edit")
                }
            }
        }
        .sheet(isPresented: $showEditBudget) {
            EditBudgetView(budget: budget)
        }
        .sheet(item: $transactionToEdit) { txn in
            AddTransactionView(
                viewModel: AddTransactionViewModel(
                    dataService: SwiftDataService(modelContext: modelContext),
                    transaction: txn
                ),
                isNewTransaction: false
            )
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
    .modelContainer(for: [Budget.self, Transaction.self, Category.self, SavingsGoal.self], inMemory: true)
}
