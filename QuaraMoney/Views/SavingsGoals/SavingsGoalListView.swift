import SwiftUI
import SwiftData

struct SavingsGoalListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var goals: [SavingsGoal]
    @Binding private var searchText: String

    init(searchText: Binding<String>) {
        let notDeleted = #Predicate<SavingsGoal> { $0.deletedAt == nil }
        _goals = Query(filter: notDeleted, sort: [SortDescriptor(\SavingsGoal.priority), SortDescriptor(\SavingsGoal.createdDate)])
        _searchText = searchText
    }

    @State private var viewModel = SavingsGoalListViewModel()

    private var activeGoals: [SavingsGoal] {
        viewModel.activeGoals(from: goals, matching: searchText)
    }

    private var completedGoals: [SavingsGoal] {
        viewModel.completedGoals(from: goals, matching: searchText)
    }

    private var dominantColor: Color {
        if let first = activeGoals.first {
            return Color(hex: first.colorHex) ?? .blue
        }
        return .blue
    }

    var body: some View {
        List {
            if goals.isEmpty {
                Section {
                    AppEmptyStateView(
                        L10n.Savings.noGoals,
                        systemImage: "target",
                        description: L10n.Savings.noGoalsDescription
                    )
                    .padding(.vertical, 32)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                // MARK: Summary Section
                SavingsGoalSummaryCard(
                    totalSaved: viewModel.totalSaved(from: goals),
                    totalTarget: viewModel.totalTarget(from: goals),
                    overallProgress: viewModel.overallProgress(from: goals),
                    activeCount: activeGoals.count,
                    completedCount: completedGoals.count,
                    dominantColor: dominantColor
                )

                // MARK: Active Goals
                if !activeGoals.isEmpty {
                    Section(L10n.Savings.activeGoals) {
                        ForEach(activeGoals) { goal in
                            NavigationLink {
                                SavingsGoalDetailView(goal: goal)
                            } label: {
                                SavingsGoalRowView(goal: goal)
                            }
                        }
                        .onDelete { indexSet in
                            deleteGoals(at: indexSet, from: activeGoals)
                        }
                    }
                }

                // MARK: Completed Goals
                if !completedGoals.isEmpty {
                    Section {
                        DisclosureGroup("\(L10n.Savings.completedGoals) (\(completedGoals.count))", isExpanded: $viewModel.showCompletedGoals) {
                            ForEach(completedGoals) { goal in
                                NavigationLink {
                                    SavingsGoalDetailView(goal: goal)
                                } label: {
                                    SavingsGoalRowView(goal: goal)
                                }
                            }
                            .onDelete { indexSet in
                                deleteGoals(at: indexSet, from: completedGoals)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .syncPullToRefresh(modelContext)
    }

    private func deleteGoals(at offsets: IndexSet, from source: [SavingsGoal]) {
        withAnimation {
            for index in offsets {
                SoftDeleteService.delete(source[index])
            }
        }
        try? modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
}

#Preview {
    NavigationStack {
        SavingsGoalListView(searchText: .constant(""))
    }
    .modelContainer(for: [SavingsGoal.self, Wallet.self], inMemory: true)
}
