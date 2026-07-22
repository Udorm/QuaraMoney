import SwiftUI
import Charts
import SwiftData

struct DailyExpenseItem: Identifiable {
    var id: Date { date }
    let date: Date
    let amount: Decimal
}

struct CumulativeExpenseItem: Identifiable {
    var id: Date { date }
    let date: Date
    let dailyAmount: Decimal
    let cumulativeAmount: Decimal
}

struct AverageExpenseItem: Identifiable {
    var id: Date { date }
    let date: Date
    let cumulativeAmount: Decimal
}

// MARK: - Derived chart data

/// Every array the expense-trend chart needs, derived in a single pass.
///
/// These used to be sibling computed properties on the view, each re-deriving
/// `chartData` (a walk over every day in the period plus a currency conversion
/// per transaction). A single `body` evaluation re-ran that work five or six
/// times, and because the scrub selection lived on the same view, it re-ran on
/// every touch-move frame. Building it once and handing it down fixes both.
struct ExpenseTrendModel {
    let daily: [DailyExpenseItem]
    let cumulative: [CumulativeExpenseItem]
    let average: [AverageExpenseItem]
    /// Cumulative series truncated at the last day with actual spending.
    let line: [CumulativeExpenseItem]
    let maxSpendingDate: Date
    let maxYValue: Double

    /// Start-of-day indexes so scrub lookups are O(1) instead of a linear
    /// `isDate(_:inSameDayAs:)` scan per frame.
    private let cumulativeByDay: [Date: CumulativeExpenseItem]
    private let averageByDay: [Date: AverageExpenseItem]

    static let empty = ExpenseTrendModel(
        dailySections: [],
        startDate: Date(),
        endDate: Date(),
        previousPeriodCumulative: []
    )

