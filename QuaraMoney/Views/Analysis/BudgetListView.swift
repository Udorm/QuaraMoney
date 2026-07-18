import SwiftUI
import SwiftData

struct BudgetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Budget> { $0.deletedAt == nil }, sort: [SortDescriptor(\Budget.startDate, order: .reverse)]) private var budgets: [Budget]
    // Budgets only ever consider non-event transactions; scope the query so we
    // don't materialize the entire event ledger alongside personal transactions.
    @Query(filter: #Predicate<Transaction> { $0.event == nil && $0.deletedAt == nil }) private var transactions: [Transaction]
    @Binding private var searchText: String
    @Binding private var isFilterPresented: Bool
    @State private var filterPeriod: BudgetFilterPeriod = .active
    @State private var showRecurringOnly = false

    init(searchText: Binding<String>, isFilterPresented: Binding<Bool>) {
        _searchText = searchText
        _isFilterPresented = isFilterPresented
    }
    
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
                if let category = budget.category, category.displayName.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                if let categories = budget.categories {
                    if categories.contains(where: { $0.displayName.localizedCaseInsensitiveContains(searchText) }) {
                        return true
                    }
                }
                return false
            }
        }
        
        return result
    }
    
    var body: some View {
        List {
            if budgets.isEmpty {
                Section {
                    AppEmptyStateView(
                        L10n.Budget.emptyState,
                        systemImage: "chart.bar",
                        description: L10n.Budget.emptyDescription
                    )
                    .padding(.vertical, 32)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                // Single-pass spending for every shown budget, computed once per
                // render instead of re-filtering all transactions per budget.
                let shownBudgets = filteredBudgets
                let spending = BudgetCalculator.spendingByBudget(
                    for: shownBudgets,
                    transactions: transactions,
                    targetCurrency: preferredCurrency
                )
                let limits = BudgetCalculator.limitsByBudget(
                    for: shownBudgets,
                    transactions: transactions,
                    targetCurrency: preferredCurrency
                )

                if filterPeriod == .active || filterPeriod == .all {
                    Section {
                        BudgetSummarySection(
                            budgets: shownBudgets.filter { $0.isActive },
                            spending: spending,
                            limits: limits
                        )
                    } header: {
                        filterDescription
                    }
                }

                Section {
                    ForEach(shownBudgets) { budget in
                        NavigationLink(destination: BudgetDetailView(budget: budget, transactions: transactions)) {
                            BudgetRowView(
                                budget: budget,
                                spent: spending[budget.id] ?? 0,
                                budgetLimitConverted: limits[budget.id] ?? 0
                            )
                        }
                    }
                    .onDelete(perform: deleteBudgets)
                } header: {
                    if filterPeriod != .active && filterPeriod != .all {
                        filterDescription
                    }
                }

                if shownBudgets.isEmpty {
                    Section {
                        AppEmptyStateView(
                            L10n.Budget.emptyState,
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: headerTitle
                        )
                        .padding(.vertical, 24)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .sheet(isPresented: $isFilterPresented) {
            FilterSheetView(
                selectedPeriod: $filterPeriod,
                selectedWalletIds: .constant([]),
                customStartDate: .constant(Date()),
                customEndDate: .constant(Date()),
                isPresented: $isFilterPresented,
                wallets: [],
                showWalletFilter: false
            ) {
                Section {
                    Toggle(L10n.Budget.recurringOnly, isOn: $showRecurringOnly)
                }
            }
        }
        .syncPullToRefresh(modelContext)
    }

    private var filterDescription: some View {
        Label(headerTitle, systemImage: filterPeriod.icon)
            .appFont(.caption, weight: .medium)
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
    
    private var headerTitle: String {
        if showRecurringOnly {
            return "\(filterPeriod.displayName) • \(L10n.Budget.recurringOnly)"
        }
        return filterPeriod.displayName
    }
    
    private func deleteBudgets(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let budgetToDelete = filteredBudgets[index]
                if let actualIndex = budgets.firstIndex(where: { $0.id == budgetToDelete.id }) {
                    SoftDeleteService.delete(budgets[actualIndex])
                }
            }
        }
        try? modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
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
    /// Precomputed spent-per-budget (keyed by `budget.id`) from a single pass.
    let spending: [UUID: Decimal]
    let limits: [UUID: Decimal]

    private var preferredCurrency: String {
        CurrencyManager.shared.preferredCurrencyCode
    }

    private func spent(for budget: Budget) -> Decimal {
        spending[budget.id] ?? 0
    }

    private var totalBudgeted: Decimal {
        budgets.reduce(Decimal.zero) { total, budget in
            total + (limits[budget.id] ?? 0)
        }
    }

    private var totalSpent: Decimal {
        budgets.reduce(Decimal.zero) { total, budget in
            total + spent(for: budget)
        }
    }

    private var onTrackCount: Int {
        budgets.filter { budget in
            let spentAmount = spent(for: budget)
            let limitConverted = limits[budget.id] ?? 0
            let progress = limitConverted > 0 ? Double(truncating: spentAmount as NSNumber) / Double(truncating: limitConverted as NSNumber) : 0
            return progress <= 1.0
        }.count
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Budget.totalSpent)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    Text(totalSpent.formattedAmount(for: preferredCurrency))
                        .appFont(.title2, weight: .bold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(L10n.Budget.totalBudgeted)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    Text(totalBudgeted.formattedAmount(for: preferredCurrency))
                        .appFont(.title2, weight: .bold)
                        .foregroundStyle(.secondary)
                }
            }
            
            let progress = totalBudgeted > 0 ? Double(truncating: totalSpent as NSNumber) / Double(truncating: totalBudgeted as NSNumber) : 0
            VStack(spacing: 8) {
                ProgressView(value: min(progress, 1.0))
                    .tint(progress > 1.0 ? .red : (progress > 0.9 ? .orange : ThemeManager.shared.incomeColor))
                
                HStack {
                    Text(L10n.Budget.percentUsed(Int(progress * 100)))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(L10n.Budget.onTrackCount(onTrackCount, budgets.count - onTrackCount))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
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
                    .appFont(.title3)
                    .foregroundStyle(iconColor)
            }
            
            // MARK: Content
            VStack(alignment: .leading, spacing: 6) {
                // Title Row
                HStack {
                    Text(budget.displayName)
                        .appFont(.body, weight: .semibold)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Primary Value: Remaining or Spent based on preference/context
                    // Here we focus on "Amount Left" as it's usually what users care about
                    if isOverBudget {
                        Text(spent.formattedAmount(for: preferredCurrency))
                            .appFont(.body, weight: .bold)
                            .foregroundStyle(ThemeManager.shared.expenseColor)
                    } else {
                        Text(remaining.formattedAmount(for: preferredCurrency))
                            .appFont(.body, weight: .bold)
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
                                .appFont(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        if isOverBudget {
                             Text(L10n.Budget.overBy((spent - budgetLimitConverted).formattedAmount(for: preferredCurrency)))
                                .appFont(.caption)
                                .foregroundStyle(ThemeManager.shared.expenseColor)
                        } else {
                            Text(L10n.Budget.leftOf(budgetLimitConverted.formattedAmount(for: preferredCurrency)))
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Right: Time Info
                    if budget.isActive {
                        Text(L10n.Budget.daysLeft(budget.daysRemaining))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    } else if budget.isPeriodEnded {
                        Text(L10n.Budget.ended)
                            .appFont(.caption)
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
        BudgetListView(
            searchText: .constant(""),
            isFilterPresented: .constant(false)
        )
            .modelContainer(for: [Budget.self, Transaction.self, TransactionLocation.self, Category.self], inMemory: true)
    }
}
