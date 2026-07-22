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

                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("tab.plan".localized)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showBudgetForm = true
                        } label: {
                            Label("plan.new_budget".localized, systemImage: "chart.bar.fill")
                        }

                        Button {
                            showGoalForm = true
                        } label: {
                            Label("plan.new_saving_goal".localized, systemImage: "target")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("plan.quick_actions".localized)
                }
            }
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
        PlanCard(tint: .accentColor, usesGlass: true) {
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
                        if metrics.isDeterminate {
                            budgetPrimaryAmount(metrics, limit: limit)

                            if let progress = metrics.progress {
                                VStack(alignment: .leading, spacing: 10) {
                                    PlanProgressLine(progress: progress, color: budgetAmountColor(metrics))
                                    budgetSupportingAmounts(metrics, limit: limit)
                                    budgetClassification(metrics)
                                }
                            } else {
                                budgetClassification(metrics)
                            }
                        } else {
                            PlanAmountSummary(
                                title: "plan.spent".localized,
                                amount: metrics.spent.formattedAmount(for: metrics.currencyCode),
                                amountColor: .orange
                            )
                            VStack(alignment: .leading, spacing: 10) {
                                PlanPartialDataLabel()
                                budgetClassification(metrics)
                            }
                        }
                    } else {
                        PlanPartialDataLabel()
                        budgetClassification(metrics)
                    }
                case .spendingOnly:
                    PlanAmountSummary(
                        title: "plan.spent_this_month".localized,
                        amount: metrics.spent.formattedAmount(for: metrics.currencyCode)
                    )
                    if !metrics.isDeterminate { PlanPartialDataLabel() }
                    budgetClassification(metrics)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func budgetPrimaryAmount(_ metrics: PlanBudgetOverviewMetrics, limit: Decimal) -> some View {
        let overage = max(0, metrics.spent - limit)
        if overage > 0 {
            PlanAmountSummary(
                title: "plan.over_budget".localized,
                amount: overage.formattedAmount(for: metrics.currencyCode),
                amountColor: .red
            )
        } else {
            PlanAmountSummary(
                title: "plan.remaining".localized,
                amount: max(0, limit - metrics.spent).formattedAmount(for: metrics.currencyCode),
                targetAmount: limit.formattedAmount(for: metrics.currencyCode),
                amountColor: .accentColor
            )
        }
    }

    @ViewBuilder
    private func budgetSupportingAmounts(_ metrics: PlanBudgetOverviewMetrics, limit: Decimal) -> some View {
        if metrics.spent > limit {
            HStack(spacing: 16) {
                overviewStat(
                    title: "plan.spent".localized,
                    value: metrics.spent.formattedAmount(for: metrics.currencyCode)
                )
                Divider().frame(height: 34)
                overviewStat(
                    title: "plan.limit".localized,
                    value: limit.formattedAmount(for: metrics.currencyCode)
                )
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text("plan.spent".localized)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(metrics.spent.formattedAmount(for: metrics.currencyCode))
                    .appFont(.subheadline, weight: .semibold)
                    .monospacedDigit()
            }
        }
    }

    private func overviewStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .appFont(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .appFont(.subheadline, weight: .semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func budgetAmountColor(_ metrics: PlanBudgetOverviewMetrics) -> Color {
        guard let progress = metrics.progress, progress > 1 else { return .accentColor }
        return .red
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
        PlanCard(tint: .green, usesGlass: true) {
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
                    PlanAmountSummary(
                        title: "plan.saved".localized,
                        amount: metrics.saved.formattedAmount(for: metrics.currencyCode),
                        amountColor: .green
                    )
                    Label("plan.all_goals_completed".localized, systemImage: "checkmark.circle.fill")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.green)
                    if !metrics.isDeterminate { PlanPartialDataLabel() }
                case .active:
                    if let target = metrics.target {
                        PlanAmountSummary(
                            title: "plan.saved".localized,
                            amount: metrics.saved.formattedAmount(for: metrics.currencyCode),
                            targetAmount: target.formattedAmount(for: metrics.currencyCode),
                            amountColor: .green
                        )
                    }
                    if let progress = metrics.progress {
                        PlanProgressLine(
                            progress: progress,
                            color: .green,
                            isDeterminate: metrics.isDeterminate
                        )
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

}

#Preview {
    PlanOverviewView()
        .modelContainer(for: [Budget.self, SavingsGoal.self, Transaction.self, Category.self, Wallet.self], inMemory: true)
}
