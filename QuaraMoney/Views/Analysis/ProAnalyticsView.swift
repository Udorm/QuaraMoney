import SwiftUI
import SwiftData
import Charts

// MARK: - Pro Analytics Dashboard

/// Advanced ("Pro") analytics dashboard. Entry point routed from `AnalysisView` via the
/// Basic/Pro toolbar toggle. Built entirely from native SwiftUI + Swift Charts components.
struct ProAnalyticsView: View {
    @Binding var proMode: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var vm = ProAnalyticsViewModel()
    @State private var showFilterSheet = false
    @State private var showCustomizeSheet = false

    @Query(filter: #Predicate<Wallet> { !$0.isArchived }, sort: \Wallet.name) private var wallets: [Wallet]
    @Query(sort: \Category.name) private var categories: [Category]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ProActiveFiltersBar(vm: vm, wallets: wallets, categories: categories) {
                        showFilterSheet = true
                    }

                    // Regular width (iPad / large iPhone landscape): two-column masonry.
                    if horizontalSizeClass == .regular {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) {
                                ForEach(columnSections(0)) { sectionView($0) }
                            }
                            VStack(spacing: 16) {
                                ForEach(columnSections(1)) { sectionView($0) }
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: 16) {
                            ForEach(vm.layout.visibleSections) { sectionView($0) }
                        }
                        .padding(.horizontal)
                    }

                    if vm.layout.visibleSections.isEmpty {
                        ProAllHiddenPlaceholder { showCustomizeSheet = true }
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
                .animation(.easeInOut(duration: 0.25), value: vm.currentReferenceDate)
                .animation(.easeInOut(duration: 0.2), value: vm.layout)
            }
            // Floating Liquid Glass period controls — the navigation layer stays above the
            // content layer, which scrolls underneath.
            .safeAreaInset(edge: .top, spacing: 0) {
                ProPeriodHeader(vm: vm)
            }
            .navigationDestination(for: ProDashboardDetail.self) { detail in
                ProSectionDetailPage(detail: detail, vm: vm, wallets: wallets)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    AnalyticsModePicker(proMode: $proMode)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showCustomizeSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.app(.title3))
                    }
                    ProDashboardFilterButton(filter: vm.filter) {
                        showFilterSheet = true
                    }
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                ProDashboardFilterSheet(vm: vm, wallets: wallets, categories: categories)
            }
            .sheet(isPresented: $showCustomizeSheet) {
                ProCustomizeSheet(vm: vm)
            }
            .onAppear {
                vm.configure(modelContext: modelContext)
                vm.refreshData()
            }
        }
    }

    /// Sections assigned to one column of the two-column (regular width) layout,
    /// alternating in user order so both columns stay roughly balanced.
    private func columnSections(_ parity: Int) -> [DashboardSection] {
        vm.layout.visibleSections.enumerated()
            .filter { $0.offset % 2 == parity }
            .map(\.element)
    }

    /// Maps a configured section to its card, honoring runtime guards (heatmap needs day-or-coarser
    /// grouping; merchants only render when location data exists). Every section except the
    /// Overview hero renders as a Health-style summary card that pushes a full detail page.
    @ViewBuilder
    private func sectionView(_ section: DashboardSection) -> some View {
        switch section {
        case .overview:
            ProOverviewCard(vm: vm)
        case .budgets:
            if !vm.result.budgetStatuses.isEmpty {
                summaryLink(.budgets) { ProBudgetsSummaryCard(vm: vm) }
            }
        case .flow:
            summaryLink(.flow) { ProFlowSummaryCard(vm: vm) }
        case .categories:
            summaryLink(.categories) { ProCategoriesSummaryCard(vm: vm) }
        case .patterns:
            summaryLink(.patterns) { ProPatternsSummaryCard(vm: vm) }
        case .heatmap:
            if vm.grouping != .hour {
                summaryLink(.heatmap) { ProHeatmapSummaryCard(vm: vm) }
            }
        case .merchants:
            if !vm.result.merchants.isEmpty {
                summaryLink(.merchants) { ProMerchantsSummaryCard(vm: vm) }
            }
        case .largest:
            if !vm.result.largestTransactions.isEmpty {
                summaryLink(.largest) { ProLargestSummaryCard(vm: vm) }
            }
        case .insights:
            if !ProInsightsBuilder.build(from: vm.result, currency: vm.preferredCurrency).isEmpty {
                summaryLink(.insights) { ProInsightsSummaryCard(vm: vm) }
            }
        }
    }

    private func summaryLink<Card: View>(_ detail: ProDashboardDetail, @ViewBuilder card: () -> Card) -> some View {
        NavigationLink(value: detail) { card() }
            .buttonStyle(.plain)
    }
}

