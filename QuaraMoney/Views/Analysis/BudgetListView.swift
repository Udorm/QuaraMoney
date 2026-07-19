import SwiftUI
import SwiftData

struct BudgetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Budget> { $0.deletedAt == nil }, sort: \Budget.createdAt) private var budgets: [Budget]
    @Query(filter: #Predicate<Transaction> { $0.event == nil && $0.deletedAt == nil }) private var transactions: [Transaction]
    @Binding private var searchText: String
    @Binding private var isFilterPresented: Bool
    @State private var filter: PlanBudgetFilter = .all

    init(searchText: Binding<String>, isFilterPresented: Binding<Bool>) {
        _searchText = searchText; _isFilterPresented = isFilterPresented
    }

    private var matching: [Budget] {
        budgets.filter { budget in
            let matchesFilter = switch filter {
            case .all: true
            case .standing, .recurring: budget.periodType != .custom
            case .oneOffs: budget.periodType == .custom
            }
            guard matchesFilter else { return false }
            guard !searchText.isEmpty else { return true }
            return budget.displayName.localizedCaseInsensitiveContains(searchText) ||
                budget.trackedCategoryInfos.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var attentionIDs: Set<UUID> {
        var result = Set(budgets.filter(\.needsAttention).map(\.id))
        let groups = Dictionary(grouping: budgets.filter { $0.periodType != .custom && $0.targetKind == .total },
                                by: \Budget.periodType)
        for duplicates in groups.values where duplicates.count > 1 {
            let canonical = duplicates.min { $0.createdAt < $1.createdAt }?.id
            result.formUnion(duplicates.compactMap { $0.id == canonical ? nil : $0.id })
        }
        return result
    }

    private var attention: [Budget] { matching.filter { attentionIDs.contains($0.id) } }
    private var standing: [Budget] { matching.filter { $0.periodType != .custom && !attentionIDs.contains($0.id) } }
    private var oneOffs: [Budget] { matching.filter { $0.periodType == .custom && !attentionIDs.contains($0.id) } }
    private var upcoming: [Budget] { oneOffs.filter { Date() < $0.periodDateRange.start } }
    private var active: [Budget] { oneOffs.filter(\.isActive) }
    private var ended: [Budget] { oneOffs.filter(\.isPeriodEnded) }

    var body: some View {
        let spending = BudgetCalculator.spendingByBudgetCurrency(for: matching, transactions: transactions)
        let onTrack = matching.filter { $0.amountLimit > 0 && (spending[$0.id] ?? 0) <= $0.amountLimit }.count
        List {
            if matching.isEmpty {
                AppEmptyStateView(L10n.Budget.emptyState, systemImage: "chart.bar",
                                  description: L10n.Budget.emptyDescription)
                    .listRowBackground(Color.clear)
            } else {
                Section { Text("plan.list_on_track".localized(with: onTrack, matching.count)).appFont(size: 15, weight: .semibold) }
                budgetSection("plan.needs_attention".localized, budgets: attention, spending: spending, attention: true)
                budgetSection("plan.your_budgets".localized, budgets: standing, spending: spending)
                budgetSection("plan.upcoming_one_offs".localized, budgets: upcoming, spending: spending)
                budgetSection("plan.active_one_offs".localized, budgets: active, spending: spending)
                budgetSection("plan.ended_one_offs".localized, budgets: ended, spending: spending)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("plan.budgets".localized)
        .searchable(text: $searchText, prompt: "common.search".localized)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("filter.title".localized, selection: $filter) {
                        ForEach(PlanBudgetFilter.allCases) { Text($0.title).tag($0) }
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                .accessibilityLabel("filter.title".localized)
            }
        }
        .syncPullToRefresh(modelContext)
    }

    @ViewBuilder
    private func budgetSection(_ title: String, budgets: [Budget], spending: [UUID: Decimal], attention: Bool = false) -> some View {
        if !budgets.isEmpty {
            Section(title) {
                ForEach(budgets) { budget in
                    NavigationLink(destination: BudgetDetailView(budget: budget, transactions: transactions)) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(budget.displayName).appFont(size: 17, weight: .semibold)
                                Spacer()
                                Text((spending[budget.id] ?? 0).formattedAmount(for: budget.currencyCode))
                                    .appFont(size: 15, weight: .semibold).monospacedDigit()
                            }
                            Text(attention ? attentionReason(budget) : budget.periodDisplayString)
                                .appFont(size: 13, weight: .regular)
                                .foregroundStyle(attention ? .orange : .secondary)
                        }.contentShape(Rectangle())
                    }
                    .swipeActions {
                        Button("common.delete".localized, role: .destructive) { delete(budget) }
                    }
                }
            }
        }
    }

    private func attentionReason(_ budget: Budget) -> String {
        if budget.targetKind == .categories && budget.trackedCategoryIds.isEmpty { return "plan.attention_categories".localized }
        if budget.amountLimit <= 0 { return "plan.attention_limit".localized }
        return "plan.attention_duplicate".localized
    }

    private func delete(_ budget: Budget) {
        SoftDeleteService.delete(budget)
        try? modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
}

private enum PlanBudgetFilter: String, CaseIterable, Identifiable {
    case all, standing, oneOffs, recurring
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "filter.all".localized
        case .standing: return "plan.filter_standing".localized
        case .oneOffs: return "plan.filter_one_offs".localized
        case .recurring: return "budget.recurring_only".localized
        }
    }
}

#Preview {
    NavigationStack { BudgetListView(searchText: .constant(""), isFilterPresented: .constant(false)) }
        .modelContainer(for: [Budget.self, Transaction.self, Category.self], inMemory: true)
}
