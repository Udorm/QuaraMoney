import SwiftUI
import SwiftData

struct BudgetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<Budget> { $0.deletedAt == nil }, sort: \Budget.createdAt)
    private var budgets: [Budget]

    @State private var store = PlanBudgetListStore()
    @State private var refreshPolicy = PlanRefreshPolicy()
    @State private var segment: PlanBudgetSegment = .active
    @State private var searchText = ""
    @State private var showForm = false
    @State private var budgetToDelete: Budget?
    @State private var errorMessage: String?

    private let mutationExecutor = PlanMutationExecutor()

    private var matchingItems: [PlanBudgetListItemState] {
        guard !searchText.isEmpty else { return store.items }
        return store.items.filter { item in
            guard let budget = budget(for: item.budgetID) else { return false }
            return budget.displayName.localizedCaseInsensitiveContains(searchText) ||
                budget.trackedCategoryInfos.contains {
                    $0.name.localizedCaseInsensitiveContains(searchText)
                }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("plan.budget_segment".localized, selection: $segment) {
                    Text("plan.active".localized).tag(PlanBudgetSegment.active)
                    Text("plan.ended".localized).tag(PlanBudgetSegment.ended)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
            .listRowBackground(Color.clear)

            if store.isLoading && !store.hasLoaded {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                }
                .listRowBackground(Color.clear)
            } else if matchingItems.isEmpty {
                Section {
                    AppEmptyStateView(
                        searchText.isEmpty
                            ? (segment == .active ? "plan.no_active_budgets".localized : "plan.no_ended_budgets".localized)
                            : "common.noResults".localized,
                        systemImage: searchText.isEmpty ? "chart.bar" : "magnifyingglass",
                        description: searchText.isEmpty
                            ? "plan.no_budgets_segment_description".localized
                            : "plan.search_no_results".localized
                    )
                    .padding(.vertical, 28)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(matchingItems) { item in
                        if let budget = budget(for: item.budgetID) {
                            NavigationLink {
                                LazyView(BudgetDetailView(budget: budget))
                            } label: {
                                PlanBudgetListRow(budget: budget, state: item)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("common.delete".localized, role: .destructive) {
                                    budgetToDelete = budget
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("plan.budgets".localized)
        .searchable(text: $searchText, placement: .toolbar, prompt: "common.search".localized)
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("plan.new_budget".localized)
            }
        }
        .syncPullToRefresh(modelContext)
        .onAppear {
            store.configure(modelContext: modelContext)
            refreshPolicy.configure { store.refresh(segment: segment) }
            refreshPolicy.setVisible(true)
        }
        .onDisappear { refreshPolicy.setVisible(false) }
        .onChange(of: segment) { _, newSegment in
            store.refresh(segment: newSegment)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { refreshPolicy.sceneBecameActive() }
        }
        .sheet(isPresented: $showForm) {
            BudgetFormView()
        }
        .confirmationDialog(
            "plan.delete_budget_title".localized,
            isPresented: Binding(
                get: { budgetToDelete != nil },
                set: { if !$0 { budgetToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("common.delete".localized, role: .destructive) { deleteSelectedBudget() }
            Button("common.cancel".localized, role: .cancel) { budgetToDelete = nil }
        } message: {
            Text("plan.delete_budget_message".localized)
        }
        .alert(
            "common.error".localized,
            isPresented: Binding(
                get: { errorMessage != nil || store.errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("common.ok".localized) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? store.errorMessage ?? "")
        }
    }

    private func budget(for id: UUID) -> Budget? {
        budgets.first { $0.id == id }
    }

    private func deleteSelectedBudget() {
        guard let budget = budgetToDelete else { return }
        do {
            try mutationExecutor.softDelete(budget, in: modelContext)
            HapticManager.shared.success()
            budgetToDelete = nil
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }
}

private struct PlanBudgetListRow: View {
    let budget: Budget
    let state: PlanBudgetListItemState

    private var color: Color {
        if state.projection.isOnTrack == false { return .red }
        if let category = budget.trackedCategoryInfos.first {
            return Color(hex: category.colorHex) ?? .accentColor
        }
        return .accentColor
    }

    private var icon: String {
        budget.trackedCategoryInfos.first?.icon ?? "sum"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PlanIconTile(systemImage: icon, color: color)

            VStack(alignment: .leading, spacing: 7) {
                Text(budget.displayName)
                    .appFont(.body, weight: .semibold)
                    .lineLimit(1)

                Text(statusLine)
                    .appFont(.caption)
                    .foregroundStyle(state.isUpcoming ? .blue : .secondary)

                if state.projection.isDeterminate {
                    (Text(state.projection.spent.formattedAmount(for: budget.currencyCode))
                        .foregroundStyle(.primary)
                     + Text(" / \(state.projection.limit.formattedAmount(for: budget.currencyCode))")
                        .foregroundStyle(.secondary))
                        .appFont(.caption, weight: .medium)
                        .monospacedDigit()

                    PlanProgressLine(progress: state.projection.progress, color: color)
                } else {
                    Text(state.projection.spent.formattedAmount(for: budget.currencyCode))
                        .appFont(.caption, weight: .medium)
                        .monospacedDigit()
                    PlanPartialDataLabel()
                }

                if state.needsAttention || state.isDuplicateTotal {
                    Label(attentionText, systemImage: "exclamationmark.triangle.fill")
                        .appFont(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusLine: String {
        if state.isUpcoming {
            return "plan.starts_date".localized(
                with: state.range.start.appFormatted(date: .abbreviated, time: .omitted)
            )
        }
        if state.isEnded, state.projection.isDeterminate {
            if state.projection.overage > 0 {
                return "plan.over_by".localized(
                    with: state.projection.overage.formattedAmount(for: budget.currencyCode)
                )
            }
            return "plan.under_by".localized(
                with: state.projection.remaining.formattedAmount(for: budget.currencyCode)
            )
        }
        return budget.periodType.displayName
    }

    private var attentionText: String {
        if state.isDuplicateTotal { return "plan.attention_duplicate".localized }
        if budget.targetKind == .categories && budget.trackedCategoryIds.isEmpty {
            return "plan.attention_categories".localized
        }
        return "plan.attention_limit".localized
    }
}

#Preview {
    NavigationStack { BudgetListView() }
        .modelContainer(for: [Budget.self, Transaction.self, Category.self, Wallet.self], inMemory: true)
}
