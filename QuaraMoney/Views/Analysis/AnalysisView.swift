import SwiftUI
import SwiftData
import Charts

struct AnalysisView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("analyticsProMode") private var proMode: Bool = false
    @State private var viewModel = AnalysisViewModel()

    var body: some View {
        // Route to the advanced dashboard when enabled. The gate is always unlocked today
        // but keeps a single choke point for a future paywall (see ProFeatureGate).
        if proMode && ProFeatureGate.isProUnlocked {
            ProAnalyticsView(proMode: $proMode)
        } else {
            AnalysisContentView(vm: viewModel, proMode: $proMode)
                .onAppear {
                    viewModel.configure(modelContext: modelContext)
                    // Visibility gating: refreshes on appear only when data
                    // changed while hidden (or on first load).
                    viewModel.setVisible(true)
                }
                .onDisappear { viewModel.setVisible(false) }
        }
    }
}

/// Segmented Basic ⇄ Pro switch shown in the Analysis nav bar. Shared by both modes.
struct AnalyticsModePicker: View {
    @Binding var proMode: Bool

    var body: some View {
        Picker("analysis.pro.mode".localized, selection: $proMode) {
            Text("analysis.pro.mode.basic".localized).tag(false)
            Text("analysis.pro.mode.pro".localized).tag(true)
        }
        .pickerStyle(.segmented)
        .frame(width: 170)
    }
}

struct AnalysisContentView: View {
    @Bindable var vm: AnalysisViewModel
    @Binding var proMode: Bool

    // For Wallet Filter - We need to query wallets.
    @Query(filter: #Predicate<Wallet> { !$0.isArchived && $0.deletedAt == nil }, sort: \Wallet.name) private var wallets: [Wallet]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Filter Description
                    Text(vm.filterDescription)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    // Charts (Now includes the Period Picker)
                    SpendingTrendChart(vm: vm)

                    if !vm.categoryStats.isEmpty {
                        CategoryBreakdownChart(vm: vm)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(L10n.Analysis.title)
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    AnalyticsModePicker(proMode: $proMode)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    AnalysisFilterButton(vm: vm, wallets: wallets)
                }
            }
        }
    }
    
    @ViewBuilder
    private func OverviewSection(vm: AnalysisViewModel) -> some View {
        VStack(spacing: 16) {
            FinancialSummaryCards(income: vm.totalIncome, expense: vm.totalExpense)
                .padding(.horizontal)
        }
    }
}


struct SpendingTrendChart: View {
    @Bindable var vm: AnalysisViewModel
    @State private var dragOffset: CGFloat = 0
    @State private var slideDirection: Int = 0 // -1 = left, 0 = none, 1 = right
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1a. Income/Expense toggle — the most common switch, kept one tap
            // away in the chart card instead of buried in the filter sheet.
            Picker("analysis.transactionType".localized, selection: $vm.selectedTransactionType) {
                Text(L10n.Transaction.TransactionType.expense).tag(TransactionTypeFilter.expense)
                Text(L10n.Transaction.TransactionType.income).tag(TransactionTypeFilter.income)
            }
            .pickerStyle(.segmented)

            // 1b. Period Segmented Control
            Picker(L10n.Filter.title, selection: $vm.selectedPeriod) {
                Text("analysis.period.w".localized).tag(AnalysisPeriod.week)
                Text("analysis.period.m".localized).tag(AnalysisPeriod.month)
                Text("analysis.period.6m".localized).tag(AnalysisPeriod.sixMonths)
                Text("analysis.period.y".localized).tag(AnalysisPeriod.year)
                Text("analysis.period.ly".localized).tag(AnalysisPeriod.lastYear)
            }
            .pickerStyle(.segmented)

