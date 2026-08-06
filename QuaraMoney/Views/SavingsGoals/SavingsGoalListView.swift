import SwiftData
import SwiftUI

struct SavingsGoalListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]
    @Query private var legacyGoals: [SavingsGoal]

    @State private var segment: PlanSavingsSegment = .active
    @State private var searchText = ""
    @State private var showForm = false
    @State private var walletToDelete: Wallet?
    @State private var migrationReport = SavingsMigrationReportStore.latest()
    @State private var errorMessage: String?

    init() {
        _wallets = Query(
            filter: #Predicate<Wallet> { $0.deletedAt == nil },
            sort: [SortDescriptor(\Wallet.priority), SortDescriptor(\Wallet.createdAt)]
        )
        _legacyGoals = Query(
            filter: #Predicate<SavingsGoal> { $0.deletedAt == nil },
            sort: [SortDescriptor(\SavingsGoal.priority), SortDescriptor(\SavingsGoal.createdDate)]
        )
    }

    private var savingsWallets: [Wallet] {
        wallets.filter { wallet in
            guard wallet.isSavings, !wallet.isArchived,
                  wallet.isSavingsReached == (segment == .completed) else { return false }
            return searchText.isEmpty || wallet.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var pendingGoals: [SavingsGoal] {
        let adoptedIDs = Set(wallets.compactMap(\.legacySavingsGoalID))
        return legacyGoals.filter { !adoptedIDs.contains($0.id) }
    }

    var body: some View {
        List {
            if let migrationReport, migrationReport.acknowledgedAt == nil,
               !migrationReport.deferredGoalIDs.isEmpty || !migrationReport.failedGoals.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("savings.migrationAttention".localized, systemImage: "exclamationmark.triangle.fill")
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(.orange)
                        Text("savings.migrationAttentionDetail".localized(
                            with: migrationReport.deferredGoalIDs.count + migrationReport.failedGoals.count
                        ))
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                        Button("common.dismiss".localized) {
                            SavingsMigrationReportStore.acknowledgeLatest()
                            self.migrationReport = SavingsMigrationReportStore.latest()
                        }
                        .appFont(.subheadline, weight: .semibold)
                    }
                }
            }

            Section {
                Picker("plan.savings_segment".localized, selection: $segment) {
                    Text("plan.active".localized).tag(PlanSavingsSegment.active)
                    Text("plan.completed".localized).tag(PlanSavingsSegment.completed)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
            .listRowBackground(Color.clear)

            if savingsWallets.isEmpty && (segment == .completed || pendingGoals.isEmpty) {
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
                    ForEach(savingsWallets) { wallet in
                        NavigationLink {
                            LazyView(SavingsGoalDetailView(wallet: wallet))
                        } label: {
                            SavingsGoalRowView(wallet: wallet)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("common.delete".localized, role: .destructive) { walletToDelete = wallet }
                        }
                    }
                }
            }

            if segment == .active && !pendingGoals.isEmpty {
                Section("savings.migrationPending".localized) {
                    ForEach(pendingGoals) { goal in
                        NavigationLink {
                            LazyView(SavingsGoalDetailView(goal: goal))
                        } label: {
                            Label(goal.name, systemImage: "exclamationmark.triangle")
                                .appFont(.body, weight: .medium)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("plan.savings".localized)
        .searchable(text: $searchText, placement: .toolbar, prompt: "common.search".localized)
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showForm = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("plan.new_saving_goal".localized)
            }
        }
        .syncPullToRefresh(modelContext)
        .sheet(isPresented: $showForm) { SavingsGoalFormView() }
        .confirmationDialog(
            "plan.delete_goal_title".localized,
            isPresented: Binding(
                get: { walletToDelete != nil },
                set: { if !$0 { walletToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if walletToDelete?.balance == 0 {
                Button("common.delete".localized, role: .destructive) { deleteSelectedGoal() }
            }
            Button("common.cancel".localized, role: .cancel) { walletToDelete = nil }
        } message: {
            Text(walletToDelete?.balance == 0
                 ? "plan.delete_goal_message".localized
                 : "savings.deleteBalanceFirst".localized)
        }
        .alert(
            "common.error".localized,
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("common.ok".localized) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func deleteSelectedGoal() {
        guard let wallet = walletToDelete else { return }
        do {
            try SoftDeleteService.deleteWallet(wallet, strategy: .deleteTransactions)
            try modelContext.save()
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            walletToDelete = nil
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { SavingsGoalListView() }
        .modelContainer(for: [SavingsGoal.self, Transaction.self, Wallet.self], inMemory: true)
}
