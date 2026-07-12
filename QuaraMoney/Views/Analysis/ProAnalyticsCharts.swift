import SwiftUI
import SwiftData
import Charts

// MARK: - Health-Style Metric Header

/// Apple Health-style card header: tinted title row, uppercase eyebrow caption,
/// large headline value, and the period below. The big number is the takeaway;
/// the chart underneath is the evidence.
struct ProMetricHeader: View {
    let title: String
    let systemImage: String
    let tint: Color
    let caption: String
    let value: String
    var valueColor: Color = .primary
    let period: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .appFont(.subheadline, weight: .semibold)
                Text(title)
                    .appFont(.subheadline, weight: .semibold)
                Spacer(minLength: 0)
            }
            .foregroundStyle(tint)
            .padding(.bottom, 6)

            Text(caption.uppercased())
                .appFont(.caption2, weight: .semibold)
                .foregroundStyle(.secondary)
            Text(value)
                .appFont(.title2, weight: .bold)
                .foregroundStyle(valueColor)
                .contentTransition(.numericText())
                .monospacedDigit()
            Text(period)
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Scrub Callout

/// The floating "lollipop" card shown above the selection rule while scrubbing a chart.
struct ProCallout<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) { content }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// One color-dotted label/value line inside a scrub callout.
private struct ProCalloutRow: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .appFont(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .appFont(.caption, weight: .semibold)
                .monospacedDigit()
        }
    }
}

// MARK: - Cash Flow (mirrored bars ⇄ cumulative net trend, scrubbable)

/// Merged cash-flow card. A top-right toggle switches between the mirrored
/// income/expense bars and the cumulative net trend line; the choice persists.
struct ProFlowCard: View {
    enum Style: String, CaseIterable {
        case bars
        case trend
    }

    var vm: ProAnalyticsViewModel
    @AppStorage("proFlowChartStyle.v1") private var style: Style = .bars
    @State private var rawSelection: Date?

    private var buckets: [ProAnalyticsProcessor.FlowBucket] { vm.result.flowBuckets }
    private var incomeLabel: String { L10n.Transaction.TransactionType.income }
    private var expenseLabel: String { L10n.Transaction.TransactionType.expense }

