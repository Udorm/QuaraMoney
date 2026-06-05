import SwiftUI
import SwiftData
import Charts

// MARK: - Pro Analytics Dashboard

/// Advanced ("Pro") analytics dashboard. Entry point routed from `AnalysisView` via the
/// Basic/Pro toolbar toggle. Built entirely from native SwiftUI + Swift Charts components.
struct ProAnalyticsView: View {
    @Binding var proMode: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var vm = ProAnalyticsViewModel()

    @Query(filter: #Predicate<Wallet> { !$0.isArchived }, sort: \Wallet.name) private var wallets: [Wallet]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ProPeriodHeader(vm: vm)

                    ProOverviewCard(vm: vm)

                    ProCashFlowCard(vm: vm)

                    ProNetTrendCard(vm: vm)

                    ProCategoryCard(vm: vm)

                    ProPatternsCard(vm: vm)

                    if vm.grouping != .hour {
                        ProHeatmapCard(vm: vm)
                    }

                    if !vm.result.merchants.isEmpty {
                        ProMerchantsCard(vm: vm)
                    }

                    ProInsightsCard(vm: vm)
                }
                .padding(.vertical)
                .animation(.easeInOut(duration: 0.25), value: vm.currentReferenceDate)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    AnalyticsModePicker(proMode: $proMode)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ProAnalysisFilterButton(vm: vm, wallets: wallets)
                }
            }
            .onAppear {
                vm.configure(modelContext: modelContext)
                vm.refreshData()
            }
        }
    }
}

// MARK: - Reusable Card Container

/// Standard grouped card matching the app's analytics surfaces.
struct ProCard<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