    init(
        dailySections: [DailyTransactionSection],
        startDate: Date,
        endDate: Date,
        previousPeriodCumulative: [Decimal]
    ) {
        // Hoisted: `Calendar.current` builds a fresh snapshot on every access,
        // and this used to be read once per transaction.
        let calendar = Calendar.current
        let targetCurrency = CurrencyManager.shared.preferredCurrencyCode
        let rates = CurrencyManager.shared.rates

        // 1. Continuous daily timeline for the period.
        var days: [Date] = []
        var current = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        while current <= endDay {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        // 2. Expense per day. `uniquingKeysWith` rather than
        // `uniqueKeysWithValues`: two sections landing on the same start-of-day
        // would trap, and the grouping is not this type's invariant to enforce.
        let expenseMap = Dictionary(
            dailySections.map { section -> (Date, Decimal) in
                let dayKey = calendar.startOfDay(for: section.date)
                let dailyExpense = section.transactions.reduce(Decimal.zero) { result, txn in
                    if txn.excludeFromReports { return result }
                    guard txn.type == .expense || (txn.type == .adjustment && txn.amount < 0) else { return result }
                    let converted = CurrencyManager.convert(amount: txn.amount, from: txn.currencyCode, to: targetCurrency, rates: rates)
                    return result + abs(converted)
                }
                return (dayKey, dailyExpense)
            },
            uniquingKeysWith: { $0 + $1 }
        )

        let daily = days.map { DailyExpenseItem(date: $0, amount: expenseMap[$0] ?? 0) }
        self.daily = daily

        // 3. Running total.
        var runningTotal: Decimal = 0
        let cumulative = daily.map { item -> CumulativeExpenseItem in
            runningTotal += item.amount
            return CumulativeExpenseItem(
                date: item.date,
                dailyAmount: item.amount,
                cumulativeAmount: runningTotal
            )
        }
        self.cumulative = cumulative

        // 4. Previous-period reference line, aligned day-for-day.
        let average = zip(days, previousPeriodCumulative).map {
            AverageExpenseItem(date: $0, cumulativeAmount: $1)
        }
        self.average = average

        // 5. Truncate the current line at the last day with spending.
        let maxSpendingDate = daily.last(where: { $0.amount > 0 })?.date ?? startDate
        self.maxSpendingDate = maxSpendingDate
        self.line = cumulative.filter { $0.date <= maxSpendingDate }

        // 6. Y domain covers both series.
        var values = cumulative.map { Double(truncating: $0.cumulativeAmount as NSDecimalNumber) }
        values.append(contentsOf: average.map { Double(truncating: $0.cumulativeAmount as NSDecimalNumber) })
        self.maxYValue = max(10.0, values.max() ?? 10.0) * 1.15

        self.cumulativeByDay = Dictionary(cumulative.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        self.averageByDay = Dictionary(average.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func cumulativeItem(on date: Date) -> CumulativeExpenseItem? {
        cumulativeByDay[Calendar.current.startOfDay(for: date)]
    }

    func averageItem(on date: Date) -> AverageExpenseItem? {
        averageByDay[Calendar.current.startOfDay(for: date)]
    }
}

// MARK: - Palette

/// Colors shared by the trend card and the plain net header. On the tinted hero
/// card (Home) chart chrome switches to translucent white so it stays legible
/// against an arbitrary accent fill.
struct FinancialSummaryPalette {
    let tintedBackground: Bool

    var muted: Color { tintedBackground ? Color.white.opacity(0.75) : .secondary }
    var previousValue: Color { tintedBackground ? Color.white.opacity(0.9) : Color(.secondaryLabel) }
    var referenceLine: Color { tintedBackground ? Color.white.opacity(0.55) : Color.gray.opacity(0.45) }
    var referenceDot: Color { tintedBackground ? Color.white.opacity(0.7) : Color.gray }
    var separator: Color { tintedBackground ? Color.white.opacity(0.35) : Color(.separator).opacity(0.4) }
    var gridline: Color { tintedBackground ? Color.white.opacity(0.15) : Color.secondary.opacity(0.08) }
    var primaryValue: Color { tintedBackground ? .white : .primary }

    /// Fixed ring drawn around expense/income-colored marks on the tinted hero
    /// card so they stay legible however close the user's hue sits to the fill.
    var halo: Color { Color.white.opacity(0.9) }

    /// The big "expense in period" figure can't rely on the raw expense hue for
    /// contrast against an arbitrary accent background.
    var expenseValue: Color { tintedBackground ? primaryValue : ThemeManager.shared.expenseColor }

    func netValue(isPositive: Bool) -> Color {
        guard !tintedBackground else { return primaryValue }
        return isPositive ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }
}

// MARK: - Card

struct FinancialSummaryCards: View {
    let income: Decimal
    let expense: Decimal
    let dailySections: [DailyTransactionSection]
    let startDate: Date
    let endDate: Date
    let showChart: Bool
    let previousPeriodCumulative: [Decimal]
    /// Tighter spacing + smaller chart/figures, for hero-card contexts (Home).
    let compact: Bool
    /// True when the card sits on a solid accent-colored background (Home's hero
    /// card) rather than the default page background.
    let tintedBackground: Bool
    /// When set, a drill-in chevron is shown at the top-right of the header that
    /// invokes this closure (Home → Pro analytics). Nil hides the chevron.
    let onNavigateToPro: (() -> Void)?

    init(
        income: Decimal,
        expense: Decimal,
        dailySections: [DailyTransactionSection] = [],
        startDate: Date = Date(),
        endDate: Date = Date(),
        showChart: Bool = true,
        previousPeriodCumulative: [Decimal] = [],
        compact: Bool = false,
        tintedBackground: Bool = false,
        onNavigateToPro: (() -> Void)? = nil
    ) {
        self.income = income
        self.expense = expense
        self.dailySections = dailySections
        self.startDate = startDate
        self.endDate = endDate
        self.showChart = showChart
        self.previousPeriodCumulative = previousPeriodCumulative
        self.compact = compact
        self.tintedBackground = tintedBackground
        self.onNavigateToPro = onNavigateToPro
    }

    var net: Decimal { income - expense }

    private var palette: FinancialSummaryPalette {
        FinancialSummaryPalette(tintedBackground: tintedBackground)
    }

    var body: some View {
        VStack(spacing: compact ? 12 : 16) {
            if showChart {
                // Derived once here, then handed down. The scrub selection lives
                // inside ExpenseTrendCard, so dragging re-renders only that
                // subtree and never re-enters this initializer.
                ExpenseTrendCard(
                    model: ExpenseTrendModel(
                        dailySections: dailySections,
                        startDate: startDate,
                        endDate: endDate,
                        previousPeriodCumulative: previousPeriodCumulative
                    ),
                    expense: expense,
                    startDate: startDate,
                    endDate: endDate,
                    compact: compact,
                    palette: palette,
                    previousPeriodCumulative: previousPeriodCumulative,
                    onNavigateToPro: onNavigateToPro
                )
            } else {
                // Standard net-total header for non-chart summaries (Analysis).
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Analysis.net.uppercased())
                            .appFont(.caption2, weight: .bold)
                            .foregroundStyle(palette.muted)

                        Text(net.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                            .appFont(.title, weight: .bold)
                            .foregroundStyle(palette.netValue(isPositive: net >= 0))
                    }
                    Spacer()
                    if let onNavigateToPro {
                        ProDrillInChevron(tintedBackground: tintedBackground, action: onNavigateToPro)
                    }
                }
            }
        }
        .padding(.vertical, compact ? 0 : 8)
    }
}

// MARK: - Pro Drill-in Chevron

struct ProDrillInChevron: View {
    let tintedBackground: Bool
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.shared.impact(style: .light)
            action()
        } label: {
            Image(systemName: "chevron.right")
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(tintedBackground ? .white : Color.accentColor)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(tintedBackground
                                  ? Color.white.opacity(0.18)
                                  : Color(.secondarySystemGroupedBackground))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("analysis.pro.mode.pro".localized)
    }
}

// MARK: - Expense Trend Card (Apple Health style)

/// Owns the chart's scrub selection. Keeping `rawSelectedDate` here rather than
/// on `FinancialSummaryCards` means a drag re-evaluates only this subtree — the
/// `ExpenseTrendModel` is passed in already built.
private struct ExpenseTrendCard: View {
    let model: ExpenseTrendModel
    let expense: Decimal
    let startDate: Date
    let endDate: Date
    let compact: Bool
    let palette: FinancialSummaryPalette
    let previousPeriodCumulative: [Decimal]
    let onNavigateToPro: (() -> Void)?