            // 2. Header Stats with Navigation
            HStack {
                // Back Button
                Button {
                    slideDirection = 1
                    // Completion-based reset: a timer could desync from the
                    // animation if the user tapped again within 0.3 s.
                    withAnimation(.easeInOut(duration: 0.3)) {
                        vm.navigateBack()
                    } completion: {
                        slideDirection = 0
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .appFont(.title2)
                        .foregroundStyle(.secondary)
                }
                .disabled(vm.selectedPeriod == .custom)
                
                Spacer()
                
                VStack(spacing: 4) {
                    Text(vm.selectedTransactionType == .expense ? "analysis.totalSpending".localized : "analysis.totalIncome".localized)
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    let amount = vm.selectedTransactionType == .expense ? vm.totalExpense : vm.totalIncome
                    Text(amount.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                        .font(.app(.title, weight: .bold))
                        .foregroundStyle(Color.primary)
                    
                }
                
                Spacer()
                
                // Forward Button
                Button {
                    slideDirection = -1
                    withAnimation(.easeInOut(duration: 0.3)) {
                        vm.navigateForward()
                    } completion: {
                        slideDirection = 0
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .appFont(.title2)
                        .foregroundStyle(.secondary)
                }
                .disabled(vm.selectedPeriod == .custom)
            }
            .frame(height: 80)

            // 3. Chart with swipe navigation between periods
            chartContent
                .frame(height: 250)
                .contentShape(Rectangle())
                .offset(x: dragOffset)
                .opacity(1.0 - Double(abs(dragOffset)) / 300.0)
                .id(vm.currentReferenceDate) // Trigger transition on date change
                .transition(.asymmetric(
                    insertion: .move(edge: slideDirection >= 0 ? .leading : .trailing),
                    removal: .move(edge: slideDirection >= 0 ? .trailing : .leading)
                ))
                .animation(.easeInOut(duration: 0.3), value: vm.currentReferenceDate)
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            // Only track horizontal drags
                            if abs(value.translation.width) > abs(value.translation.height) {
                                dragOffset = value.translation.width * 0.5
                            }
                        }
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else {
                                withAnimation(.spring()) { dragOffset = 0 }
                                return
                            }
                            
                            if value.translation.width > 60 {
                                // Swipe right -> go back
                                slideDirection = 1
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    dragOffset = 0
                                    vm.navigateBack()
                                } completion: {
                                    slideDirection = 0
                                }
                            } else if value.translation.width < -60 {
                                // Swipe left -> go forward
                                slideDirection = -1
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    dragOffset = 0
                                    vm.navigateForward()
                                } completion: {
                                    slideDirection = 0
                                }
                            } else {
                                // Snap back
                                withAnimation(.spring()) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var chartContent: some View {
        if vm.dailyStats.isEmpty {
            AppEmptyStateView(
                "analysis.noData".localized,
                systemImage: "chart.bar",
                description: "analysis.noTransactionsForPeriod".localized
            )
        } else {
            Chart {
                ForEach(vm.dailyStats) { stat in
                    let amount = vm.selectedTransactionType == .expense ? stat.expense : stat.income
                    let color = vm.selectedTransactionType == .expense ? ThemeManager.shared.expenseColor : ThemeManager.shared.incomeColor
                    BarMark(
                        x: .value("Date", stat.date, unit: self.chartUnit),
                        y: .value("Amount", amount)
                    )
                    .foregroundStyle(color.gradient)
                    .cornerRadius(4)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: self.chartUnit, count: self.axisStrideCount)) { value in
                    AxisValueLabel(format: self.axisFormat, centered: true)
                        .font(.app(.caption2))
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.2))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.2))
                    AxisValueLabel()
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // Helpers
    
    var chartUnit: Calendar.Component {
        switch vm.grouping {
        case .hour: return .hour
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }
    
    var axisStrideCount: Int {
        // Customize stride based on the visible range (Period)
        switch vm.selectedPeriod {
        case .day: return 4 // Every 4 hours
        case .week: return 1 // Every day
        case .month: return 5 // Every 5 days
        case .sixMonths: return 1 // Every month
        case .year: return 1 // Every month
        case .lastYear: return 1
        case .custom: return 5
        }
    }
    
    var axisFormat: Date.FormatStyle {
        switch vm.selectedPeriod {
        case .day: return .dateTime.hour()
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day()
        case .sixMonths: return .dateTime.month(.abbreviated)
        case .year: return .dateTime.month(.abbreviated)
        case .lastYear: return .dateTime.month(.abbreviated)
        case .custom: return .dateTime.day().month()
        }
    }
    

}

struct CategoryBreakdownChart: View {
    var vm: AnalysisViewModel
    @State private var selectedStat: CategoryStat?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(vm.selectedTransactionType == .expense ? "analysis.topSpendingCategories".localized : "analysis.topIncomeCategories".localized)
                    .font(.app(.headline))
                
