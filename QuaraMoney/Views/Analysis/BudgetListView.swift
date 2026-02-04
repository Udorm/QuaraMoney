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
    
    private var totalSpent: Decimal {
        budgets.reduce(Decimal.zero) { total, budget in
            total + calculateSpending(for: budget)
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
            return progress <= 1.0 // Changed to 1.0 to consider "on track" as not over budget, or strict 0.8? Sticking to logic "over budget" count implies > 1.0 usually, but let's keep original logic loosely or refine. Original was <= 0.8. Let's use <= 1.0 for "On Track" in general sense, or strictly adhering to "Healthy". 
            // Let's stick to "On Track" meaning "Not Over Budget" for the text label "X on track, Y over".
            return progress <= 1.0
        }.count
    }
    
    var body: some View {
        Section {
            VStack(spacing: 16) {
                // Top Row: Spent vs Budgeted
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Spent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(totalSpent.formatted(.currency(code: preferredCurrency)))
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Total Budgeted")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(totalBudgeted.formatted(.currency(code: preferredCurrency)))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Progress Bar
                let progress = totalBudgeted > 0 ? Double(truncating: totalSpent as NSNumber) / Double(truncating: totalBudgeted as NSNumber) : 0
                VStack(spacing: 8) {
                    ProgressView(value: min(progress, 1.0))
                        .tint(progress > 1.0 ? .red : (progress > 0.9 ? .orange : ThemeManager.shared.incomeColor))
                    
                    HStack {
                        Text("\(Int(progress * 100))% of budget used")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("\(onTrackCount) on track, \(budgets.count - onTrackCount) over")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
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
            return .red
        } else if progress > 0.9 {
            return .orange
        } else {
            return ThemeManager.shared.incomeColor
        }
    }
    
    // Remaining amount calculation
    private var remaining: Decimal {
        max(budgetLimitConverted - spent, 0)
    }
    
    private var budgetIcon: String {
        if let category = budget.category {
            return category.icon
        } else if let group = budget.categoryGroup {
            return group.iconName
        } else {
            return "chart.pie.fill"
        }
    }
    
    private var iconColor: Color {
        if let category = budget.category {
            return Color(hex: category.colorHex) ?? .blue
        } else if let group = budget.categoryGroup {
            return Color(hex: group.colorHex) ?? .purple
        } else {
            return .blue
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // MARK: Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: budgetIcon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
            }
            
            // MARK: Content
            VStack(alignment: .leading, spacing: 6) {
                // Title Row
                HStack {
                    Text(budget.displayName)
                        .font(.body) // Fixed syntax
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Primary Value: Remaining or Spent based on preference/context
                    // Here we focus on "Amount Left" as it's usually what users care about
                    if isOverBudget {
                        Text(spent.formatted(.currency(code: preferredCurrency)))
                            .font(.body)
                            .fontWeight(.bold)
                            .foregroundStyle(.red)
                    } else {
                        Text(remaining.formatted(.currency(code: preferredCurrency)))
                            .font(.body)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.primary)
                    }
                }
                
                // Progress Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemGray4).opacity(0.5))
                            .frame(height: 6)
                        
                        Capsule()
                            .fill(progressColor.gradient)
                            .frame(width: min(geometry.size.width * CGFloat(min(progress, 1.0)), geometry.size.width), height: 6)
                    }
                }
                .frame(height: 6)
                
                // Footer / Subtitle Row
                HStack {
                    // Left: Budget Info / Badges
                    HStack(spacing: 4) {
                        if budget.isRecurring {
                            Image(systemName: "repeat")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        if isOverBudget {
                             Text("Over by \((spent - budgetLimitConverted).formatted(.currency(code: preferredCurrency)))")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text("left of \(budgetLimitConverted.formatted(.currency(code: preferredCurrency)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Right: Time Info
                    if budget.isActive {
                        Text("\(budget.daysRemaining) days left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if budget.isPeriodEnded {
                        Text("Ended")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        BudgetListView()
            .modelContainer(for: [Budget.self, Transaction.self, Category.self, CategoryGroup.self], inMemory: true)
    }
}