    @State private var rawSelectedDate: Date? = nil

    private var selectedCumulativeItem: CumulativeExpenseItem? {
        rawSelectedDate.flatMap { model.cumulativeItem(on: $0) }
    }

    private var selectedAverageItem: AverageExpenseItem? {
        rawSelectedDate.flatMap { model.averageItem(on: $0) }
    }

    private var currentTotal: Decimal {
        selectedCumulativeItem?.cumulativeAmount ?? expense
    }

    private var previousTotal: Decimal {
        selectedAverageItem?.cumulativeAmount ?? previousPeriodCumulative.last ?? .zero
    }

    private var isFullMonthSelected: Bool {
        let calendar = Calendar.current
        guard calendar.component(.day, from: startDate) == 1 else { return false }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: endDate) else { return false }
        return calendar.component(.day, from: nextDay) == 1
    }

    private var currentMonthName: String {
        AppDateFormatterCache.formatter(dateFormat: "MMMM", locale: .app).string(from: startDate)
    }

    private var previousMonthName: String {
        let calendar = Calendar.current
        guard let prevDate = calendar.date(byAdding: .month, value: -1, to: startDate) else {
            return L10n.Analysis.previousMonth
        }
        return AppDateFormatterCache.formatter(dateFormat: "MMMM", locale: .app).string(from: prevDate)
    }

    var body: some View {
        VStack(spacing: compact ? 12 : 16) {
            header
            chart.frame(height: compact ? 130 : 150)
        }
    }

    // MARK: Header

    private var header: some View {
        let currencyCode = CurrencyManager.shared.preferredCurrencyCode
        let isFullMonth = isFullMonthSelected

        return HStack(alignment: .center, spacing: 12) {
            // Current period
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(ThemeManager.shared.expenseColor)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(palette.halo, lineWidth: palette.tintedBackground ? 1 : 0))
                    Text("analysis.expenseInPeriod".localized(with: isFullMonth ? currentMonthName : L10n.Filter.thisMonth))
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(palette.muted)
                }

                Text(currentTotal.formattedAmount(for: currencyCode))
                    .appFont(compact ? .title3 : .title2, weight: .bold)
                    .foregroundStyle(palette.expenseValue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Previous period
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(palette.referenceDot)
                        .frame(width: 8, height: 8)
                    Text("analysis.expenseInPeriod".localized(with: isFullMonth ? previousMonthName : L10n.Analysis.previousPeriod))
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(palette.muted)
                }

