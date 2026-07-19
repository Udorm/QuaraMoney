import SwiftUI
import SwiftData
import Charts

struct BudgetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let budget: Budget

    @State private var store = PlanBudgetDetailStore()
    @State private var refreshPolicy = PlanRefreshPolicy()
    @State private var showEditForm = false
    @State private var transactionToEdit: Transaction?

    private var accentColor: Color {
        if let category = budget.trackedCategoryInfos.first {
            return Color(hex: category.colorHex) ?? .accentColor
        }
        return .accentColor
    }

    private var iconName: String {
        budget.trackedCategoryInfos.first?.icon ?? "sum"
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                heroCard

                if let state = store.state {
                    statCard(state)
                    if !state.projection.relevantTransactionIDs.isEmpty,
                       !state.trend.isDegenerate {
                        trendCard(state)
                    }
                    recentTransactionsCard(state)
                } else if store.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(budget.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("common.edit".localized) { showEditForm = true }
            }
        }
        .syncPullToRefresh(modelContext)
        .onAppear {
            store.configure(modelContext: modelContext)
            refreshPolicy.configure { store.refresh(budgetID: budget.id) }
            refreshPolicy.setVisible(true)
        }
        .onDisappear { refreshPolicy.setVisible(false) }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { refreshPolicy.sceneBecameActive() }
        }
        .sheet(isPresented: $showEditForm) {
            BudgetFormView(existing: budget) {
                dismiss()
            }
        }
        .sheet(item: $transactionToEdit) { transaction in
            AddTransactionContainer(transaction: transaction, isNewTransaction: false)
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
        PlanCard(tint: accentColor) {
            HStack(spacing: 16) {
                PlanIconTile(systemImage: iconName, color: accentColor, size: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text(budget.displayName)
                        .appFont(.title2, weight: .bold)
                    if let state = store.state {
                        Text(PlanDisplayFormatting.range(state.range))
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(budget.periodType.displayName)
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private func statCard(_ state: PlanBudgetDetailState) -> some View {
        PlanCard {
            Text("plan.budget_progress".localized)
                .appFont(.headline, weight: .bold)

            if state.isUpcoming {
                Text("plan.starts_in_days".localized(with: state.daysUntilStart))
                    .appFont(.title3, weight: .bold)
                    .foregroundStyle(.blue)
                Text(PlanDisplayFormatting.range(state.range))
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
            } else if state.projection.isDeterminate {
                Text("plan.spent_of".localized(
                    with: state.projection.spent.formattedAmount(for: budget.currencyCode),
                    state.projection.limit.formattedAmount(for: budget.currencyCode)
                ))
                .appFont(.title2, weight: .bold)
                .monospacedDigit()

                PlanProgressBar(
                    progress: state.projection.progress,
                    color: state.projection.isOnTrack == false ? .red : accentColor
                )

                Text(PlanDisplayFormatting.percent(state.projection.progress))
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(state.projection.isOnTrack == false ? .red : accentColor)
                    .monospacedDigit()

                if state.isEnded {
                    Text(finalResult(state))
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(state.projection.overage > 0 ? .red : .green)
                } else {
                    HStack(spacing: 0) {
                        statColumn(
                            title: "plan.remaining".localized,
                            value: state.projection.remaining.formattedAmount(for: budget.currencyCode)
                        )
                        Divider().frame(height: 44)
                        statColumn(
                            title: "plan.left_per_day".localized,
                            value: leftPerDay(state).formattedAmount(for: budget.currencyCode)
                        )
                    }
                }
            } else {
                Text(state.projection.spent.formattedAmount(for: budget.currencyCode))
                    .appFont(.title2, weight: .bold)
                    .monospacedDigit()
                PlanProgressBar(
                    progress: state.projection.progress,
                    color: .orange,
                    isDeterminate: false
                )
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

    private func leftPerDay(_ state: PlanBudgetDetailState) -> Decimal {
        guard state.daysLeftIncludingToday > 0 else { return 0 }
        return state.projection.remaining / Decimal(state.daysLeftIncludingToday)
    }

    private func finalResult(_ state: PlanBudgetDetailState) -> String {
        if state.projection.overage > 0 {
            return "plan.over_by".localized(
                with: state.projection.overage.formattedAmount(for: budget.currencyCode)
            )
        }
        return "plan.under_by".localized(
            with: state.projection.remaining.formattedAmount(for: budget.currencyCode)
        )
    }

    private func trendCard(_ state: PlanBudgetDetailState) -> some View {
        PlanCard {
            Text("plan.spending_trend".localized)
                .appFont(.headline, weight: .bold)

            Chart {
                ForEach(state.trend.points) { point in
                    let value = MoneyMinorUnitConverter.toMinorUnits(
                        point.cumulativeSpent,
                        currencyCode: budget.currencyCode
                    )
                    AreaMark(
                        x: .value("plan.date".localized, point.date),
                        y: .value("plan.spent".localized, value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accentColor.opacity(0.28), accentColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("plan.date".localized, point.date),
                        y: .value("plan.spent".localized, value)
                    )
                    .foregroundStyle(accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
                }

                RuleMark(y: .value(
                    "plan.limit".localized,
                    MoneyMinorUnitConverter.toMinorUnits(state.projection.limit, currencyCode: budget.currencyCode)
                ))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("plan.limit".localized)
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let minor = value.as(Int64.self) {
                            Text(MoneyMinorUnitConverter.fromMinorUnits(minor, currencyCode: budget.currencyCode)
                                .formattedAmountShort(for: budget.currencyCode))
                                .appFont(.caption2)
                        }
                    }
                }
            }
            .frame(height: 220)

            if !state.trend.isDeterminate { PlanPartialDataLabel() }
        }
    }

    private func recentTransactionsCard(_ state: PlanBudgetDetailState) -> some View {
        PlanCard(spacing: 10) {
            HStack {
                Text("plan.recent_transactions".localized)
                    .appFont(.headline, weight: .bold)
                Spacer()
                if !store.recentTransactions.isEmpty {
                    NavigationLink {
                        FilteredTransactionsDetailView(config: seeAllConfig(state))
                    } label: {
                        Text("common.seeAll".localized)
                            .appFont(.subheadline, weight: .semibold)
                    }
                }
            }

            if store.recentTransactions.isEmpty {
                Text("plan.no_budget_transactions".localized)
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                ForEach(store.recentTransactions) { transaction in
                    Button {
                        transactionToEdit = transaction
                    } label: {
                        TransactionRowView(transaction: transaction)
                    }
                    .buttonStyle(.plain)
                    if transaction.id != store.recentTransactions.last?.id {
                        Divider().padding(.leading, 46)
                    }
                }
            }
        }
    }

    private func seeAllConfig(_ state: PlanBudgetDetailState) -> TransactionFilterConfig {
        TransactionFilterConfig(
            title: budget.displayName,
            startDate: state.range.start,
            endDate: state.range.end,
            categoryId: budget.trackedCategoryIds.count == 1 ? budget.trackedCategoryIds.first : nil,
            categoryName: budget.trackedCategoryInfos.count == 1 ? budget.trackedCategoryInfos.first?.name : nil,
            categoryIcon: budget.trackedCategoryInfos.count == 1 ? budget.trackedCategoryInfos.first?.icon : nil,
            categoryColorHex: budget.trackedCategoryInfos.count == 1 ? budget.trackedCategoryInfos.first?.colorHex : nil,
            transactionType: .expense,
            dateRangeDescription: PlanDisplayFormatting.range(state.range),
            categoryIds: budget.targetKind == .categories ? budget.trackedCategoryIds : nil,
            categoryInfos: budget.targetKind == .categories ? budget.trackedCategoryInfos : nil,
            reportExclusionPolicy: .exclude,
            archivedWalletPolicy: .include,
            summaryCurrencyCode: budget.currencyCode,
            conversionPolicy: .rateChecked,
            budgetRelevancePolicy: .sharedPredicate
        )
    }
}

#Preview {
    let budget = Budget(name: "Food", amountLimit: 500, currencyCode: "USD", periodType: .monthly)
    NavigationStack { BudgetDetailView(budget: budget) }
        .modelContainer(for: [Budget.self, Transaction.self, Category.self, Wallet.self], inMemory: true)
}