                Spacer()
                
            }
            
            // Totals hoisted out of the ForEach: computing `total` inside every
            // row was O(n²) Decimal addition per render.
            let maxAmount = vm.categoryStats.first?.amount ?? 1
            let total = vm.categoryStats.reduce(0) { $0 + $1.amount }
            let preferredCurrency = CurrencyManager.shared.preferredCurrencyCode

            LazyVStack(spacing: 0) {
                ForEach(vm.categoryStats) { stat in
                    Button {
                        selectedStat = stat
                    } label: {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: stat.icon.isEmpty ? "circle.fill" : stat.icon)
                                    .appFont(.title3)
                                    .foregroundStyle(Color(hex: stat.colorHex) ?? .blue)
                                    .frame(width: 30)

                                VStack(alignment: .leading) {
                                    Text(stat.name)
                                        .font(.app(.subheadline, weight: .medium))

                                    let ratio = maxAmount > 0 ? Double(truncating: stat.amount as NSNumber) / Double(truncating: maxAmount as NSNumber) : 0
                                    CategoryShareBar(
                                        ratio: ratio,
                                        tint: Color(hex: stat.colorHex) ?? .blue
                                    )
                                }

                                Spacer()

                                VStack(alignment: .trailing) {
                                    Text(stat.amount.formattedAmount(for: preferredCurrency))
                                        .font(.app(.callout))
                                        .monospacedDigit()

                                    let percent = total > 0 ? Double(truncating: stat.amount as NSNumber) / Double(truncating: total as NSNumber) : 0
                                    Text(percent.formatted(.percent.precision(.fractionLength(0))))
                                        .font(.app(.caption2))
                                        .foregroundStyle(.secondary)
                                }

                                Image(systemName: "chevron.right")
                                    .font(.app(.caption))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)

                            Divider()
                                .padding(.leading, 40)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
        .sheet(item: $selectedStat) { stat in
            NavigationStack {
                FilteredTransactionsDetailView(
                    config: TransactionFilterConfig(
                        title: stat.name,
                        startDate: vm.startDate,
                        endDate: vm.endDate,
                        walletId: vm.selectedWalletIds.count == 1 ? vm.selectedWalletIds.first : nil,
                        walletName: nil,
                        categoryId: stat.id,
                        categoryName: stat.name,
                        categoryIcon: stat.icon,
                        categoryColorHex: stat.colorHex,
                        transactionType: vm.selectedTransactionType,
                        dateRangeDescription: vm.filterDescription,
                        defaultSortOption: .highestAmount
                    )
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

/// Proportional share bar for category rows. Native linear ProgressView
/// instead of the previous per-row GeometryReader capsule (which forced an
/// extra layout pass for every row).
private struct CategoryShareBar: View {
    let ratio: Double
    let tint: Color

    var body: some View {
        ProgressView(value: max(0, min(1, ratio)))
            .progressViewStyle(.linear)
            .tint(tint)
            .scaleEffect(x: 1, y: 1.5, anchor: .center)
            .frame(height: 6)
    }
}

// MARK: - Analysis Filter Button (wallet filtering only)
//
// The income/expense toggle used to live here; it now sits in the chart card
// (SpendingTrendChart) since it's the most-used switch and deserves one tap.

private struct AnalysisFilterButton: View {
    @Bindable var vm: AnalysisViewModel
    var wallets: [Wallet]

    var body: some View {
        FilterSheetButton(
            selectedPeriod: $vm.selectedPeriod,
            selectedWalletIds: $vm.selectedWalletIds,
            customStartDate: $vm.customStartDate,
            customEndDate: $vm.customEndDate,
            wallets: wallets,
            showPeriodFilter: false
        ) {
            EmptyView()
        }
    }
}