// MARK: - Detail Pages (Health-style drill-in for summary cards)

/// Navigation targets for the summary cards.
enum ProDashboardDetail: Hashable {
    case budgets
    case flow
    case categories
    case patterns
    case heatmap
    case merchants
    case largest
    case insights

    var title: String {
        switch self {
        case .budgets:    return "budget.title".localized
        case .flow:       return "analysis.pro.cashFlow".localized
        case .categories: return "analysis.pro.section.category".localized
        case .patterns:   return "analysis.pro.weekdayPattern".localized
        case .heatmap:    return "analysis.pro.heatmap".localized
        case .merchants:  return "analysis.pro.topPlaces".localized
        case .largest:    return "analysis.pro.largest".localized
        case .insights:   return "analysis.pro.insights".localized
        }
    }
}

/// Full-chart page pushed from a summary card. Shares the dashboard view model,
/// so period, filters, and interactivity all carry over.
struct ProSectionDetailPage: View {
    let detail: ProDashboardDetail
    var vm: ProAnalyticsViewModel
    var wallets: [Wallet] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(vm.filterDescription)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                switch detail {
                case .budgets:    ProBudgetsCard(vm: vm)
                case .flow:       ProFlowCard(vm: vm)
                case .categories: ProCategoriesCard(vm: vm, wallets: wallets)
                case .patterns:   ProPatternsCard(vm: vm)
                case .heatmap:    ProHeatmapCard(vm: vm)
                case .merchants:  ProMerchantsCard(vm: vm)
                case .largest:    ProLargestCard(vm: vm)
                case .insights:   ProInsightsCard(vm: vm)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(detail.title)
        .navigationBarTitleDisplayMode(.inline)
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
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
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

// MARK: - Period Header (floating Liquid Glass navigation layer)

struct ProPeriodHeader: View {
    @Bindable var vm: ProAnalyticsViewModel

    var body: some View {
        VStack(spacing: 10) {
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
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(vm.selectedPeriod.description(
                    referenceDate: vm.currentReferenceDate,
                    customStart: vm.customStartDate,
                    customEnd: vm.customEndDate
                ))
                .appFont(.subheadline, weight: .semibold)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())

                Spacer()

                Button {
                    vm.navigateForward()
                } label: {
                    Image(systemName: "chevron.right")
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(vm.canNavigateForward ? .secondary : Color(.tertiaryLabel))
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!vm.canNavigateForward)
            }
            .glassEffect(.regular, in: Capsule())
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
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

// MARK: - Insights

struct ProInsight: Identifiable {
    let id = UUID()
    let icon: String
    let tint: Color
    let text: String
}

/// Builds the natural-language insight list from a processor result. Shared by the
/// dashboard summary card and the full insights card.
@MainActor
enum ProInsightsBuilder {
    static func build(from r: ProAnalyticsProcessor.Result, currency: String) -> [ProInsight] {
        var items: [ProInsight] = []

        // 1. Spending vs previous period
        if r.prevExpense > 0 {
            let change = (r.expense.doubleValue - r.prevExpense.doubleValue) / r.prevExpense.doubleValue
            let pct = abs(change).formatted(.percent.precision(.fractionLength(0)))
            if change > 0.01 {
                items.append(ProInsight(icon: "arrow.up.right.circle.fill", tint: ThemeManager.shared.expenseColor,
                                     text: "analysis.pro.insight.spentMore".localized(with: pct)))
            } else if change < -0.01 {
                items.append(ProInsight(icon: "arrow.down.right.circle.fill", tint: ThemeManager.shared.incomeColor,
                                     text: "analysis.pro.insight.spentLess".localized(with: pct)))
            }
        }

        // 2. Biggest category mover vs. previous period
        if let mover = r.categoryDeltas.first, mover.previous > 0, mover.current > 0 {
            let amount = abs(mover.change).formattedAmountShort(for: currency)
            if mover.change > 0 {
                items.append(ProInsight(icon: "arrow.up.forward.circle.fill", tint: .orange,
                                     text: "analysis.pro.insight.moverUp".localized(with: mover.name, amount)))
            } else {
                items.append(ProInsight(icon: "arrow.down.forward.circle.fill", tint: .teal,
                                     text: "analysis.pro.insight.moverDown".localized(with: mover.name, amount)))
            }
        }

        // 3. Top category
        if let top = r.categories.first, top.amount > 0 {
            let pct = top.fraction.formatted(.percent.precision(.fractionLength(0)))
            items.append(ProInsight(icon: "chart.pie.fill", tint: Color(hex: top.colorHex) ?? .blue,
                                 text: "analysis.pro.insight.topCategory".localized(with: top.name, pct)))
        }

        // 3. Savings outcome
        if r.income > 0 {
            if r.net >= 0 {
                let rate = (r.net / r.income).doubleValue.formatted(.percent.precision(.fractionLength(0)))
                items.append(ProInsight(icon: "banknote.fill", tint: ThemeManager.shared.incomeColor,
                                     text: "analysis.pro.insight.saved".localized(with: rate)))
            } else {
                items.append(ProInsight(icon: "exclamationmark.triangle.fill", tint: ThemeManager.shared.expenseColor,
                                     text: "analysis.pro.insight.overspent".localized))
            }
        }

        // 4. Busiest weekday
        if let busiest = r.weekdayTotals.filter({ $0.total > 0 }).max(by: { $0.total < $1.total }) {
            let name = ProDateFormatters.weekdaySymbol(busiest.weekday)
            items.append(ProInsight(icon: "calendar", tint: .orange,
                                 text: "analysis.pro.insight.busiestDay".localized(with: name)))
        }

        // 5. Projection
        if let projected = r.projectedTotal, projected > 0 {
            items.append(ProInsight(icon: "chart.line.uptrend.xyaxis", tint: .purple,
                                 text: "analysis.pro.insight.projection".localized(with: projected.formattedAmount(for: currency))))
        }

        // 6. Top place
        if let place = r.merchants.first {
            items.append(ProInsight(icon: "mappin.circle.fill", tint: .pink,
                                 text: "analysis.pro.insight.topPlace".localized(with: place.name, place.amount.formattedAmount(for: currency))))
        }

        return Array(items.prefix(5))
    }
}

// MARK: - Insights Card (full list, shown on the detail page)

struct ProInsightsCard: View {
    @Bindable var vm: ProAnalyticsViewModel

    private var insights: [ProInsight] {
        ProInsightsBuilder.build(from: vm.result, currency: vm.preferredCurrency)
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

// MARK: - Filter Button (toolbar)

/// Toolbar filter button with a count badge reflecting how many constraints are active.
struct ProDashboardFilterButton: View {
    let filter: DashboardFilter
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .symbolVariant(filter.hasActiveConstraints ? .fill : .none)
                    .font(.app(.title3))
                    .foregroundStyle(filter.hasActiveConstraints ? Color.accentColor : .primary)

                if filter.activeConstraintCount > 0 {
                    Text("\(filter.activeConstraintCount)")
                        .appFont(.caption2, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Circle().fill(Color.red))
                        .offset(x: 7, y: -7)
                }
            }
        }
    }
}

// MARK: - Active Filters Chip Bar

/// Horizontally scrollable, tappable summary of every active filter. Tapping a chip removes
/// that constraint; the leading "Filters" chip opens the full sheet.
struct ProActiveFiltersBar: View {
    @Bindable var vm: ProAnalyticsViewModel
    var wallets: [Wallet]
    var categories: [Category]
    var openFilters: () -> Void

    private var typeLabel: String {
        vm.filter.transactionType == .income
            ? L10n.Transaction.TransactionType.income
            : L10n.Transaction.TransactionType.expense
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Type toggle chip — always present, taps cycle expense ⇄ income.
                Chip(
                    systemImage: vm.filter.transactionType == .income ? "arrow.down.left" : "arrow.up.right",
                    text: typeLabel,
                    tint: vm.filter.transactionType == .income ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor,
                    style: .solid
                ) {
                    vm.filter.transactionType = vm.filter.transactionType == .income ? .expense : .income
                }

                // Wallet chips (iterate the sorted query for stable order)
                ForEach(wallets.filter { vm.filter.walletIds.contains($0.id) }) { wallet in
                    Chip(systemImage: wallet.icon.isEmpty ? "creditcard" : wallet.icon, text: wallet.name, removable: true) {
                        vm.filter.walletIds.remove(wallet.id)
                    }
                }

                // Category chips
                ForEach(categories.filter { vm.filter.categoryIds.contains($0.id) }) { category in
                    Chip(systemImage: category.icon.isEmpty ? "tag" : category.icon, text: category.name, removable: true) {
                        vm.filter.categoryIds.remove(category.id)
                    }
                }

                // Amount range chip
                if vm.filter.minAmount != nil || vm.filter.maxAmount != nil {
                    Chip(systemImage: "dollarsign.circle", text: amountRangeText, removable: true) {
                        vm.filter.minAmount = nil
                        vm.filter.maxAmount = nil
                    }
                }

                // Include-excluded chip
                if vm.filter.includeExcluded {
                    Chip(systemImage: "eye", text: "analysis.pro.filter.includeExcluded".localized, removable: true) {
                        vm.filter.includeExcluded = false
                    }
                }

                // Clear-all chip
                if vm.filter.hasActiveConstraints {
                    Chip(systemImage: "xmark.circle.fill", text: "analysis.pro.filter.clearAll".localized, tint: .secondary, style: .tinted) {
                        vm.filter.clearConstraints()
                    }
                }

                // Add-filter chip
                Chip(systemImage: "plus", text: "analysis.pro.filter.add".localized, tint: .accentColor, style: .tinted, action: openFilters)
            }
            .padding(.horizontal)
        }
    }

