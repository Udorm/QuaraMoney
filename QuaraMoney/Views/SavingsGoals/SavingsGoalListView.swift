import SwiftUI
import SwiftData

struct SavingsGoalListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var goals: [SavingsGoal]

    @State private var store = PlanSavingsListStore()
    @State private var refreshPolicy = PlanRefreshPolicy()
    @State private var segment: PlanSavingsSegment = .active
    @State private var searchText = ""
    @State private var showForm = false
    @State private var goalToDelete: SavingsGoal?
    @State private var errorMessage: String?

    private let mutationExecutor = PlanMutationExecutor()

    init() {
        _goals = Query(
            filter: #Predicate<SavingsGoal> { $0.deletedAt == nil },
            sort: [SortDescriptor(\SavingsGoal.priority), SortDescriptor(\SavingsGoal.createdDate)]
        )
    }

    private var matchingItems: [PlanSavingsListItemState] {
        guard !searchText.isEmpty else { return store.items }
        return store.items.filter { item in
            goal(for: item.goalID)?.name.localizedCaseInsensitiveContains(searchText) == true
        }
    }

    var body: some View {
        List {
            Section {
                Picker("plan.savings_segment".localized, selection: $segment) {
                    Text("plan.active".localized).tag(PlanSavingsSegment.active)
                    Text("plan.completed".localized).tag(PlanSavingsSegment.completed)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
                            ? (segment == .active ? "plan.no_active_goals".localized : "plan.no_completed_goals".localized)
                            : "common.noResults".localized,
                        systemImage: searchText.isEmpty ? "target" : "magnifyingglass",
                        description: searchText.isEmpty
                            ? "plan.no_goals_segment_description".localized
                            : "plan.search_no_results".localized
                    )
                    .padding(.vertical, 28)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(matchingItems) { item in
                        if let goal = goal(for: item.goalID) {
                            NavigationLink {
                                LazyView(SavingsGoalDetailView(goal: goal))
                            } label: {
                                SavingsGoalRowView(goal: goal, metrics: item.metrics)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("common.delete".localized, role: .destructive) {
                                    goalToDelete = goal
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("plan.savings".localized)
        .searchable(text: $searchText, prompt: "common.search".localized)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("plan.new_saving_goal".localized)
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
            SavingsGoalFormView()
        }
        .confirmationDialog(
            "plan.delete_goal_title".localized,
            isPresented: Binding(
                get: { goalToDelete != nil },
                set: { if !$0 { goalToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("common.delete".localized, role: .destructive) { deleteSelectedGoal() }
            Button("common.cancel".localized, role: .cancel) { goalToDelete = nil }
        } message: {
            Text("plan.delete_goal_message".localized)
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

    private func goal(for id: UUID) -> SavingsGoal? {
        goals.first { $0.id == id }
    }

    private func deleteSelectedGoal() {
        guard let goal = goalToDelete else { return }
        do {
            try mutationExecutor.softDelete(goal, in: modelContext)
            HapticManager.shared.success()
            goalToDelete = nil
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }
}

#Preview {
    NavigationStack { SavingsGoalListView() }
        .modelContainer(for: [SavingsGoal.self, Transaction.self, Wallet.self], inMemory: true)
}
