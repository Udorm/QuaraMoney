import SwiftUI
import SwiftData

struct BudgetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Budget.startDate, order: .reverse)]) private var budgets: [Budget]
    @Query private var transactions: [Transaction]
    @State private var showAddBudget = false
    @State private var filterPeriod: BudgetFilterPeriod = .active
    @State private var showRecurringOnly = false
    
    private var preferredCurrency: String {
        CurrencyManager.shared.preferredCurrencyCode
    }
    
    private var filteredBudgets: [Budget] {
        var result = budgets
        
        // Filter by period
        switch filterPeriod {
        case .active:
            result = result.filter { $0.isActive }
        case .upcoming:
            result = result.filter { $0.startDate > Date() }
        case .past:
            result = result.filter { $0.isPeriodEnded }
        case .all:
            break
        }
        
        // Filter by recurring
        if showRecurringOnly {
            result = result.filter { $0.isRecurring }
        }
        
        return result
    }
    
    var body: some View {
        Group {
            if budgets.isEmpty {
                ContentUnavailableView(
                    "No Budgets",
                    systemImage: "chart.bar",
                    description: Text("Set up a budget to track your spending habits.")
                )
            } else {
                List {
                    // Summary section for active budgets
                    if filterPeriod == .active || filterPeriod == .all {
                        BudgetSummarySection(
                            budgets: filteredBudgets.filter { $0.isActive },
                            transactions: transactions
                        )
                    }
                    
                    // Budget list
                    ForEach(filteredBudgets) { budget in
                        NavigationLink(destination: BudgetDetailView(budget: budget, transactions: transactions)) {
                            BudgetRowView(
                                budget: budget,
                                spent: calculateSpending(for: budget),
                                budgetLimitConverted: convertBudgetLimit(for: budget)
                            )
                        }
                    }
                    .onDelete(perform: deleteBudgets)
                }
            }
        }
        .navigationTitle("Budgets")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Period", selection: $filterPeriod) {
                        ForEach(BudgetFilterPeriod.allCases) { period in
                            Label(period.displayName, systemImage: period.icon)
                                .tag(period)
                        }
                    }
                    
                    Divider()
                    
                    Toggle("Recurring Only", isOn: $showRecurringOnly)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .symbolVariant(filterPeriod != .active || showRecurringOnly ? .fill : .none)
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddBudget = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddBudget) {
            AddBudgetView()
        }
    }
    
    /// Calculate spending for a budget by filtering transactions and converting to preferred currency
    private func calculateSpending(for budget: Budget) -> Decimal {
        let calendar = Calendar.current
        let periodRange = budget.periodDateRange
        
        // Filter transactions within the budget period
        let relevantTransactions = transactions.filter { txn in
            guard txn.type == .expense,
                  txn.date >= periodRange.start && txn.date < periodRange.end else {
                return false
            }
            
            // Check if transaction matches budget target
            if budget.isTotalBudget {
                // Total budget: include all expenses
                return true
            } else if let categoryId = budget.category?.id {
                // Single category budget
                return txn.category?.id == categoryId
            } else if let group = budget.categoryGroup {
                // Category group budget
                return group.categoryIds.contains(txn.category?.id ?? UUID())
            }
            
            return false
        }
        
        // Convert each transaction to preferred currency and sum
        return relevantTransactions.reduce(Decimal.zero) { total, txn in
            let converted = CurrencyManager.shared.convert(
                amount: txn.amount,
                from: txn.currencyCode,
                to: preferredCurrency
            )
            return total + converted
        }
    }
    
    /// Convert budget limit to preferred currency
    private func convertBudgetLimit(for budget: Budget) -> Decimal {
        return CurrencyManager.shared.convert(
            amount: budget.effectiveLimit,
            from: budget.currencyCode,
            to: preferredCurrency
        )
    }
    
    private func deleteBudgets(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let budgetToDelete = filteredBudgets[index]
                if let actualIndex = budgets.firstIndex(where: { $0.id == budgetToDelete.id }) {
                    modelContext.delete(budgets[actualIndex])
                }
            }
        }
    }
}

// MARK: - Budget Filter Period

enum BudgetFilterPeriod: String, CaseIterable, Identifiable {
    case active
    case upcoming
    case past
    case all
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .active: return "Active"
        case .upcoming: return "Upcoming"
        case .past: return "Past"
        case .all: return "All Budgets"
        }
    }
    
    var icon: String {
        switch self {
        case .active: return "clock.fill"
        case .upcoming: return "calendar.badge.clock"
        case .past: return "clock.arrow.circlepath"
        case .all: return "list.bullet"
        }
    }
}

