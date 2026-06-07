import SwiftUI
import SwiftData
import Charts

// MARK: - Cash Flow (income vs expense grouped bars)

struct ProCashFlowCard: View {
    var vm: ProAnalyticsViewModel

    private var buckets: [ProAnalyticsProcessor.FlowBucket] { vm.result.flowBuckets }
    private var incomeLabel: String { L10n.Transaction.TransactionType.income }
    private var expenseLabel: String { L10n.Transaction.TransactionType.expense }

    var body: some View {
        ProCard {
            ProSectionHeader(
                title: "analysis.pro.cashFlow".localized,
                subtitle: "analysis.pro.cashFlow.subtitle".localized,
                systemImage: "arrow.left.arrow.right"
            )

            if buckets.allSatisfy({ $0.income == 0 && $0.expense == 0 }) {
                ProEmptyChart()
            } else {
                Chart {
                    ForEach(buckets) { bucket in
                        BarMark(
                            x: .value("analysis.pro.period".localized, bucket.date, unit: vm.grouping.chartComponent),
                            y: .value("analysis.pro.amount".localized, bucket.income.doubleValue)
                        )
                        .foregroundStyle(by: .value("analysis.transactionType".localized, incomeLabel))
                        .position(by: .value("analysis.transactionType".localized, incomeLabel))
                        .cornerRadius(3)

                        BarMark(
                            x: .value("analysis.pro.period".localized, bucket.date, unit: vm.grouping.chartComponent),
                            y: .value("analysis.pro.amount".localized, bucket.expense.doubleValue)
                        )
                        .foregroundStyle(by: .value("analysis.transactionType".localized, expenseLabel))
                        .position(by: .value("analysis.transactionType".localized, expenseLabel))
                        .cornerRadius(3)
                    }
                }
                .chartForegroundStyleScale(
                    domain: [incomeLabel, expenseLabel],
                    range: [ThemeManager.shared.incomeColor, ThemeManager.shared.expenseColor]
                )
                .chartLegend(position: .top, alignment: .leading, spacing: 8)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel(format: vm.grouping.axisFormat)
                            .font(.app(.caption2))
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                            .foregroundStyle(Color.secondary.opacity(0.15))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                            .foregroundStyle(Color.secondary.opacity(0.15))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v.formattedAmountShort(for: vm.preferredCurrency))
                                    .font(.app(.caption2))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 220)
            }
        }
    }
}

// MARK: - Net Trend (cumulative net flow area)

struct ProNetTrendCard: View {
    var vm: ProAnalyticsViewModel

    private struct TrendPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let value: Double
    }

    private var points: [TrendPoint] {
        var running: Decimal = 0
        return vm.result.flowBuckets.map { bucket in
            running += bucket.net
            return TrendPoint(date: bucket.date, value: running.doubleValue)
        }
    }

    private var endValue: Double { points.last?.value ?? 0 }
    private var trendColor: Color {
        endValue >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    var body: some View {
        ProCard {
            ProSectionHeader(
                title: "analysis.pro.netTrend".localized,
                subtitle: "analysis.pro.netTrend.subtitle".localized,
                systemImage: "chart.xyaxis.line"
            )

            if points.count < 2 {
                ProEmptyChart()
            } else {
                Chart {
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(Color(.separator))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    ForEach(points) { point in
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
                        .lineStyle(StrokeStyle(lineWidth: 3))
                    }

                    if let last = points.last {
                        PointMark(
                            x: .value("analysis.pro.period".localized, last.date, unit: vm.grouping.chartComponent),
                            y: .value("analysis.net".localized, last.value)
                        )
                        .foregroundStyle(trendColor)
                        .symbolSize(60)
                    }
                }
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
                                    .font(.app(.caption2))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 200)
            }
        }
    }
}

// MARK: - Category Breakdown (donut + drill-down legend)

struct ProCategoryCard: View {
    var vm: ProAnalyticsViewModel
    var wallets: [Wallet] = []
    @State private var selected: ProAnalyticsProcessor.CategorySlice?

    /// Name of the single selected wallet, when exactly one is active (for drill-down titles).
    private var singleWalletName: String? {
        guard let id = vm.singleSelectedWalletId else { return nil }
        return wallets.first { $0.id == id }?.name
    }

    private var categories: [ProAnalyticsProcessor.CategorySlice] { vm.result.categories }
    private var total: Decimal { categories.reduce(0) { $0 + $1.amount } }

    /// Top slices rendered individually; the remainder collapses into one "Other" sector.
    private var donutSlices: [(name: String, amount: Decimal, color: Color)] {
        let top = categories.prefix(8)
        var slices = top.map { ($0.name, $0.amount, Color(hex: $0.colorHex) ?? .blue) }
        let otherAmount = categories.dropFirst(8).reduce(Decimal.zero) { $0 + $1.amount }
        if otherAmount > 0 {
            slices.append(("analysis.pro.other".localized, otherAmount, Color(.systemGray3)))
        }
        return slices
    }

