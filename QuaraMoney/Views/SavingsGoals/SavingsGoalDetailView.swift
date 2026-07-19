import SwiftUI
import SwiftData
import Charts

struct SavingsGoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let goal: SavingsGoal

    @State private var store = PlanSavingsDetailStore()
    @State private var refreshPolicy = PlanRefreshPolicy()
    @State private var showContribution = false
    @State private var showWithdrawal = false
    @State private var showEditForm = false

    private var color: Color { Color(hex: goal.colorHex) ?? .green }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                heroCard

                if let state = store.state {
                    statCard(state)
                    progressCard(state)
                    recentContributionsCard(state)
                    actionButtons
                } else if store.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("common.edit".localized) { showEditForm = true }
            }
        }
        .syncPullToRefresh(modelContext)
        .onAppear {
            store.configure(modelContext: modelContext)
            refreshPolicy.configure { store.refresh(goalID: goal.id) }
            refreshPolicy.setVisible(true)
        }
        .onDisappear { refreshPolicy.setVisible(false) }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { refreshPolicy.sceneBecameActive() }
        }
        .sheet(isPresented: $showContribution) {
            SavingsContributionSheet(goal: goal, isWithdrawal: false)
        }
        .sheet(isPresented: $showWithdrawal) {
            SavingsContributionSheet(goal: goal, isWithdrawal: true)
        }
        .sheet(isPresented: $showEditForm) {
            SavingsGoalFormView(existing: goal) {
                dismiss()
            }
        }
        .alert(
            "common.error".localized,
            isPresented: Binding(get: { store.errorMessage != nil }, set: { _ in })
        ) {
            Button("common.ok".localized) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var heroCard: some View {
        PlanCard(tint: color) {
            HStack(spacing: 18) {
                Image(systemName: goal.iconName)
                    .appFont(size: 32, weight: .semibold)
                    .foregroundStyle(.white)
                    .frame(width: 78, height: 78)
                    .background(
                        LinearGradient(
                            colors: [color, color.opacity(0.68)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(goal.name)
                        .appFont(.title2, weight: .bold)
                    if let targetDate = goal.targetDate {
                        Text("plan.target_date_value".localized(
                            with: targetDate.appFormatted(date: .abbreviated, time: .omitted)
                        ))
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("savings.status.noDate".localized)
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if store.state?.metrics.isCompleted == true {
                        Label("plan.completed".localized, systemImage: "checkmark.circle.fill")
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.12), in: Capsule())
                    }
                }
                Spacer()
            }
        }
    }

    private func statCard(_ state: PlanSavingsDetailState) -> some View {
        PlanCard {
            Text("plan.savings_progress".localized)
                .appFont(.headline, weight: .bold)

            if state.metrics.isDeterminate {
                Text("plan.saved_of".localized(
                    with: state.metrics.saved.formattedAmount(for: goal.currencyCode),
                    goal.targetAmount.formattedAmount(for: goal.currencyCode)
                ))
                .appFont(.title2, weight: .bold)
                .monospacedDigit()

                PlanProgressBar(progress: state.metrics.progress, color: color)
                Text(PlanDisplayFormatting.percent(state.metrics.progress))
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(color)
                    .monospacedDigit()

                HStack(spacing: 0) {
                    statColumn(
                        title: "plan.to_go".localized,
                        value: state.metrics.remaining.formattedAmount(for: goal.currencyCode)
                    )
                    if let monthlyTarget = state.metrics.monthlyTarget {
                        Divider().frame(height: 44)
                        statColumn(
                            title: "plan.monthly_target".localized,
                            value: monthlyTarget.formattedAmount(for: goal.currencyCode)
                        )
                    }
                }
            } else {
                Text(state.metrics.saved.formattedAmount(for: goal.currencyCode))
                    .appFont(.title2, weight: .bold)
                    .monospacedDigit()
                PlanProgressBar(progress: state.metrics.progress, color: .orange, isDeterminate: false)
                PlanPartialDataLabel()
            }
        }
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appFont(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .appFont(.subheadline, weight: .semibold)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressCard(_ state: PlanSavingsDetailState) -> some View {
        PlanCard {
            Text("plan.progress_over_time".localized)
                .appFont(.headline, weight: .bold)

            Chart(state.progressSeries.points) { point in
                BarMark(
                    x: .value("plan.month".localized, point.date, unit: .month),
                    y: .value(
                        "plan.saved".localized,
                        MoneyMinorUnitConverter.toMinorUnits(point.saved, currencyCode: goal.currencyCode)
                    )
                )
                .foregroundStyle(point.isUpcoming ? Color.orange.gradient : color.gradient)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            let isUpcoming = state.progressSeries.points.contains {
                                $0.isUpcoming && Calendar.current.isDate($0.date, equalTo: date, toGranularity: .month)
                            }
                            Text(isUpcoming
                                 ? "plan.upcoming".localized
                                 : AppDateFormatterCache.formatter(dateFormat: "MMM", locale: .app).string(from: date))
                                .appFont(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let minor = value.as(Int64.self) {
                            Text(MoneyMinorUnitConverter.fromMinorUnits(minor, currencyCode: goal.currencyCode)
                                .formattedAmountShort(for: goal.currencyCode))
                                .appFont(.caption2)
                        }
                    }
                }
            }
            .frame(height: 220)

            if !state.progressSeries.isDeterminate { PlanPartialDataLabel() }
        }
    }

    private func recentContributionsCard(_ state: PlanSavingsDetailState) -> some View {
        PlanCard(spacing: 10) {
            HStack {
                Text("plan.recent_contributions".localized)
                    .appFont(.headline, weight: .bold)
                Spacer()
                if !state.ledgerRows.isEmpty {
                    NavigationLink {
                        SavingsLedgerListView(goal: goal, rows: state.ledgerRows)
                    } label: {
                        Text("common.seeAll".localized)
                            .appFont(.subheadline, weight: .semibold)
                    }
                }
            }

            if state.ledgerRows.isEmpty {
                Text("plan.no_contributions".localized)
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                ForEach(Array(state.ledgerRows.prefix(5))) { row in
                    SavingsLedgerRowView(row: row, color: color)
                    if row.id != state.ledgerRows.prefix(5).last?.id {
                        Divider().padding(.leading, 42)
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                showContribution = true
            } label: {
                Label("plan.add_money".localized, systemImage: "plus.circle.fill")
                    .appFont(.headline, weight: .semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(color)
            .controlSize(.large)

            Button {
                showWithdrawal = true
            } label: {
                Text("plan.withdraw".localized)
                    .appFont(.subheadline, weight: .semibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
        }
    }
}

private struct SavingsLedgerListView: View {
    let goal: SavingsGoal
    let rows: [PlanSavingsLedgerDisplayRow]

    private var color: Color { Color(hex: goal.colorHex) ?? .green }

    var body: some View {
        List(rows) { row in
            SavingsLedgerRowView(row: row, color: color)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("plan.contributions".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SavingsLedgerRowView: View {
    let row: PlanSavingsLedgerDisplayRow
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.isWithdrawal ? "arrow.up.right" : "arrow.down.left")
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(row.isWithdrawal ? .orange : color)
                .frame(width: 34, height: 34)
                .background(
                    (row.isWithdrawal ? Color.orange : color).opacity(0.12),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(row.isWithdrawal ? "plan.withdrawal".localized : "plan.contribution".localized)
                    .appFont(.subheadline, weight: .medium)
                Text(row.date.appFormatted(date: .abbreviated, time: .shortened))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let convertedAmount = row.convertedAmount {
                    Text(signed(convertedAmount).formattedAmount(for: row.goalCurrencyCode))
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(row.isWithdrawal ? .orange : color)
                        .monospacedDigit()
                } else {
                    Text(signed(row.originalAmount).formattedAmount(for: row.originalCurrencyCode))
                        .appFont(.subheadline, weight: .semibold)
                        .monospacedDigit()
                    Text("plan.unconverted_amount".localized)
                        .appFont(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func signed(_ amount: Decimal) -> Decimal {
        row.isWithdrawal ? -amount : amount
    }
}

/// Wraps the existing transaction form in locked-goal mode. The preselected
/// goal stays fixed even when it is already complete.
struct SavingsContributionSheet: View {
    @Environment(\.modelContext) private var modelContext
    let goal: SavingsGoal
    let isWithdrawal: Bool

    @State private var viewModel: AddTransactionViewModel?

    var body: some View {
        Group {
            if let viewModel {
                AddTransactionView(
                    viewModel: viewModel,
                    isNewTransaction: true,
                    locksSavingsGoal: true
                )
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard viewModel == nil else { return }
            let model = AddTransactionViewModel(
                dataService: SwiftDataService(modelContext: modelContext),
                initialWallet: nil
            )
            model.type = .transfer
            model.note = goal.name
            model.selectedSavingsGoal = goal
            model.savingsIsWithdrawal = isWithdrawal
            if let wallet = goal.linkedWallet {
                if isWithdrawal { model.selectedWallet = wallet }
                else { model.destinationWallet = wallet }
            }
            viewModel = model
        }
    }
}

#Preview {
    let goal = SavingsGoal(name: "Emergency Fund", targetAmount: 10_000, currencyCode: "USD")
    NavigationStack { SavingsGoalDetailView(goal: goal) }
        .modelContainer(for: [SavingsGoal.self, Transaction.self, Wallet.self], inMemory: true)
}