    private var amountRangeText: String {
        let currency = vm.preferredCurrency
        switch (vm.filter.minAmount, vm.filter.maxAmount) {
        case let (min?, max?):
            return "\(min.formattedAmountShort(for: currency)) – \(max.formattedAmountShort(for: currency))"
        case let (min?, nil):
            return "≥ \(min.formattedAmountShort(for: currency))"
        case let (nil, max?):
            return "≤ \(max.formattedAmountShort(for: currency))"
        default:
            return ""
        }
    }

    /// Small pill used in the filter bar.
    private struct Chip: View {
        enum Style { case solid, tinted, outline }
        let systemImage: String
        let text: String
        var tint: Color = .accentColor
        var removable: Bool = false
        var style: Style = .outline
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 5) {
                    Image(systemName: systemImage)
                        .appFont(.caption2, weight: .semibold)
                    Text(text)
                        .appFont(.caption, weight: .medium)
                        .lineLimit(1)
                    if removable {
                        Image(systemName: "xmark")
                            .appFont(.caption2, weight: .bold)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(background)
                .foregroundStyle(foreground)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(style == .outline ? Color(.separator) : .clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }

        @ViewBuilder private var background: some View {
            switch style {
            case .solid:   tint
            case .tinted:  tint.opacity(0.15)
            case .outline: Color(.secondarySystemGroupedBackground)
            }
        }

        private var foreground: Color {
            switch style {
            case .solid:   return .white
            case .tinted:  return tint
            case .outline: return .primary
            }
        }
    }
}

// MARK: - All-Hidden Placeholder

struct ProAllHiddenPlaceholder: View {
    let onCustomize: () -> Void

    var body: some View {
        ProCard {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.3x3.fill")
                    .appFont(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("analysis.pro.allHidden.title".localized)
                    .appFont(.headline)
                Text("analysis.pro.allHidden.message".localized)
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("analysis.pro.customize".localized, action: onCustomize)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
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

    /// Fuller date format for the scrub-selection callout, where space allows more context.
    var selectionFormat: Date.FormatStyle {
        switch self {
        case .hour: return .dateTime.hour()
        case .day: return .dateTime.weekday(.abbreviated).month(.abbreviated).day()
        case .week: return .dateTime.month(.abbreviated).day().year()
        case .month: return .dateTime.month(.wide).year()
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