/// Title + optional subtitle header used inside cards.
struct ProSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(.headline)
                if let subtitle {
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Period Header

struct ProPeriodHeader: View {
    @Bindable var vm: ProAnalyticsViewModel

    var body: some View {
        VStack(spacing: 14) {
            Picker("analysis.timePeriod".localized, selection: $vm.selectedPeriod) {
                Text("analysis.period.w".localized).tag(AnalysisPeriod.week)
                Text("analysis.period.m".localized).tag(AnalysisPeriod.month)
                Text("analysis.period.6m".localized).tag(AnalysisPeriod.sixMonths)
                Text("analysis.period.y".localized).tag(AnalysisPeriod.year)
            }
            .pickerStyle(.segmented)

            HStack {
                Button {
                    vm.navigateBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .appFont(.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 32)
                }

                Spacer()

                Text(vm.selectedPeriod.description(
                    referenceDate: vm.currentReferenceDate,
                    customStart: vm.customStartDate,
                    customEnd: vm.customEndDate
                ))
                .appFont(.subheadline, weight: .semibold)
                .multilineTextAlignment(.center)

                Spacer()

                Button {
                    vm.navigateForward()
                } label: {
                    Image(systemName: "chevron.right")
                        .appFont(.headline)
                        .foregroundStyle(vm.canNavigateForward ? .secondary : Color(.tertiaryLabel))
                        .frame(width: 44, height: 32)
                }
                .disabled(!vm.canNavigateForward)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Overview Card

struct ProOverviewCard: View {
    @Bindable var vm: ProAnalyticsViewModel

    private var r: ProAnalyticsProcessor.Result { vm.result }
    private var currency: String { vm.preferredCurrency }

    private var savingsRate: Double {
        guard r.income > 0 else { return 0 }
        return (r.net / r.income).doubleValue
    }

    var body: some View {
        ProCard {
            // Net worth
            VStack(alignment: .leading, spacing: 4) {
                Text("analysis.pro.netWorth".localized.uppercased())
                    .appFont(.caption2, weight: .bold)
                    .foregroundStyle(.secondary)
                Text(r.netWorth.formattedAmount(for: currency))
                    .appFont(.largeTitle, weight: .bold)
                    .foregroundStyle(r.netWorth >= 0 ? .primary : ThemeManager.shared.expenseColor)
                    .contentTransition(.numericText())
            }

            Divider()

            // Income / Expense / Net with deltas
            HStack(alignment: .top, spacing: 0) {
                statColumn(
                    label: L10n.Transaction.TransactionType.income.uppercased(),
                    amount: r.income,
                    previous: r.prevIncome,
                    color: ThemeManager.shared.incomeColor,
                    higherIsBetter: true
                )
                Divider().frame(height: 44)
                statColumn(
                    label: "analysis.pro.expenses".localized.uppercased(),
                    amount: r.expense,
                    previous: r.prevExpense,
                    color: ThemeManager.shared.expenseColor,
                    higherIsBetter: false
                )
                Divider().frame(height: 44)
                statColumn(
                    label: "analysis.net".localized.uppercased(),
                    amount: r.net,
                    previous: r.prevNet,
                    color: r.net >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor,
                    higherIsBetter: true
                )
            }

            // Savings rate
            if r.income > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("analysis.pro.savingsRate".localized)
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(savingsRate.formatted(.percent.precision(.fractionLength(0))))
                            .appFont(.caption, weight: .bold)
                            .foregroundStyle(savingsRate >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemGray5))
                                .frame(height: 8)
                            Capsule()
                                .fill((savingsRate >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor).gradient)
                                .frame(width: geo.size.width * CGFloat(min(max(savingsRate, 0), 1)), height: 8)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }

    @ViewBuilder
    private func statColumn(label: String, amount: Decimal, previous: Decimal, color: Color, higherIsBetter: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .appFont(.caption2, weight: .semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(amount.formattedAmountShort(for: vm.preferredCurrency))
                .appFont(.subheadline, weight: .bold)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            DeltaBadge(current: amount, previous: previous, higherIsBetter: higherIsBetter)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

// MARK: - Delta Badge

/// Shows period-over-period change as a colored ▲/▼ percentage chip.
struct DeltaBadge: View {
    let current: Decimal
    let previous: Decimal
    /// When `true`, an increase is "good" (green); when `false`, an increase is "bad" (red).
    let higherIsBetter: Bool

    private var change: Double? {
        let prev = abs(previous.doubleValue)
        guard prev > 0.0001 else { return nil }
        return (current.doubleValue - previous.doubleValue) / prev
    }

    var body: some View {
        if let change {
            let isUp = change >= 0
            let isGood = (isUp == higherIsBetter)
            HStack(spacing: 2) {
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                Text(abs(change).formatted(.percent.precision(.fractionLength(0))))
            }
            .appFont(.caption2, weight: .semibold)
            .foregroundStyle(isGood ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor)
        } else if current > 0 {
            Text("analysis.pro.new".localized)
                .appFont(.caption2, weight: .semibold)
                .foregroundStyle(.secondary)
        } else {
            Text("—")
                .appFont(.caption2, weight: .semibold)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Insights Card

struct ProInsightsCard: View {
    @Bindable var vm: ProAnalyticsViewModel

    private struct Insight: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let text: String
    }

    private var insights: [Insight] {
        let r = vm.result
        let currency = vm.preferredCurrency
        var items: [Insight] = []

        // 1. Spending vs previous period
        if r.prevExpense > 0 {
            let change = (r.expense.doubleValue - r.prevExpense.doubleValue) / r.prevExpense.doubleValue
            let pct = abs(change).formatted(.percent.precision(.fractionLength(0)))
            if change > 0.01 {
                items.append(Insight(icon: "arrow.up.right.circle.fill", tint: ThemeManager.shared.expenseColor,
                                     text: "analysis.pro.insight.spentMore".localized(with: pct)))
            } else if change < -0.01 {
                items.append(Insight(icon: "arrow.down.right.circle.fill", tint: ThemeManager.shared.incomeColor,
                                     text: "analysis.pro.insight.spentLess".localized(with: pct)))
            }
        }

        // 2. Top category
        if let top = r.categories.first, top.amount > 0 {
            let pct = top.fraction.formatted(.percent.precision(.fractionLength(0)))
            items.append(Insight(icon: "chart.pie.fill", tint: Color(hex: top.colorHex) ?? .blue,
                                 text: "analysis.pro.insight.topCategory".localized(with: top.name, pct)))
        }

        // 3. Savings outcome
        if r.income > 0 {
            if r.net >= 0 {
                let rate = (r.net / r.income).doubleValue.formatted(.percent.precision(.fractionLength(0)))
                items.append(Insight(icon: "banknote.fill", tint: ThemeManager.shared.incomeColor,
                                     text: "analysis.pro.insight.saved".localized(with: rate)))
            } else {
                items.append(Insight(icon: "exclamationmark.triangle.fill", tint: ThemeManager.shared.expenseColor,
                                     text: "analysis.pro.insight.overspent".localized))
            }
        }

        // 4. Busiest weekday
        if let busiest = r.weekdayTotals.filter({ $0.total > 0 }).max(by: { $0.total < $1.total }) {
            let name = ProDateFormatters.weekdaySymbol(busiest.weekday)
            items.append(Insight(icon: "calendar", tint: .orange,
                                 text: "analysis.pro.insight.busiestDay".localized(with: name)))
        }

        // 5. Projection
        if let projected = r.projectedTotal, projected > 0 {
            items.append(Insight(icon: "chart.line.uptrend.xyaxis", tint: .purple,
                                 text: "analysis.pro.insight.projection".localized(with: projected.formattedAmount(for: currency))))
        }

        // 6. Top place
        if let place = r.merchants.first {
            items.append(Insight(icon: "mappin.circle.fill", tint: .pink,
                                 text: "analysis.pro.insight.topPlace".localized(with: place.name, place.amount.formattedAmount(for: currency))))
        }

        return Array(items.prefix(5))
    }

    var body: some View {
        ProCard {
            ProSectionHeader(title: "analysis.pro.insights".localized, systemImage: "sparkles")

            if insights.isEmpty {
                Text("analysis.pro.insights.empty".localized)
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 12) {
                    ForEach(insights) { insight in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: insight.icon)
                                .appFont(.body)
                                .foregroundStyle(insight.tint)
                                .frame(width: 24)
                            Text(insight.text)
                                .appFont(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: - Filter Button

/// Pro dashboard filter: wallet + transaction type (period is controlled by the header picker).
struct ProAnalysisFilterButton: View {
    @Bindable var vm: ProAnalyticsViewModel
    var wallets: [Wallet]

    @State private var pendingTransactionType: TransactionTypeFilter = .expense

    var body: some View {
        FilterSheetButton(
            selectedPeriod: $vm.selectedPeriod,
            selectedWallet: $vm.selectedWallet,
            customStartDate: $vm.customStartDate,
            customEndDate: $vm.customEndDate,
            wallets: wallets,
            showPeriodFilter: false,
            onApply: {
                vm.selectedTransactionType = pendingTransactionType
            }
        ) {
            Section("analysis.transactionType".localized) {
                Picker("analysis.transactionType".localized, selection: $pendingTransactionType) {
                    Text(L10n.Transaction.TransactionType.expense).tag(TransactionTypeFilter.expense)
                    Text(L10n.Transaction.TransactionType.income).tag(TransactionTypeFilter.income)
                }
                .pickerStyle(.segmented)
            }
        }
        .onAppear { pendingTransactionType = vm.selectedTransactionType }
        .onChange(of: vm.selectedTransactionType) { _, newValue in
            pendingTransactionType = newValue
        }
    }
}

// MARK: - Chart Axis Helpers

extension TimeGrouping {
    /// Calendar component used as the Swift Charts `unit:` for binning marks.
    var chartComponent: Calendar.Component {
        switch self {
        case .hour: return .hour
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    /// Axis label format appropriate for the binning granularity.
    var axisFormat: Date.FormatStyle {
        switch self {
        case .hour: return .dateTime.hour()
        case .day: return .dateTime.day()
        case .week: return .dateTime.month(.abbreviated).day()
        case .month: return .dateTime.month(.narrow)
        case .year: return .dateTime.year()
        }
    }
}

enum ProDateFormatters {
    /// Localized standalone weekday symbol (1 = Sunday … 7 = Saturday).
    static func weekdaySymbol(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? []
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }
}

#Preview {
    ProAnalyticsView(proMode: .constant(true))
        .modelContainer(for: [Transaction.self, Wallet.self, Category.self, Budget.self], inMemory: true)
}