// MARK: - Budget Summary Section

struct BudgetSummarySection: View {
    let budgets: [Budget]
    let transactions: [Transaction]
    
    private var preferredCurrency: String {
        CurrencyManager.shared.preferredCurrencyCode
    }
    
    private var totalBudgeted: Decimal {
        budgets.reduce(Decimal.zero) { total, budget in
            total + CurrencyManager.shared.convert(
                amount: budget.effectiveLimit,
                from: budget.currencyCode,
                to: preferredCurrency
            )
        }
    }
    
    private var onTrackCount: Int {
        budgets.filter { budget in
            let spent = calculateSpending(for: budget)
            let limit = CurrencyManager.shared.convert(
                amount: budget.effectiveLimit,
                from: budget.currencyCode,
                to: preferredCurrency
            )
            let progress = limit > 0 ? Double(truncating: spent as NSNumber) / Double(truncating: limit as NSNumber) : 0
            return progress <= 0.8
        }.count
    }
    
    var body: some View {
        Section {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Budgeted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(totalBudgeted.formatted(.currency(code: preferredCurrency)))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("On Track")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("\(onTrackCount)/\(budgets.count)")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Image(systemName: onTrackCount == budgets.count ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(onTrackCount == budgets.count ? ThemeManager.shared.incomeColor : .orange)
                    }
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Summary")
        }
    }
    
    private func calculateSpending(for budget: Budget) -> Decimal {
        let periodRange = budget.periodDateRange
        
        let relevantTransactions = transactions.filter { txn in
            guard txn.type == .expense,
                  txn.date >= periodRange.start && txn.date < periodRange.end else {
                return false
            }
            
            if budget.isTotalBudget {
                return true
            } else if let categoryId = budget.category?.id {
                return txn.category?.id == categoryId
            } else if let group = budget.categoryGroup {
                return group.categoryIds.contains(txn.category?.id ?? UUID())
            }
            
            return false
        }
        
        return relevantTransactions.reduce(Decimal.zero) { total, txn in
            CurrencyManager.shared.convert(
                amount: txn.amount,
                from: txn.currencyCode,
                to: preferredCurrency
            ) + total
        }
    }
}

// MARK: - Budget Row View with Progress

struct BudgetRowView: View {
    let budget: Budget
    let spent: Decimal
    let budgetLimitConverted: Decimal
    
    private var preferredCurrency: String {
        CurrencyManager.shared.preferredCurrencyCode
    }
    
    private var progress: Double {
        guard budgetLimitConverted > 0 else { return 0 }
        return Double(truncating: spent as NSNumber) / Double(truncating: budgetLimitConverted as NSNumber)
    }
    
    private var isOverBudget: Bool {
        spent > budgetLimitConverted
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
        VStack(alignment: .leading, spacing: 8) {
            // Top row: Icon, Name, Badges, Amount
            HStack {
                Image(systemName: budgetIcon)
                    .foregroundStyle(progressColor)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(budget.displayName)
                            .font(.headline)
                        
                        // Badges
                        if budget.isRecurring {
                            Image(systemName: "repeat")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        
                        if budget.isTotalBudget {
                            Text("TOTAL")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundStyle(.blue)
                                .cornerRadius(4)
                        }
                        
                        if budget.isGroupBudget {
                            Text("GROUP")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.2))
                                .foregroundStyle(.purple)
                                .cornerRadius(4)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Text(budget.periodDisplayString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if budget.isActive {
                            Text("\(budget.daysRemaining) days left")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if budget.isPeriodEnded {
                            Text("Ended")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(spent.formatted(.currency(code: preferredCurrency))) / \(budgetLimitConverted.formatted(.currency(code: preferredCurrency)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Text("\(Int(min(progress, 1.0) * 100))%")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(progressColor)
                        
                        if budget.rolloverAmount > 0 {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    // Progress fill
                    Capsule()
                        .fill(progressColor.gradient)
                        .frame(width: min(geometry.size.width * CGFloat(min(progress, 1.0)), geometry.size.width), height: 8)
                }
            }
            .frame(height: 8)
            
            // Rollover indicator
            if budget.rolloverAmount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("Includes \(budget.rolloverAmount.formatted(.currency(code: preferredCurrency))) rollover")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        BudgetListView()
            .modelContainer(for: [Budget.self, Transaction.self, Category.self, CategoryGroup.self], inMemory: true)
    }
}