    private var titleKey: String {
        vm.selectedTransactionType == .expense ? "analysis.topSpendingCategories" : "analysis.topIncomeCategories"
    }

    var body: some View {
        ProCard {
            ProSectionHeader(title: titleKey.localized, systemImage: "chart.pie.fill")

            if categories.isEmpty {
                ProEmptyChart()
            } else {
                ZStack {
                    Chart {
                        ForEach(Array(donutSlices.enumerated()), id: \.offset) { _, slice in
                            SectorMark(
                                angle: .value("analysis.pro.amount".localized, slice.amount.doubleValue),
                                innerRadius: .ratio(0.62),
                                angularInset: 1.5
                            )
                            .foregroundStyle(slice.color)
                            .cornerRadius(4)
                        }
                    }
                    .frame(height: 200)

                    VStack(spacing: 2) {
                        Text("analysis.total".localized.uppercased())
                            .appFont(.caption2, weight: .semibold)
                            .foregroundStyle(.secondary)
                        Text(total.formattedAmountShort(for: vm.preferredCurrency))
                            .appFont(.title2, weight: .bold)
                    }
                }

                VStack(spacing: 0) {
                    ForEach(categories) { stat in
                        Button {
                            selected = stat
                        } label: {
                            categoryRow(stat)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $selected) { stat in
            NavigationStack {
                FilteredTransactionsDetailView(
                    config: TransactionFilterConfig(
                        title: stat.name,
                        startDate: vm.startDate,
                        endDate: vm.endDate,
                        walletId: vm.singleSelectedWalletId,
                        walletName: singleWalletName,
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
    }
}

// MARK: - Weekday Patterns

struct ProPatternsCard: View {
    var vm: ProAnalyticsViewModel

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
                Chart {
                    ForEach(orderedWeekdays, id: \.self) { wd in
                        let stat = stats.first { $0.weekday == wd }
                        let total = stat?.total ?? 0
                        BarMark(
                            x: .value("analysis.pro.weekday".localized, ProDateFormatters.weekdaySymbol(wd)),
                            y: .value("analysis.pro.amount".localized, total.doubleValue)
                        )
                        .foregroundStyle((total == maxTotal && total > 0 ? barColor : barColor.opacity(0.35)).gradient)
                        .cornerRadius(4)
                    }
                }
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
                                    .font(.app(.caption2))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 180)

                Divider()

                HStack(spacing: 0) {
                    miniStat(
                        label: "analysis.pro.avgPerDay".localized,
                        value: vm.result.avgDailySpend.formattedAmount(for: vm.preferredCurrency)
                    )
                    Divider().frame(height: 36)
                    if let busiest = stats.filter({ $0.total > 0 }).max(by: { $0.total < $1.total }) {
                        miniStat(
                            label: "analysis.pro.topDay".localized,
                            value: ProDateFormatters.weekdaySymbol(busiest.weekday)
                        )
                    }
                    if let projected = vm.result.projectedTotal, projected > 0 {
                        Divider().frame(height: 36)
                        miniStat(
                            label: "analysis.pro.projected".localized,
                            value: projected.formattedAmountShort(for: vm.preferredCurrency)
                        )
                    }
                }
            }
        }
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

// MARK: - Spending Heatmap (GitHub-style calendar)

struct ProHeatmapCard: View {
    var vm: ProAnalyticsViewModel

    private let cellSize: CGFloat = 15
    private let cellSpacing: CGFloat = 3

    private var heatColor: Color {
        vm.selectedTransactionType == .income ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    private var spendByDay: [Date: Decimal] {
        Dictionary(uniqueKeysWithValues: vm.result.dailySpend.map { ($0.date, $0.amount) })
    }

    private var maxDay: Double { vm.result.dailySpend.map { $0.amount.doubleValue }.max() ?? 0 }

    /// Columns of 7 days each (Sun→Sat ordered by locale first weekday), GitHub-contributions layout.
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
    }

    @ViewBuilder
    private func cell(for day: Date) -> some View {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: vm.startDate)
        let inRange = day >= startDay && day < vm.endDate
        let amount = spendByDay[day]?.doubleValue ?? 0

        RoundedRectangle(cornerRadius: 3)
            .fill(fillColor(inRange: inRange, amount: amount))
            .frame(width: cellSize, height: cellSize)
    }

    private func fillColor(inRange: Bool, amount: Double) -> Color {
        guard inRange else { return Color(.systemGray6).opacity(0.5) }
        guard amount > 0, maxDay > 0 else { return Color(.systemGray5) }
        let intensity = 0.3 + 0.7 * (amount / maxDay)
        return heatColor.opacity(min(1.0, intensity))
    }
}

// MARK: - Top Places / Merchants

struct ProMerchantsCard: View {
    var vm: ProAnalyticsViewModel

    private var merchants: [ProAnalyticsProcessor.MerchantStat] {
        Array(vm.result.merchants.prefix(5))
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
