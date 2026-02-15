import SwiftUI
import SwiftData

struct BudgetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Budget.startDate, order: .reverse)]) private var budgets: [Budget]
    @Query private var transactions: [Transaction]
    @State private var showAddBudget = false
    @State private var filterPeriod: BudgetFilterPeriod = .active
    @State private var showRecurringOnly = false
    @State private var searchText = ""
    
    private var preferredCurrency: String {
        CurrencyManager.shared.preferredCurrencyCode
    }
    
    private var filteredBudgets: [Budget] {
        var result = budgets
        
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
        
        if showRecurringOnly {
            result = result.filter { $0.isRecurring }
        }
        
        if !searchText.isEmpty {
            result = result.filter { budget in
                if let name = budget.name, name.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                if let category = budget.category, category.name.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                if let categories = budget.categories {
                    if categories.contains(where: { $0.name.localizedCaseInsensitiveContains(searchText) }) {
                        return true
                    }
                }
                return false
            }
        }
        
        return result
    }
    
    var body: some View {
        Group {
            if budgets.isEmpty {
                AppEmptyStateView(
                    L10n.Budget.emptyState,
                    systemImage: "chart.bar",
                    description: L10n.Budget.emptyDescription
                )
            } else {
                List {
                    if filterPeriod == .active || filterPeriod == .all {
                        Section {
                            BudgetSummarySection(
                                budgets: filteredBudgets.filter { $0.isActive },
                                transactions: transactions
                            )
                        }
                    }
                    
                    Section(header: Text(headerTitle).font(.app(.subheadline)).textCase(nil)) {
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
        }
        .navigationTitle(L10n.Budget.title)
        .searchable(text: $searchText)
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showAddBudget = true
                } label: {
                    Image(systemName: "plus")
                }
                
                FilterSheetButton(
                    selectedPeriod: $filterPeriod,
                    selectedWallet: .constant(nil),
                    customStartDate: .constant(Date()),
                    customEndDate: .constant(Date()),
                    wallets: [],
                    defaultPeriod: .active,
                    showWalletFilter: false
                ) {
                    Section {
                        Toggle(L10n.Budget.recurringOnly, isOn: $showRecurringOnly)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddBudget) {
            AddBudgetView()
        }
    }
    
    private var headerTitle: String {
        if showRecurringOnly {
            return "\(filterPeriod.displayName) • \(L10n.Budget.recurringOnly)"
        }
        return filterPeriod.displayName
    }
    
    /// Calculate spending for a budget by filtering transactions and converting to preferred currency
    private func calculateSpending(for budget: Budget) -> Decimal {
        let periodRange = budget.periodDateRange
        
        // Filter transactions within the budget period
        let relevantTransactions = transactions.filter { txn in
            guard !txn.excludeFromReports,
                  txn.type == .expense,
                  txn.date >= periodRange.start && txn.date < periodRange.end else {
                return false
            }
            
            // Check if transaction matches budget target
            if budget.isTotalBudget {
                // Total budget: include all expenses
                return true
            } else if let categories = budget.categories, !categories.isEmpty {
                // Multi-category budget
                return categories.contains { $0.id == txn.category?.id }
            } else if let categoryId = budget.category?.id {
                // Single category budget
                return txn.category?.id == categoryId
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
        let limit: Decimal
        if case .percentOfIncome = budget.amountType {
            let income = calculateIncome(for: budget)
            limit = budget.calculateEffectiveLimit(income: income)
        } else {
            limit = budget.effectiveLimit
        }
        
        return CurrencyManager.shared.convert(
            amount: limit,
            from: budget.currencyCode,
            to: preferredCurrency
        )
    }
    
    /// Calculate total income for the budget period
    private func calculateIncome(for budget: Budget) -> Decimal {
        let periodRange = budget.periodDateRange
        
        let relevantIncome = transactions.filter { txn in
            txn.type == .income &&
            txn.date >= periodRange.start &&
            txn.date < periodRange.end
        }
        
        return relevantIncome.reduce(Decimal.zero) { total, txn in
            let converted = CurrencyManager.shared.convert(
                amount: txn.amount,
                from: txn.currencyCode,
                to: budget.currencyCode
            )
            return total + converted
        }
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

enum BudgetFilterPeriod: String, CaseIterable, Identifiable, LocalizableDisplayName {
    case active
    case upcoming
    case past
    case all
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .active: return L10n.Budget.Filter.active
        case .upcoming: return L10n.Budget.Filter.upcoming
        case .past: return L10n.Budget.Filter.past
        case .all: return L10n.Budget.Filter.all
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
            let limit: Decimal
            if case .percentOfIncome = budget.amountType {
                let income = calculateIncome(for: budget)
                limit = budget.calculateEffectiveLimit(income: income)
            } else {
                limit = budget.effectiveLimit
            }
            
            return total + CurrencyManager.shared.convert(
                amount: limit,
                from: budget.currencyCode,
                to: preferredCurrency
            )
        }
    }
    
    /// Calculate total income for the budget period (Matches logic in BudgetListView)
    private func calculateIncome(for budget: Budget) -> Decimal {
        let periodRange = budget.periodDateRange
        
        let relevantIncome = transactions.filter { txn in
            txn.type == .income &&
            txn.date >= periodRange.start &&
            txn.date < periodRange.end
        }
        
        return relevantIncome.reduce(Decimal.zero) { total, txn in
            let converted = CurrencyManager.shared.convert(
                amount: txn.amount,
                from: txn.currencyCode,
                to: budget.currencyCode
            )
            return total + converted
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
            let limit: Decimal
            if case .percentOfIncome = budget.amountType {
                let income = calculateIncome(for: budget)
                limit = budget.calculateEffectiveLimit(income: income)
            } else {
                limit = budget.effectiveLimit
            }
            
            let limitConverted = CurrencyManager.shared.convert(
                amount: limit,
                from: budget.currencyCode,
                to: preferredCurrency
            )
            let progress = limitConverted > 0 ? Double(truncating: spent as NSNumber) / Double(truncating: limitConverted as NSNumber) : 0
            return progress <= 1.0 // Changed to 1.0 to consider "on track" as not over budget, or strict 0.8? Sticking to logic "over budget" count implies > 1.0 usually, but let's keep original logic loosely or refine. Original was <= 0.8. Let's use <= 1.0 for "On Track" in general sense, or strictly adhering to "Healthy". 
            // Let's stick to "On Track" meaning "Not Over Budget" for the text label "X on track, Y over".
        }.count
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Top Row: Spent vs Budgeted
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Budget.totalSpent)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                    Text(totalSpent.formatted(.currency(code: preferredCurrency).presentation(.narrow)))
                        .font(.app(.title2, weight: .bold))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(L10n.Budget.totalBudgeted)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                    Text(totalBudgeted.formatted(.currency(code: preferredCurrency).presentation(.narrow)))
                        .font(.app(.title2, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            
            // Progress Bar
            let progress = totalBudgeted > 0 ? Double(truncating: totalSpent as NSNumber) / Double(truncating: totalBudgeted as NSNumber) : 0
            VStack(spacing: 8) {
                ProgressView(value: min(progress, 1.0))
                    .tint(progress > 1.0 ? .red : (progress > 0.9 ? .orange : ThemeManager.shared.incomeColor))
                
                HStack {
                    Text(L10n.Budget.percentUsed(Int(progress * 100)))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(L10n.Budget.onTrackCount(onTrackCount, budgets.count - onTrackCount))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func calculateSpending(for budget: Budget) -> Decimal {
        let periodRange = budget.periodDateRange
        
        let relevantTransactions = transactions.filter { txn in
            guard !txn.excludeFromReports,
                  txn.type == .expense,
                  txn.date >= periodRange.start && txn.date < periodRange.end else {
                return false
            }
            
            if budget.isTotalBudget {
                return true
            } else if let categories = budget.categories, !categories.isEmpty {
                return categories.contains { $0.id == txn.category?.id }
            } else if let categoryId = budget.category?.id {
                return txn.category?.id == categoryId
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
        if let categories = budget.categories, !categories.isEmpty {
            if categories.count == 1 {
                return categories.first?.icon ?? "folder.fill"
            }
            return "folder.fill" // Generic icon for multiple categories
        } else if let category = budget.category {
            return category.icon
        } else {
            return "chart.pie.fill"
        }
    }
    
    private var iconColor: Color {
        if let categories = budget.categories, !categories.isEmpty {
            if categories.count == 1 {
                return Color(hex: categories.first?.colorHex ?? "") ?? .blue
            }
            return .blue // Default color for multiple
        } else if let category = budget.category {
            return Color(hex: category.colorHex) ?? .blue
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
                    .font(.app(.title3))
                    .foregroundStyle(iconColor)
            }
            
            // MARK: Content
            VStack(alignment: .leading, spacing: 6) {
                // Title Row
                HStack {
                    Text(budget.displayName)
                        .font(.app(.body, weight: .semibold))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Primary Value: Remaining or Spent based on preference/context
                    // Here we focus on "Amount Left" as it's usually what users care about
                    if isOverBudget {
                        Text(spent.formatted(.currency(code: preferredCurrency).presentation(.narrow)))
                            .font(.app(.body, weight: .bold))
                            .foregroundStyle(.red)
                    } else {
                        Text(remaining.formatted(.currency(code: preferredCurrency).presentation(.narrow)))
                            .font(.app(.body, weight: .bold))
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
                                .font(.app(.caption2))
                                .foregroundStyle(.secondary)
                        }
                        
                        if isOverBudget {
                             Text(L10n.Budget.overBy((spent - budgetLimitConverted).formatted(.currency(code: preferredCurrency).presentation(.narrow))))
                                .font(.app(.caption))
                                .foregroundStyle(.red)
                        } else {
                            Text(L10n.Budget.leftOf(budgetLimitConverted.formatted(.currency(code: preferredCurrency).presentation(.narrow))))
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Right: Time Info
                    if budget.isActive {
                        Text(L10n.Budget.daysLeft(budget.daysRemaining))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    } else if budget.isPeriodEnded {
                        Text(L10n.Budget.ended)
                            .font(.app(.caption))
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
            .modelContainer(for: [Budget.self, Transaction.self, Category.self], inMemory: true)
    }
}