                Text(previousTotal.formattedAmount(for: currencyCode))
                    .appFont(compact ? .title3 : .title2, weight: .bold)
                    .foregroundStyle(palette.previousValue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onNavigateToPro {
                ProDrillInChevron(tintedBackground: palette.tintedBackground, action: onNavigateToPro)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: rawSelectedDate == nil)
    }

    // MARK: Chart

    private var chart: some View {
        Chart {
            // 1. Previous-period reference line (grey, thinner)
            ForEach(model.average) { item in
                LineMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Previous", Double(truncating: item.cumulativeAmount as NSDecimalNumber)),
                    series: .value("Series", "Previous")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(palette.referenceLine)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }

            // 2. Current line (bold, colored, up to the last day with spending)
            ForEach(model.line) { item in
                LineMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Current", Double(truncating: item.cumulativeAmount as NSDecimalNumber)),
                    series: .value("Series", "Current")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(ThemeManager.shared.expenseColor)
                .lineStyle(StrokeStyle(lineWidth: 3))
            }

            // 3. Selection overlay
            if let selectedItem = selectedCumulativeItem {
                RuleMark(x: .value("Selected", selectedItem.date, unit: .day))
                    .foregroundStyle(palette.separator)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(
                        position: .top,
                        spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        ProCallout {
                            Text(selectedItem.date.formatted(.dateTime.month(.abbreviated).day().locale(.app)))
                                .appFont(.caption2, weight: .semibold)
                                .foregroundStyle(.secondary)
                        }
                    }

                if selectedItem.date <= model.maxSpendingDate {
                    PointMark(
                        x: .value("Selected", selectedItem.date, unit: .day),
                        y: .value("Current", Double(truncating: selectedItem.cumulativeAmount as NSDecimalNumber))
                    )
                    .foregroundStyle(ThemeManager.shared.expenseColor)
                    .symbolSize(60)
                }

                if let selectedAvg = selectedAverageItem {
                    PointMark(
                        x: .value("Selected", selectedAvg.date, unit: .day),
                        y: .value("Previous", Double(truncating: selectedAvg.cumulativeAmount as NSDecimalNumber))
                    )
                    .foregroundStyle(palette.referenceDot)
                    .symbolSize(60)
                }
            } else {
                if let lastPoint = model.line.last {
                    PointMark(
                        x: .value("Date", lastPoint.date, unit: .day),
                        y: .value("Current", Double(truncating: lastPoint.cumulativeAmount as NSDecimalNumber))
                    )
                    .foregroundStyle(ThemeManager.shared.expenseColor)
                    .symbolSize(40)
                }

                if let lastAvg = model.average.last {
                    PointMark(
                        x: .value("Date", lastAvg.date, unit: .day),
                        y: .value("Previous", Double(truncating: lastAvg.cumulativeAmount as NSDecimalNumber))
                    )
                    .foregroundStyle(palette.referenceDot)
                    .symbolSize(36)
                }
            }
        }
        .chartXSelection(value: $rawSelectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisValueLabel(format: .dateTime.day())
                    .font(.app(.caption2))
                    .foregroundStyle(palette.muted)
            }
        }
        .chartYScale(domain: 0...model.maxYValue)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(palette.gridline)
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(doubleValue.formattedAmountShort(for: CurrencyManager.shared.preferredCurrencyCode))
                            .appFont(.caption2)
                            .foregroundStyle(palette.muted)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        // Each period's data spans a different date range, so morphing marks
        // between them (Swift Charts' default) reads as a jittery wobble. Give
        // the chart a fresh identity per period instead and cross-fade.
        .id(startDate)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: startDate)
    }
}

#Preview {
    let now = Date()
    let calendar = Calendar.current
    let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
    let end = (calendar.date(byAdding: .month, value: 1, to: start) ?? start).addingTimeInterval(-1)

    return List {
        Section {
            FinancialSummaryCards(
                income: 5000,
                expense: 3200,
                dailySections: [],
                startDate: start,
                endDate: end
            )
        }
    }
    .modelContainer(for: [Budget.self, Category.self], inMemory: true)
}
