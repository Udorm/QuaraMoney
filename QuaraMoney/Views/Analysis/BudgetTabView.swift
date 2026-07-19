import SwiftUI
import SwiftData

/// Compatibility entry point retained for ContentView.
struct BudgetTabView: View {
    var body: some View { PlanOverviewView() }
}

struct PlanOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var store = PlanOverviewStore()
    @State private var refreshPolicy = PlanRefreshPolicy()
    @State private var showBudgetForm = false
    @State private var showGoalForm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    NavigationLink {
                        LazyView(BudgetListView())
                    } label: {
                        budgetCard
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        LazyView(SavingsGoalListView())
                    } label: {
                        savingsCard
                    }
                    .buttonStyle(.plain)

                    quickActions
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("tab.plan".localized)
            .syncPullToRefresh(modelContext)
            .onAppear {
                store.configure(modelContext: modelContext)
                refreshPolicy.configure { store.refresh() }
                refreshPolicy.setVisible(true)
            }
            .onDisappear { refreshPolicy.setVisible(false) }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { refreshPolicy.sceneBecameActive() }
            }
            .sheet(isPresented: $showBudgetForm) {
                BudgetFormView()
            }
            .sheet(isPresented: $showGoalForm) {
                SavingsGoalFormView()
            }
            .alert(
                "common.error".localized,
                isPresented: Binding(
                    get: { store.errorMessage != nil },
                    set: { _ in }
                )
            ) {
                Button("common.ok".localized) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var budgetCard: some View {
        PlanCard(tint: .accentColor) {
            HStack(alignment: .top, spacing: 14) {
                PlanIconTile(systemImage: "chart.bar.fill", color: .accentColor, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("plan.budgets".localized)
                        .appFont(.headline, weight: .bold)
                    Text(budgetSubtitle)
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.secondary)
            }

            if let metrics = store.metrics?.budgets {
                switch metrics.mode {
                case .empty:
                    EmptyView()
                case .attention:
                    Label("plan.budget_setup_needed".localized, systemImage: "exclamationmark.triangle.fill")
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.orange)
                case .aggregateWithLimit:
                    if let limit = metrics.limit {
                        Text("plan.spent_of".localized(
                            with: metrics.spent.formattedAmount(for: metrics.currencyCode),
                            limit.formattedAmount(for: metrics.currencyCode)
                        ))
                        .appFont(.title2, weight: .bold)
                        .monospacedDigit()
                    }
                    if let progress = metrics.progress, metrics.isDeterminate {
                        PlanProgressBar(progress: progress, color: .accentColor)
                        HStack {
                            Text(PlanDisplayFormatting.percent(progress))
                                .appFont(.caption, weight: .semibold)
                                .monospacedDigit()
                            Spacer()
                            budgetClassification(metrics)
                        }
                    } else {
                        PlanPartialDataLabel()
                        budgetClassification(metrics)
                    }
                case .spendingOnly:
                    Text(metrics.spent.formattedAmount(for: metrics.currencyCode))
                        .appFont(.title2, weight: .bold)
                        .monospacedDigit()
                    Text("plan.spent_this_month".localized)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    if !metrics.isDeterminate { PlanPartialDataLabel() }
                    budgetClassification(metrics)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var budgetSubtitle: String {
        guard let metrics = store.metrics?.budgets else { return "plan.budget_card_subtitle".localized }
        return metrics.mode == .empty
            ? "plan.create_first_budget".localized
            : "plan.budget_card_subtitle".localized
    }

    private func budgetClassification(_ metrics: PlanBudgetOverviewMetrics) -> some View {
        let text: String
        if metrics.unknownCount > 0 {
            text = "plan.on_track_with_unknown".localized(
                with: metrics.onTrackCount,
                metrics.classifiedCount,
                metrics.unknownCount
            )
        } else {
            text = "plan.on_track_count".localized(with: metrics.onTrackCount, metrics.classifiedCount)
        }
        return Text(text)
            .appFont(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var savingsCard: some View {
        PlanCard(tint: .green) {
            HStack(alignment: .top, spacing: 14) {
                PlanIconTile(systemImage: "target", color: .green, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("plan.savings".localized)
                        .appFont(.headline, weight: .bold)
                    Text(savingsSubtitle)
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.secondary)
            }

            if let metrics = store.metrics?.savings {
                switch metrics.mode {
                case .empty:
                    EmptyView()
                case .allCompleted:
                    Text("plan.all_goals_completed".localized)
                        .appFont(.title3, weight: .bold)
                        .foregroundStyle(.green)
                    Text("plan.lifetime_saved".localized(
                        with: metrics.saved.formattedAmount(for: metrics.currencyCode)
                    ))
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    if !metrics.isDeterminate { PlanPartialDataLabel() }
                case .active:
                    if let target = metrics.target {
                        Text("plan.saved_of".localized(
                            with: metrics.saved.formattedAmount(for: metrics.currencyCode),
                            target.formattedAmount(for: metrics.currencyCode)
                        ))
                        .appFont(.title2, weight: .bold)
                        .monospacedDigit()
                    }
                    if let progress = metrics.progress {
                        PlanProgressBar(
                            progress: progress,
                            color: .green,
                            isDeterminate: metrics.isDeterminate
                        )
                        Text(PlanDisplayFormatting.percent(progress))
                            .appFont(.caption, weight: .semibold)
                            .monospacedDigit()
                    }
                    Text("plan.goal_counts".localized(
                        with: metrics.activeCount,
                        metrics.completedCount,
                        metrics.unknownCount
                    ))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    if !metrics.isDeterminate { PlanPartialDataLabel() }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var savingsSubtitle: String {
        guard let metrics = store.metrics?.savings else { return "plan.savings_card_subtitle".localized }
        return metrics.mode == .empty
            ? "plan.create_first_goal".localized
            : "plan.savings_card_subtitle".localized
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("plan.quick_actions".localized)
                .appFont(.headline, weight: .bold)

            HStack(spacing: 12) {
                Button {
                    showBudgetForm = true
                } label: {
                    Label("plan.new_budget".localized, systemImage: "chart.bar.fill")
                        .appFont(.subheadline, weight: .semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    showGoalForm = true
                } label: {
                    Label("plan.new_saving_goal".localized, systemImage: "target")
                        .appFont(.subheadline, weight: .semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
}

#Preview {
    PlanOverviewView()
        .modelContainer(for: [Budget.self, SavingsGoal.self, Transaction.self, Category.self, Wallet.self], inMemory: true)
}