    private struct TrendPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let value: Double
    }

    private var trendPoints: [TrendPoint] {
        var running: Decimal = 0
        return buckets.map { bucket in
            running += bucket.net
            return TrendPoint(date: bucket.date, value: running.doubleValue)
        }
    }

    private var selectedBucket: ProAnalyticsProcessor.FlowBucket? {
        guard let rawSelection else { return nil }
        return buckets.min {
            abs($0.date.timeIntervalSince(rawSelection)) < abs($1.date.timeIntervalSince(rawSelection))
        }
    }

    private var selectedPoint: TrendPoint? {
        guard let rawSelection else { return nil }
        return trendPoints.min {
            abs($0.date.timeIntervalSince(rawSelection)) < abs($1.date.timeIntervalSince(rawSelection))
        }
    }

    private var net: Decimal { vm.result.net }
    private var netColor: Color {
        net >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }
    private var hasData: Bool {
        !buckets.allSatisfy { $0.income == 0 && $0.expense == 0 }
    }

    var body: some View {
        ProCard {
            HStack(alignment: .top, spacing: 8) {
                ProMetricHeader(
                    title: "analysis.pro.cashFlow".localized,
                    systemImage: "arrow.left.arrow.right",
                    tint: .teal,
                    caption: (style == .bars ? "analysis.pro.totalNet" : "analysis.pro.cumulative").localized,
                    value: signedAmount(net),
                    valueColor: netColor,
                    period: vm.periodDescription
                )
                .opacity(rawSelection == nil ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: rawSelection == nil)

                Picker("analysis.pro.cashFlow".localized, selection: $style) {
                    Image(systemName: "chart.bar.fill")
                        .accessibilityLabel("analysis.pro.cashFlow".localized)
                        .tag(Style.bars)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .accessibilityLabel("analysis.pro.netTrend".localized)
                        .tag(Style.trend)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 100)
            }

            if !hasData || (style == .trend && trendPoints.count < 2) {
                ProEmptyChart()
            } else if style == .bars {
                barsChart
            } else {
                trendChart
            }
        }
        .onChange(of: style) { _, _ in rawSelection = nil }
    }

    // MARK: Mirrored bars

    private var barsChart: some View {
        Chart {
            // Mirrored cash-flow bars: income grows up from zero, expenses grow down.
            // One x-slot per bucket keeps bars readable even at 30+ days.
            ForEach(buckets) { bucket in
                let dimmed = selectedBucket != nil && selectedBucket?.id != bucket.id

                BarMark(
                    x: .value("analysis.pro.period".localized, bucket.date, unit: vm.grouping.chartComponent),
                    y: .value("analysis.pro.amount".localized, bucket.income.doubleValue)
                )
                .foregroundStyle(by: .value("analysis.transactionType".localized, incomeLabel))
                .cornerRadius(3)
                .opacity(dimmed ? 0.3 : 1)

                BarMark(
                    x: .value("analysis.pro.period".localized, bucket.date, unit: vm.grouping.chartComponent),
                    y: .value("analysis.pro.amount".localized, -bucket.expense.doubleValue)
                )
                .foregroundStyle(by: .value("analysis.transactionType".localized, expenseLabel))
                .cornerRadius(3)
                .opacity(dimmed ? 0.3 : 1)
            }

            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color(.separator))
                .lineStyle(StrokeStyle(lineWidth: 1))

            if let sel = selectedBucket {
                RuleMark(x: .value("analysis.pro.period".localized, sel.date, unit: vm.grouping.chartComponent))
                    .foregroundStyle(Color(.systemGray3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .zIndex(-1)
                    .annotation(
                        position: .top,
                        spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        ProCallout {
                            Text(sel.date, format: vm.grouping.selectionFormat)
                                .appFont(.caption2, weight: .semibold)
                                .foregroundStyle(.secondary)
                            ProCalloutRow(color: ThemeManager.shared.incomeColor, label: incomeLabel,
                                          value: sel.income.formattedAmountShort(for: vm.preferredCurrency))
                            ProCalloutRow(color: ThemeManager.shared.expenseColor, label: expenseLabel,
                                          value: sel.expense.formattedAmountShort(for: vm.preferredCurrency))
                            ProCalloutRow(color: .secondary, label: "analysis.net".localized,
                                          value: signedAmount(sel.net, short: true))
                        }
                    }
            }
        }
        .chartXSelection(value: $rawSelection)
        .chartForegroundStyleScale(
            domain: [incomeLabel, expenseLabel],
            range: [ThemeManager.shared.incomeColor, ThemeManager.shared.expenseColor]
        )
        .chartLegend(position: .top, alignment: .leading, spacing: 8)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: vm.grouping.axisFormat)
                    .font(.app(.caption2))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        // Mirrored chart: the negative half is expenses, label it unsigned.
                        Text(abs(v).formattedAmountShort(for: vm.preferredCurrency))
                            .appFont(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 230)
    }

    // MARK: Cumulative trend

    private var trendColor: Color {
        (trendPoints.last?.value ?? 0) >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    private var trendChart: some View {
        Chart {
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color(.separator))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            ForEach(trendPoints) { point in
                AreaMark(
                    x: .value("analysis.pro.period".localized, point.date, unit: vm.grouping.chartComponent),
                    y: .value("analysis.net".localized, point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    .linearGradient(
                        colors: [trendColor.opacity(0.28), trendColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("analysis.pro.period".localized, point.date, unit: vm.grouping.chartComponent),
                    y: .value("analysis.net".localized, point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(trendColor)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }

            if let sel = selectedPoint {
                RuleMark(x: .value("analysis.pro.period".localized, sel.date, unit: vm.grouping.chartComponent))
                    .foregroundStyle(Color(.systemGray3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .zIndex(-1)
                    .annotation(
                        position: .top,
                        spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        ProCallout {
                            Text(sel.date, format: vm.grouping.selectionFormat)
                                .appFont(.caption2, weight: .semibold)
                                .foregroundStyle(.secondary)
                            Text(signedAmount(Decimal(sel.value)))
                                .appFont(.subheadline, weight: .bold)
                                .foregroundStyle(sel.value >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor)
                                .monospacedDigit()
                        }
                    }

                PointMark(
                    x: .value("analysis.pro.period".localized, sel.date, unit: vm.grouping.chartComponent),
                    y: .value("analysis.net".localized, sel.value)
                )
                .foregroundStyle(trendColor)
                .symbolSize(90)
            } else if let last = trendPoints.last {
                PointMark(
                    x: .value("analysis.pro.period".localized, last.date, unit: vm.grouping.chartComponent),
                    y: .value("analysis.net".localized, last.value)
                )
                .foregroundStyle(trendColor)
                .symbolSize(60)
            }
        }
        .chartXSelection(value: $rawSelection)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: vm.grouping.axisFormat)
                    .font(.app(.caption2))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v.formattedAmountShort(for: vm.preferredCurrency))
                            .appFont(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 230)
    }

    private func signedAmount(_ amount: Decimal, short: Bool = false) -> String {
        let formatted = short
            ? amount.formattedAmountShort(for: vm.preferredCurrency)
            : amount.formattedAmount(for: vm.preferredCurrency)
        return amount > 0 ? "+\(formatted)" : formatted
    }
}

// MARK: - Categories (breakdown donut ⇄ top movers, drill-down)

/// Merged category card. A top-right toggle switches between the share-of-total
/// donut breakdown and the period-over-period Top Movers list.
struct ProCategoriesCard: View {
    enum Style: String, CaseIterable {
        case breakdown
        case movers
    }

    var vm: ProAnalyticsViewModel
    var wallets: [Wallet] = []
    @AppStorage("proCategoryChartStyle.v1") private var style: Style = .breakdown
    @State private var selected: SelectedCategory?
    @State private var selectedAngle: Double?

    /// Unified drill-down target for both the breakdown legend and the movers list.
    struct SelectedCategory: Identifiable {
        let id: UUID
        let name: String
        let icon: String
        let colorHex: String
    }

    /// Name of the single selected wallet, when exactly one is active (for drill-down titles).
    private var singleWalletName: String? {
        guard let id = vm.singleSelectedWalletId else { return nil }
        return wallets.first { $0.id == id }?.name
    }

    private var categories: [ProAnalyticsProcessor.CategorySlice] { vm.result.categories }
    private var movers: [ProAnalyticsProcessor.CategoryDelta] { Array(vm.result.categoryDeltas.prefix(6)) }
    private var total: Decimal { categories.reduce(0) { $0 + $1.amount } }

    private var titleKey: String {
        if style == .movers { return "analysis.pro.movers" }
        return vm.selectedTransactionType == .expense ? "analysis.topSpendingCategories" : "analysis.topIncomeCategories"
    }

    private var subtitle: String? {
        style == .movers ? "analysis.pro.movers.subtitle".localized : nil
    }

    var body: some View {
        ProCard {
            HStack(alignment: .top, spacing: 8) {
                ProSectionHeader(title: titleKey.localized, subtitle: subtitle, systemImage: "chart.pie.fill")

                Picker("analysis.pro.section.category".localized, selection: $style) {
                    Image(systemName: "chart.pie.fill")
                        .accessibilityLabel("analysis.pro.section.category".localized)
                        .tag(Style.breakdown)
                    Image(systemName: "arrow.up.arrow.down")
                        .accessibilityLabel("analysis.pro.movers".localized)
                        .tag(Style.movers)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 100)
            }

            switch style {
            case .breakdown:
                if categories.isEmpty {
                    ProEmptyChart()
                } else {
                    ZStack {
                        donut
                        centerLabel
                    }

                    VStack(spacing: 0) {
                        ForEach(categories) { stat in
                            Button {
                                selected = SelectedCategory(id: stat.id, name: stat.name, icon: stat.icon, colorHex: stat.colorHex)
                            } label: {
                                categoryRow(stat)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            case .movers:
                if movers.isEmpty {
                    ProEmptyChart()
                } else {
                    moversChart

                    VStack(spacing: 0) {
                        ForEach(movers) { delta in
                            Button {
                                selected = SelectedCategory(id: delta.id, name: delta.name, icon: delta.icon, colorHex: delta.colorHex)
                            } label: {
                                moverRow(delta)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onChange(of: style) { _, _ in selectedAngle = nil }
        .sheet(item: $selected) { category in
            NavigationStack {
                FilteredTransactionsDetailView(
                    config: TransactionFilterConfig(
                        title: category.name,
                        startDate: vm.startDate,
                        endDate: vm.endDate,
                        walletId: vm.singleSelectedWalletId,
                        walletName: singleWalletName,
                        categoryId: category.id,
                        categoryName: category.name,
                        categoryIcon: category.icon,
                        categoryColorHex: category.colorHex,
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

    // MARK: Donut

    private struct DonutSlice: Identifiable {
        var id: String { name }
        let name: String
        let amount: Decimal
        let color: Color
    }

    /// Top slices rendered individually; the remainder collapses into one "Other" sector.
    private var donutSlices: [DonutSlice] {
        let top = categories.prefix(8)
        var slices = top.map { DonutSlice(name: $0.name, amount: $0.amount, color: Color(hex: $0.colorHex) ?? .blue) }
        let otherAmount = categories.dropFirst(8).reduce(Decimal.zero) { $0 + $1.amount }
        if otherAmount > 0 {
            slices.append(DonutSlice(name: "analysis.pro.other".localized, amount: otherAmount, color: Color(.systemGray3)))
        }
        return slices
    }

    /// Maps the touched angle-domain value back to the sector under the finger.
    private var angleSelectedSlice: DonutSlice? {
        guard let selectedAngle else { return nil }
        var cumulative = 0.0
        for slice in donutSlices {
            cumulative += slice.amount.doubleValue
            if selectedAngle <= cumulative { return slice }
        }
        return nil
    }

    private var donut: some View {
        Chart {
            ForEach(donutSlices) { slice in
                let isSelected = angleSelectedSlice?.name == slice.name
                SectorMark(
                    angle: .value("analysis.pro.amount".localized, slice.amount.doubleValue),
                    innerRadius: .ratio(0.62),
                    outerRadius: isSelected ? .ratio(1.0) : .ratio(0.94),
                    angularInset: 1.5
                )
                .foregroundStyle(slice.color)
                .cornerRadius(4)
                .opacity(angleSelectedSlice == nil || isSelected ? 1 : 0.35)
            }
        }
        .chartAngleSelection(value: $selectedAngle)
        .frame(height: 210)
        .animation(.easeInOut(duration: 0.15), value: angleSelectedSlice?.name)
    }

    @ViewBuilder
    private var centerLabel: some View {
        if let slice = angleSelectedSlice {
            VStack(spacing: 2) {
                Text(slice.name)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(slice.amount.formattedAmountShort(for: vm.preferredCurrency))
                    .appFont(.title2, weight: .bold)
                    .contentTransition(.numericText())
                if total > 0 {
                    Text((slice.amount / total).doubleValue.formatted(.percent.precision(.fractionLength(0))))
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 120)
        } else {
            VStack(spacing: 2) {
                Text("analysis.total".localized.uppercased())
                    .appFont(.caption2, weight: .semibold)
                    .foregroundStyle(.secondary)
                Text(total.formattedAmountShort(for: vm.preferredCurrency))
                    .appFont(.title2, weight: .bold)
                    .contentTransition(.numericText())
            }
        }
    }

    @ViewBuilder
    private func categoryRow(_ stat: ProAnalyticsProcessor.CategorySlice) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: stat.icon.isEmpty ? "circle.fill" : stat.icon)
                    .appFont(.title3)
                    .foregroundStyle(Color(hex: stat.colorHex) ?? .blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 5) {
                    Text(stat.name)
                        .appFont(.subheadline, weight: .medium)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemGray5)).frame(height: 6)
                            Capsule().fill((Color(hex: stat.colorHex) ?? .blue))
                                .frame(width: geo.size.width * CGFloat(stat.fraction), height: 6)
                        }
                    }
                    .frame(height: 6)
                }

                VStack(alignment: .trailing, spacing: 2) {
                    Text(stat.amount.formattedAmount(for: vm.preferredCurrency))
                        .appFont(.callout)
                        .monospacedDigit()
                    Text(stat.fraction.formatted(.percent.precision(.fractionLength(0))))
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .appFont(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)

            if stat.id != categories.last?.id {
                Divider().padding(.leading, 40)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: Movers

    /// For expenses, spending less is good; for income, earning more is good.
    private func isGood(_ delta: ProAnalyticsProcessor.CategoryDelta) -> Bool {
        vm.selectedTransactionType == .income ? delta.change > 0 : delta.change < 0
    }

    /// Dumbbell ("before → after") chart: per category, a gray dot marks last period's
    /// total, a colored dot marks this period's, and the connecting segment — colored by
    /// whether the move is good or bad — *is* the change. Shows both reference values,
    /// which the rows below only state as text.
    private var moversChart: some View {
        let maxValue = movers.map { max($0.current, $0.previous) }.max() ?? 0
        let domainMax = max(maxValue.doubleValue * 1.08, 1)

        return VStack(alignment: .leading, spacing: 8) {
            // Manual legend: previous (gray) → current (filled).
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    Circle().fill(Color(.systemGray3)).frame(width: 8, height: 8)
                    Text("analysis.pro.lastPeriod".localized)
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 5) {
                    Circle().fill(Color.primary).frame(width: 8, height: 8)
                    Text("analysis.pro.thisPeriod".localized)
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Chart {
                ForEach(movers) { delta in
                    let color = isGood(delta) ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor

                    RuleMark(
                        xStart: .value("analysis.pro.lastPeriod".localized, delta.previous.doubleValue),
                        xEnd: .value("analysis.pro.thisPeriod".localized, delta.current.doubleValue),
                        y: .value("analysis.pro.section.category".localized, delta.name)
                    )
                    .foregroundStyle(color.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))

                    PointMark(
                        x: .value("analysis.pro.lastPeriod".localized, delta.previous.doubleValue),
                        y: .value("analysis.pro.section.category".localized, delta.name)
                    )
                    .foregroundStyle(Color(.systemGray3))
                    .symbolSize(70)

                    PointMark(
                        x: .value("analysis.pro.thisPeriod".localized, delta.current.doubleValue),
                        y: .value("analysis.pro.section.category".localized, delta.name)
                    )
                    .foregroundStyle(color)
                    .symbolSize(110)
                }
            }
            .chartXScale(domain: 0...domainMax)
            .chartYScale(domain: movers.map(\.name))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let name = value.as(String.self) {
                            Text(name)
                                .appFont(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: 76, alignment: .trailing)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v.formattedAmountShort(for: vm.preferredCurrency))
                                .appFont(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: CGFloat(movers.count) * 38)
        }
    }

    @ViewBuilder
    private func moverRow(_ delta: ProAnalyticsProcessor.CategoryDelta) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: delta.icon.isEmpty ? "circle.fill" : delta.icon)
                    .appFont(.title3)
                    .foregroundStyle(Color(hex: delta.colorHex) ?? .blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(delta.name)
                        .appFont(.subheadline, weight: .medium)
                        .lineLimit(1)
                    Text("analysis.pro.movers.was".localized(with: delta.previous.formattedAmountShort(for: vm.preferredCurrency)))
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: delta.change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .appFont(.caption2, weight: .bold)
                        Text(signedChange(delta.change))
                            .appFont(.subheadline, weight: .bold)
                            .monospacedDigit()
                    }
                    .foregroundStyle(isGood(delta) ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor)

                    Text(delta.current.formattedAmountShort(for: vm.preferredCurrency))
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Image(systemName: "chevron.right")
                    .appFont(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)

            if delta.id != movers.last?.id {
                Divider().padding(.leading, 40)
            }
        }
        .contentShape(Rectangle())
    }

    private func signedChange(_ change: Decimal) -> String {
        let formatted = abs(change).formattedAmountShort(for: vm.preferredCurrency)
        return change >= 0 ? "+\(formatted)" : "−\(formatted)"
    }
}

// MARK: - Budget Status (active budgets, own-period progress)

struct ProBudgetsCard: View {
    var vm: ProAnalyticsViewModel
    @State private var selected: ProAnalyticsProcessor.BudgetStatus?

    private var statuses: [ProAnalyticsProcessor.BudgetStatus] {
        Array(vm.result.budgetStatuses.prefix(6))
    }

    var body: some View {
        ProCard {
            ProSectionHeader(
                title: "budget.title".localized,
                subtitle: "analysis.pro.budgets.subtitle".localized,
                systemImage: "gauge.with.needle"
            )

            VStack(spacing: 0) {
                ForEach(statuses) { status in
                    Button {
                        selected = status
                    } label: {
                        budgetRow(status)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $selected) { status in
            NavigationStack {
                FilteredTransactionsDetailView(
                    config: TransactionFilterConfig(
                        title: status.name,
                        startDate: status.periodStart,
                        endDate: status.periodEnd,
                        transactionType: .expense,
                        dateRangeDescription: periodDescription(status),
                        categoryIds: status.categoryInfos.isEmpty ? nil : status.categoryInfos.map(\.id),
                        categoryInfos: status.categoryInfos.isEmpty ? nil : status.categoryInfos
                    )
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func budgetRow(_ status: ProAnalyticsProcessor.BudgetStatus) -> some View {
        let color = statusColor(status)
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(status.name)
                        .appFont(.subheadline, weight: .medium)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(status.fraction.formatted(.percent.precision(.fractionLength(0))))
                        .appFont(.caption, weight: .bold)
                        .foregroundStyle(color)
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .appFont(.caption)
                        .foregroundStyle(.tertiary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5)).frame(height: 8)
                        Capsule().fill(color.gradient)
                            .frame(width: geo.size.width * CGFloat(min(status.fraction, 1)), height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text(status.spent.formattedAmount(for: vm.preferredCurrency))
                        .appFont(.caption2, weight: .semibold)
                        .monospacedDigit()
                    Spacer()
                    Text(remainingText(status))
                        .appFont(.caption2)
                        .foregroundStyle(status.remaining >= 0 ? Color.secondary : ThemeManager.shared.expenseColor)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 8)

            if status.id != statuses.last?.id {
                Divider()
            }
        }
        .contentShape(Rectangle())
    }

    private func statusColor(_ status: ProAnalyticsProcessor.BudgetStatus) -> Color {
        if status.fraction >= 1 { return ThemeManager.shared.expenseColor }
        if status.fraction >= 0.8 { return .orange }
        return ThemeManager.shared.incomeColor
    }

    private func remainingText(_ status: ProAnalyticsProcessor.BudgetStatus) -> String {
        if status.remaining >= 0 {
            let remaining = status.remaining.formattedAmountShort(for: vm.preferredCurrency)
            let limit = status.limit.formattedAmountShort(for: vm.preferredCurrency)
            return "\(remaining) \("budget.leftOf".localized(with: limit))"
        }
        return "budget.overBy".localized(with: abs(status.remaining).formattedAmountShort(for: vm.preferredCurrency))
    }

    private func periodDescription(_ status: ProAnalyticsProcessor.BudgetStatus) -> String {
        let displayEnd = Calendar.current.date(byAdding: .day, value: -1, to: status.periodEnd) ?? status.periodEnd
        let start = status.periodStart.appFormatted(date: .abbreviated, time: .omitted)
        let end = displayEnd.appFormatted(date: .abbreviated, time: .omitted)
        return "\(start) – \(end)"
    }
}

// MARK: - Largest Transactions

struct ProLargestCard: View {
    var vm: ProAnalyticsViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var viewingTransaction: Transaction?

    private var highlights: [ProAnalyticsProcessor.TransactionHighlight] { vm.result.largestTransactions }
    private var amountColor: Color {
        vm.selectedTransactionType == .income ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    var body: some View {
        ProCard {
            ProSectionHeader(
                title: "analysis.pro.largest".localized,
                subtitle: "analysis.pro.largest.subtitle".localized,
                systemImage: "list.number"
            )

            if highlights.isEmpty {
                ProEmptyChart()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(highlights.enumerated()), id: \.element.id) { index, txn in
                        Button {
                            openTransaction(txn.id)
                        } label: {
                            highlightRow(index: index, txn: txn)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $viewingTransaction) { txn in
            AddTransactionContainer(transaction: txn, isNewTransaction: false)
        }
    }

    @ViewBuilder
    private func highlightRow(index: Int, txn: ProAnalyticsProcessor.TransactionHighlight) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .appFont(.subheadline, weight: .bold)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Image(systemName: (txn.categoryIcon?.isEmpty == false ? txn.categoryIcon! : "tag"))
                    .appFont(.title3)
                    .foregroundStyle(Color(hex: txn.categoryColorHex ?? "") ?? .blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(txn))
                        .appFont(.subheadline, weight: .medium)
                        .lineLimit(1)
                    Text(txn.date.formatted(.dateTime.month(.abbreviated).day().locale(.app)))
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(txn.amount.formattedAmount(for: vm.preferredCurrency))
                    .appFont(.callout, weight: .semibold)
                    .foregroundStyle(amountColor)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .appFont(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)

            if txn.id != highlights.last?.id {
                Divider().padding(.leading, 60)
            }
        }
        .contentShape(Rectangle())
    }

    /// Resolves the live model object for a highlight and opens the standard
    /// transaction sheet (same view/edit flow used by transaction lists).
    private func openTransaction(_ id: UUID) {
        var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id && $0.deletedAt == nil })
        descriptor.fetchLimit = 1
        viewingTransaction = (try? modelContext.fetch(descriptor))?.first
    }

    private func displayName(_ txn: ProAnalyticsProcessor.TransactionHighlight) -> String {
        if let note = txn.note, !note.trimmingCharacters(in: .whitespaces).isEmpty { return note }
        return txn.categoryName ?? "analysis.pro.uncategorized".localized
    }
}

// MARK: - Summary Card (Health-style "highlight" row that pushes a detail page)

/// Compact Health-style summary: tinted title, one-line takeaway, supporting caption,
/// and an optional mini visualization. The whole card is a navigation target.
struct ProSummaryCard<Mini: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let headline: String
    var headlineColor: Color = .primary
    var headlineLineLimit: Int = 1
    let caption: String
    @ViewBuilder var mini: Mini

    var body: some View {
        ProCard(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: systemImage)
                            .appFont(.caption, weight: .semibold)
                        Text(title)
                            .appFont(.caption, weight: .semibold)
                    }
                    .foregroundStyle(tint)

                    Text(headline)
                        .appFont(.headline)
                        .foregroundStyle(headlineColor)
                        .lineLimit(headlineLineLimit)
                        .minimumScaleFactor(0.8)
                    Text(caption)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                mini

                Image(systemName: "chevron.right")
                    .appFont(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
    }
}

// MARK: Cash Flow summary

struct ProFlowSummaryCard: View {
    var vm: ProAnalyticsViewModel

    private var buckets: [ProAnalyticsProcessor.FlowBucket] { vm.result.flowBuckets }
    private var net: Decimal { vm.result.net }
    private var netColor: Color {
        net >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    var body: some View {
        ProSummaryCard(
            title: "analysis.pro.cashFlow".localized,
            systemImage: "arrow.left.arrow.right",
            tint: .teal,
            headline: net > 0 ? "+\(net.formattedAmount(for: vm.preferredCurrency))" : net.formattedAmount(for: vm.preferredCurrency),
            headlineColor: netColor,
            caption: "analysis.pro.flow.caption".localized(
                with: vm.result.income.formattedAmountShort(for: vm.preferredCurrency),
                vm.result.expense.formattedAmountShort(for: vm.preferredCurrency)
            )
        ) {
            if !buckets.isEmpty {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("analysis.pro.period".localized, bucket.date, unit: vm.grouping.chartComponent),
                        y: .value("analysis.pro.amount".localized, bucket.income.doubleValue)
                    )
                    .foregroundStyle(ThemeManager.shared.incomeColor)
                    .cornerRadius(1)

                    BarMark(
                        x: .value("analysis.pro.period".localized, bucket.date, unit: vm.grouping.chartComponent),
                        y: .value("analysis.pro.amount".localized, -bucket.expense.doubleValue)
                    )
                    .foregroundStyle(ThemeManager.shared.expenseColor)
                    .cornerRadius(1)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .allowsHitTesting(false)
                .frame(width: 96, height: 40)
            }
        }
    }
}

// MARK: Categories summary

struct ProCategoriesSummaryCard: View {
    var vm: ProAnalyticsViewModel

    private var categories: [ProAnalyticsProcessor.CategorySlice] { vm.result.categories }

    private var titleKey: String {
        vm.selectedTransactionType == .expense ? "analysis.topSpendingCategories" : "analysis.topIncomeCategories"
    }

    private var caption: String {
        guard let top = categories.first else { return "" }
        let amount = top.amount.formattedAmountShort(for: vm.preferredCurrency)
        let share = top.fraction.formatted(.percent.precision(.fractionLength(0)))
        return "\(amount) · \(share)"
    }

    var body: some View {
        ProSummaryCard(
            title: titleKey.localized,
            systemImage: "chart.pie.fill",
            tint: .blue,
            headline: categories.first?.name ?? "—",
            caption: caption
        ) {
            if !categories.isEmpty {
                Chart {
                    ForEach(Array(categories.prefix(5).enumerated()), id: \.offset) { _, slice in
                        SectorMark(
                            angle: .value("analysis.pro.amount".localized, slice.amount.doubleValue),
                            innerRadius: .ratio(0.55),
                            angularInset: 1
                        )
                        .foregroundStyle(Color(hex: slice.colorHex) ?? .blue)
                        .cornerRadius(2)
                    }
                    let other = categories.dropFirst(5).reduce(Decimal.zero) { $0 + $1.amount }
                    if other > 0 {
                        SectorMark(
                            angle: .value("analysis.pro.amount".localized, other.doubleValue),
                            innerRadius: .ratio(0.55),
                            angularInset: 1
                        )
                        .foregroundStyle(Color(.systemGray3))
                        .cornerRadius(2)
                    }
                }
                .allowsHitTesting(false)
                .frame(width: 44, height: 44)
            }
        }
    }
}

// MARK: Budgets summary

struct ProBudgetsSummaryCard: View {
    var vm: ProAnalyticsViewModel

    private var statuses: [ProAnalyticsProcessor.BudgetStatus] { vm.result.budgetStatuses }
    private var overCount: Int { statuses.filter { $0.fraction >= 1 }.count }

    private var caption: String {
        guard let riskiest = statuses.first else { return "" }
        return "\(riskiest.name) · \(riskiest.fraction.formatted(.percent.precision(.fractionLength(0))))"
    }

    var body: some View {
        ProSummaryCard(
            title: "budget.title".localized,
            systemImage: "gauge.with.needle",
            tint: .green,
            headline: "budget.onTrackCount".localized(with: statuses.count - overCount, overCount),
            caption: caption
        ) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(statuses.prefix(4)) { status in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5)).frame(width: 56, height: 5)
                        Capsule().fill(barColor(status))
                            .frame(width: 56 * CGFloat(min(status.fraction, 1)), height: 5)
                    }
                }
            }
        }
    }

    private func barColor(_ status: ProAnalyticsProcessor.BudgetStatus) -> Color {
        if status.fraction >= 1 { return ThemeManager.shared.expenseColor }
        if status.fraction >= 0.8 { return .orange }
        return ThemeManager.shared.incomeColor
    }
}

// MARK: Largest transaction summary

struct ProLargestSummaryCard: View {
    var vm: ProAnalyticsViewModel

    private var top: ProAnalyticsProcessor.TransactionHighlight? { vm.result.largestTransactions.first }
    private var amountColor: Color {
        vm.selectedTransactionType == .income ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    private var caption: String {
        guard let top else { return "" }
        let name: String = {
            if let note = top.note, !note.trimmingCharacters(in: .whitespaces).isEmpty { return note }
            return top.categoryName ?? "analysis.pro.uncategorized".localized
        }()
        return "\(name) · \(top.date.formatted(.dateTime.month(.abbreviated).day().locale(.app)))"
    }

    var body: some View {
        ProSummaryCard(
            title: "analysis.pro.largest".localized,
            systemImage: "list.number",
            tint: .indigo,
            headline: top?.amount.formattedAmount(for: vm.preferredCurrency) ?? "—",
            headlineColor: amountColor,
            caption: caption
        ) {
            EmptyView()
        }
    }
}

// MARK: Insights summary

struct ProInsightsSummaryCard: View {
    var vm: ProAnalyticsViewModel

    private var insights: [ProInsight] {
        ProInsightsBuilder.build(from: vm.result, currency: vm.preferredCurrency)
    }

    var body: some View {
        ProSummaryCard(
            title: "analysis.pro.insights".localized,
            systemImage: "sparkles",
            tint: .purple,
            headline: insights.first?.text ?? "",
            headlineLineLimit: 2,
            caption: "analysis.pro.insights.count".localized(with: insights.count)
        ) {
            EmptyView()
        }
    }
}

// MARK: Weekday Patterns summary

struct ProPatternsSummaryCard: View {
    var vm: ProAnalyticsViewModel

    private var stats: [ProAnalyticsProcessor.WeekdayStat] { vm.result.weekdayTotals }
    private var maxTotal: Decimal { stats.map(\.total).max() ?? 0 }
    private var barColor: Color {
        vm.selectedTransactionType == .income ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    private var topDayName: String {
        guard let busiest = stats.filter({ $0.total > 0 }).max(by: { $0.total < $1.total }) else { return "—" }
        return ProDateFormatters.weekdaySymbol(busiest.weekday)
    }

    var body: some View {
        ProSummaryCard(
            title: "analysis.pro.weekdayPattern".localized,
            systemImage: "calendar",
            tint: .orange,
            headline: topDayName,
            caption: "analysis.pro.patterns.avgCaption".localized(with: vm.result.avgDailySpend.formattedAmountShort(for: vm.preferredCurrency))
        ) {
            if maxTotal > 0 {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(orderedWeekdays, id: \.self) { wd in
                        let total = stats.first { $0.weekday == wd }?.total ?? 0
                        let ratio = maxTotal > 0 ? (total / maxTotal).doubleValue : 0
                        Capsule()
                            .fill(barColor.opacity(total == maxTotal && total > 0 ? 1 : 0.35))
                            .frame(width: 5, height: max(4, 36 * ratio))
                    }
                }
                .frame(height: 36, alignment: .bottom)
            }
        }
    }
}

// MARK: Heatmap summary

struct ProHeatmapSummaryCard: View {
    var vm: ProAnalyticsViewModel

    private var heatColor: Color {
        vm.selectedTransactionType == .income ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    private var maxDay: Decimal { vm.result.dailySpend.map(\.amount).max() ?? 0 }

    private var busiest: ProAnalyticsProcessor.DaySpend? {
        vm.result.dailySpend.max { $0.amount < $1.amount }
    }

    private var headline: String {
        guard let busiest else { return "—" }
        let day = busiest.date.formatted(.dateTime.month(.abbreviated).day().locale(.app))
        return "\(day) · \(busiest.amount.formattedAmountShort(for: vm.preferredCurrency))"
    }

    /// Most recent 4 week-columns of the period, column-major like the full heatmap.
    private var miniColumns: [[Date]] {
        let calendar = Calendar.current
        let lastDay = calendar.startOfDay(for: min(vm.endDate, Date()))
        var days: [Date] = []
        for offset in stride(from: 27, through: 0, by: -1) {
            if let d = calendar.date(byAdding: .day, value: -offset, to: lastDay), d >= calendar.startOfDay(for: vm.startDate) {
                days.append(d)
            }
        }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    var body: some View {
        let spendByDay = Dictionary(uniqueKeysWithValues: vm.result.dailySpend.map { ($0.date, $0.amount) })

        ProSummaryCard(
            title: "analysis.pro.heatmap".localized,
            systemImage: "square.grid.3x3.fill",
            tint: .pink,
            headline: headline,
            caption: "analysis.pro.activeDays".localized(with: vm.result.dailySpend.filter { $0.amount > 0 }.count)
        ) {
            HStack(alignment: .top, spacing: 2) {
                ForEach(Array(miniColumns.enumerated()), id: \.offset) { _, column in
                    VStack(spacing: 2) {
                        ForEach(Array(column.enumerated()), id: \.offset) { _, day in
                            let amount = spendByDay[day] ?? 0
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(cellColor(amount))
                                .frame(width: 7, height: 7)
                        }
                    }
                }
            }
        }
    }

    private func cellColor(_ amount: Decimal) -> Color {
        guard amount > 0, maxDay > 0 else { return Color(.systemGray5) }
        let intensity = 0.3 + 0.7 * (amount / maxDay).doubleValue
        return heatColor.opacity(min(1.0, intensity))
    }
}

// MARK: Merchants summary

struct ProMerchantsSummaryCard: View {
    var vm: ProAnalyticsViewModel

    private var top: ProAnalyticsProcessor.MerchantStat? { vm.result.merchants.first }

    var body: some View {
        ProSummaryCard(
            title: "analysis.pro.topPlaces".localized,
            systemImage: "mappin.and.ellipse",
            tint: .pink,
            headline: top?.name ?? "—",
            caption: top.map {
                "\($0.amount.formattedAmountShort(for: vm.preferredCurrency)) · \($0.count) \("analysis.pro.visits".localized)"
            } ?? ""
        ) {
            EmptyView()
        }
    }
}

// MARK: - Weekday Patterns (full chart, shown on the detail page)

struct ProPatternsCard: View {
    var vm: ProAnalyticsViewModel
    @State private var selectedWeekdaySymbol: String?

    private var stats: [ProAnalyticsProcessor.WeekdayStat] { vm.result.weekdayTotals }
    private var barColor: Color {
        vm.selectedTransactionType == .income ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    /// Weekday numbers (1...7) reordered to start at the locale's first weekday.
    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    private var maxTotal: Decimal { stats.map(\.total).max() ?? 0 }

    private var selectedStat: ProAnalyticsProcessor.WeekdayStat? {
        guard let symbol = selectedWeekdaySymbol else { return nil }
        guard let wd = orderedWeekdays.first(where: { ProDateFormatters.weekdaySymbol($0) == symbol }) else { return nil }
        return stats.first { $0.weekday == wd }
    }

    var body: some View {
        ProCard {
            ProSectionHeader(
                title: "analysis.pro.weekdayPattern".localized,
                subtitle: "analysis.pro.weekdayPattern.subtitle".localized,
                systemImage: "calendar"
            )

            if maxTotal == 0 {
                ProEmptyChart()
            } else {
                chart

                Divider()

                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text("analysis.pro.avgPerDay".localized)
                            .appFont(.caption2, weight: .semibold)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(vm.result.avgDailySpend.formattedAmount(for: vm.preferredCurrency))
                            .appFont(.subheadline, weight: .bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        DeltaBadge(
                            current: vm.result.avgDailySpend,
                            previous: vm.result.prevAvgDailySpend,
                            higherIsBetter: vm.selectedTransactionType == .income
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 4)

                    Divider().frame(height: 44)
                    if let busiest = stats.filter({ $0.total > 0 }).max(by: { $0.total < $1.total }) {
                        miniStat(
                            label: "analysis.pro.topDay".localized,
                            value: ProDateFormatters.weekdaySymbol(busiest.weekday)
                        )
                    }
                    if let projected = vm.result.projectedTotal, projected > 0 {
                        Divider().frame(height: 44)
                        miniStat(
                            label: "analysis.pro.projected".localized,
                            value: projected.formattedAmountShort(for: vm.preferredCurrency)
                        )
                    }
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(orderedWeekdays, id: \.self) { wd in
                let stat = stats.first { $0.weekday == wd }
                let total = stat?.total ?? 0
                let symbol = ProDateFormatters.weekdaySymbol(wd)
                let isSelected = selectedWeekdaySymbol == symbol
                let dimmed = selectedWeekdaySymbol != nil && !isSelected

                BarMark(
                    x: .value("analysis.pro.weekday".localized, symbol),
                    y: .value("analysis.pro.amount".localized, total.doubleValue)
                )
                .foregroundStyle((total == maxTotal && total > 0 ? barColor : barColor.opacity(0.4)).gradient)
                .cornerRadius(4)
                .opacity(dimmed ? 0.3 : 1)
            }

            if let stat = selectedStat, let symbol = selectedWeekdaySymbol {
                RuleMark(x: .value("analysis.pro.weekday".localized, symbol))
                    .foregroundStyle(.clear)
                    .annotation(
                        position: .top,
                        spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        ProCallout {
                            Text(ProDateFormatters.weekdaySymbol(stat.weekday))
                                .appFont(.caption2, weight: .semibold)
                                .foregroundStyle(.secondary)
                            ProCalloutRow(color: barColor, label: "analysis.total".localized,
                                          value: stat.total.formattedAmountShort(for: vm.preferredCurrency))
                            ProCalloutRow(color: barColor.opacity(0.5), label: "analysis.pro.average".localized,
                                          value: stat.average.formattedAmountShort(for: vm.preferredCurrency))
                        }
                    }
            }
        }
        .chartXSelection(value: $selectedWeekdaySymbol)
        .chartXScale(domain: orderedWeekdays.map { ProDateFormatters.weekdaySymbol($0) })
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.app(.caption2))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v.formattedAmountShort(for: vm.preferredCurrency))
                            .appFont(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 190)
    }

    @ViewBuilder
    private func miniStat(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .appFont(.caption2, weight: .semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .appFont(.subheadline, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }
}

// MARK: - Spending Heatmap (full chart, shown on the detail page)

struct ProHeatmapCard: View {
    var vm: ProAnalyticsViewModel
    @State private var selectedDay: SelectedDay?

    private struct SelectedDay: Identifiable {
        let date: Date
        var id: Date { date }
    }

    private let cellSize: CGFloat = 15
    private let cellSpacing: CGFloat = 3

    private var heatColor: Color {
        vm.selectedTransactionType == .income ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    private var spendByDay: [Date: Decimal] {
        Dictionary(uniqueKeysWithValues: vm.result.dailySpend.map { ($0.date, $0.amount) })
    }

    private var maxDay: Double { vm.result.dailySpend.map { $0.amount.doubleValue }.max() ?? 0 }

    /// Columns of 7 days each (ordered by locale first weekday), GitHub-contributions layout.
    private var weeks: [[Date]] {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: vm.startDate)
        let offset = (calendar.component(.weekday, from: startDay) - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -offset, to: startDay) else { return [] }

        var result: [[Date]] = []
        var cursor = gridStart
        var guardCounter = 0
        while cursor < vm.endDate && guardCounter < 60 {
            var week: [Date] = []
            for _ in 0..<7 {
                week.append(cursor)
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86_400)
            }
            result.append(week)
            guardCounter += 1
        }
        return result
    }

    var body: some View {
        ProCard {
            ProSectionHeader(
                title: "analysis.pro.heatmap".localized,
                subtitle: "analysis.pro.heatmap.subtitle".localized,
                systemImage: "square.grid.3x3.fill"
            )

            if maxDay == 0 {
                ProEmptyChart()
            } else {
                HStack(alignment: .top, spacing: 8) {
                    // Sparse weekday labels (rows 0, 2, 4, 6)
                    VStack(spacing: cellSpacing) {
                        ForEach(0..<7, id: \.self) { row in
                            Text(row.isMultiple(of: 2) ? weekdayLabel(row: row) : "")
                                .appFont(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(height: cellSize)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .frame(width: 28, alignment: .leading)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: cellSpacing) {
                            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                                VStack(spacing: cellSpacing) {
                                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                        cell(for: day)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Legend
                HStack(spacing: 6) {
                    Text("analysis.pro.less".localized)
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(level == 0 ? Color(.systemGray5) : heatColor.opacity(0.3 + 0.7 * level))
                            .frame(width: 12, height: 12)
                    }
                    Text("analysis.pro.more".localized)
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .sheet(item: $selectedDay) { day in
            NavigationStack {
                FilteredTransactionsDetailView(
                    config: TransactionFilterConfig(
                        title: day.date.appFormatted(date: .abbreviated, time: .omitted),
                        startDate: day.date,
                        endDate: Calendar.current.date(byAdding: .day, value: 1, to: day.date) ?? day.date,
                        walletId: vm.singleSelectedWalletId,
                        transactionType: vm.selectedTransactionType,
                        dateRangeDescription: day.date.appFormatted(date: .complete, time: .omitted),
                        defaultSortOption: .highestAmount
                    )
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func weekdayLabel(row: Int) -> String {
        let first = Calendar.current.firstWeekday
        let weekday = ((first - 1 + row) % 7) + 1
        return ProDateFormatters.weekdaySymbol(weekday)
    }

    @ViewBuilder
    private func cell(for day: Date) -> some View {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: vm.startDate)
        let inRange = day >= startDay && day < vm.endDate
        let amount = spendByDay[day]?.doubleValue ?? 0

        Button {
            selectedDay = SelectedDay(date: day)
            HapticManager.shared.selection()
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(fillColor(inRange: inRange, amount: amount))
                .frame(width: cellSize, height: cellSize)
        }
        .buttonStyle(.plain)
        .disabled(!inRange || amount == 0)
    }

    private func fillColor(inRange: Bool, amount: Double) -> Color {
        guard inRange else { return Color(.systemGray6).opacity(0.5) }
        guard amount > 0, maxDay > 0 else { return Color(.systemGray5) }
        let intensity = 0.3 + 0.7 * (amount / maxDay)
        return heatColor.opacity(min(1.0, intensity))
    }
}

// MARK: - Top Places / Merchants (full list, shown on the detail page)

struct ProMerchantsCard: View {
    var vm: ProAnalyticsViewModel

    private var merchants: [ProAnalyticsProcessor.MerchantStat] {
        Array(vm.result.merchants.prefix(10))
    }
    private var maxAmount: Decimal { merchants.first?.amount ?? 1 }

    var body: some View {
        ProCard {
            ProSectionHeader(
                title: "analysis.pro.topPlaces".localized,
                subtitle: "analysis.pro.topPlaces.subtitle".localized,
                systemImage: "mappin.and.ellipse"
            )

            VStack(spacing: 0) {
                ForEach(Array(merchants.enumerated()), id: \.element.id) { index, place in
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .appFont(.title3)
                                .foregroundStyle(.pink)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(place.name)
                                    .appFont(.subheadline, weight: .medium)
                                    .lineLimit(1)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color(.systemGray5)).frame(height: 6)
                                        let ratio = maxAmount > 0 ? (place.amount / maxAmount).doubleValue : 0
                                        Capsule().fill(Color.pink.opacity(0.7))
                                            .frame(width: geo.size.width * CGFloat(ratio), height: 6)
                                    }
                                }
                                .frame(height: 6)
                            }

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(place.amount.formattedAmount(for: vm.preferredCurrency))
                                    .appFont(.callout)
                                    .monospacedDigit()
                                Text("\(place.count) \("analysis.pro.visits".localized)")
                                    .appFont(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)

                        if index != merchants.count - 1 {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Shared Empty State

struct ProEmptyChart: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .appFont(.title)
                .foregroundStyle(.tertiary)
            Text("analysis.noTransactionsForPeriod".localized)
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}
