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

    /// Day offset at which this period should be measured against the previous
    /// one: today while the period is still running, its final day once it's
    /// over. Comparing a half-finished month against a complete one is the
    /// easiest way to make a normal month look alarming, so both series are
    /// always read at the same offset. `nil` when the period is entirely in
    /// the future and there is nothing to compare yet.
    let comparisonIndex: Int?

    /// True while `Date()` falls inside the period — drives the "by this day"
    /// wording, which is wrong once the month is closed.
    let isPeriodOngoing: Bool

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

        // 7. Where "now" sits inside the period.
        let today = calendar.startOfDay(for: Date())
        let startDay = calendar.startOfDay(for: startDate)
        self.isPeriodOngoing = today >= startDay && today <= endDay
        if days.isEmpty {
            self.comparisonIndex = nil
        } else {
            let offset = calendar.dateComponents([.day], from: startDay, to: today).day ?? 0
            // A future period clamps to nil; a closed one clamps to its last day.
            self.comparisonIndex = offset < 0 ? nil : min(offset, days.count - 1)
        }
    }

    func cumulativeItem(on date: Date) -> CumulativeExpenseItem? {
        cumulativeByDay[Calendar.current.startOfDay(for: date)]
    }

    func averageItem(on date: Date) -> AverageExpenseItem? {
        averageByDay[Calendar.current.startOfDay(for: date)]
    }
}

// MARK: - Palette

/// Colors shared by the spend hero and the plain net header.
///
/// This used to carry a `tintedBackground` flag: Home filled its card with a
/// solid `Color.accentColor`, so every value had to be forced to white or
/// white-at-opacity to stay legible against an arbitrary accent hue — which
/// meant the one place semantic income/expense color mattered most was the one
/// place it was switched off. Home now sits on a neutral grouped-background
/// surface, so the whole translucent-white branch is gone and these are just
/// the system colors.
struct FinancialSummaryPalette {
    var muted: Color { .secondary }
    var referenceLine: Color { Color(.tertiaryLabel) }
    var primaryValue: Color { .primary }

    func netValue(isPositive: Bool) -> Color {
        isPositive ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
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
        self.onNavigateToPro = onNavigateToPro
    }

    var net: Decimal { income - expense }

    private var palette: FinancialSummaryPalette { FinancialSummaryPalette() }

    var body: some View {
        VStack(spacing: compact ? 12 : 16) {
            if showChart {
                // Derived once here, then handed down, so the hero's own state
                // changes never re-enter this initializer.
                SpendSummaryHero(
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
                        ProDrillInChevron(action: onNavigateToPro)
                    }
                }
            }
        }
        .padding(.vertical, compact ? 0 : 8)
    }
}

// MARK: - Pro Drill-in Chevron

struct ProDrillInChevron: View {
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.shared.impact(style: .light)
            action()
        } label: {
            Image(systemName: "chevron.right")
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                // Neutral system fill rather than a card-colored circle: the
                // hero card is itself `secondarySystemGroupedBackground` now,
                // so that would have been invisible.
                .background(Circle().fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("analysis.pro.mode.pro".localized)
    }
}

// MARK: - Spend Summary Hero

/// Home's hero card: one headline figure — what you've spent this period —
/// with a same-day-of-month comparison against the previous one, over a
/// scrubbable trend chart.
///
/// This replaces the old two-column "expense in July / expense in June" header.
/// That layout gave two equal-weight numbers with no entry point for the eye.
/// Here a single figure leads, the comparison moves into a chip plus one line
/// of plain text, and the space that buys goes to the chart.
///
/// The header doubles as the scrub readout: dragging across the chart swaps the
/// headline, chip and caption to that day's values rather than spending chart
/// area on a floating callout.
private struct SpendSummaryHero: View {
    let model: ExpenseTrendModel
    let expense: Decimal
    let startDate: Date
    let endDate: Date
    let compact: Bool
    let palette: FinancialSummaryPalette
    let previousPeriodCumulative: [Decimal]
    let onNavigateToPro: (() -> Void)?

    @State private var rawSelectedDate: Date?
    /// Selection as it stood when the current gesture began, so a tap that
    /// lands on the already-selected day can toggle it back off.
    @State private var selectionBeforeGesture: Date?
    @State private var isGestureActive = false

    // MARK: Period naming

    private var isFullMonthSelected: Bool {
        let calendar = Calendar.current
        guard calendar.component(.day, from: startDate) == 1 else { return false }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: endDate) else { return false }
        return calendar.component(.day, from: nextDay) == 1
    }

    private var currentPeriodName: String {
        guard isFullMonthSelected else { return L10n.Filter.thisMonth }
        return AppDateFormatterCache.formatter(dateFormat: "MMMM", locale: .app).string(from: startDate)
    }

    private var previousPeriodName: String {
        guard isFullMonthSelected else { return L10n.Analysis.previousPeriod }
        let calendar = Calendar.current
        guard let prevDate = calendar.date(byAdding: .month, value: -1, to: startDate) else {
            return L10n.Analysis.previousMonth
        }
        return AppDateFormatterCache.formatter(dateFormat: "MMMM", locale: .app).string(from: prevDate)
    }

    // MARK: Scrub selection

    /// Day offset of the scrubbed date, capped at the period's comparison point.
    ///
    /// The cap matters: `cumulative` is defined over every day of the period, so
    /// past today it simply repeats today's running total. Letting a finger drag
    /// into that region would report a real-looking figure for a day that hasn't
    /// happened. Parking the marker at today instead reads as the data boundary.
    private var selectedIndex: Int? {
        guard let rawSelectedDate else { return nil }
        let calendar = Calendar.current
        let offset = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: startDate),
            to: calendar.startOfDay(for: rawSelectedDate)
        ).day ?? 0
        guard offset >= 0, offset < model.cumulative.count else { return nil }
        guard let cap = model.comparisonIndex else { return nil }
        return min(offset, cap)
    }

    private var selectedItem: CumulativeExpenseItem? {
        selectedIndex.map { model.cumulative[$0] }
    }

    /// The point both series are read at: the scrubbed day, else the period's
    /// natural comparison point (today, or its final day once closed).
    private var activeIndex: Int? {
        selectedIndex ?? model.comparisonIndex
    }

    /// The figure the headline shows — the period total normally, the running
    /// total up to the scrubbed day while dragging.
    private var headlineAmount: Decimal {
        selectedItem?.cumulativeAmount ?? expense
    }

    // MARK: Comparison

    /// The previous period's cumulative spend at the same point in the period.
    ///
    /// `previousPeriodCumulative` can be shorter than this period (June has 30
    /// days, July 31), so the index is clamped — on the 31st the fair reference
    /// is simply June's final total.
    private var previousComparable: Decimal? {
        guard let index = activeIndex, !previousPeriodCumulative.isEmpty else { return nil }
        return previousPeriodCumulative[min(index, previousPeriodCumulative.count - 1)]
    }

    /// Signed difference against the previous period, and its percentage.
    /// `nil` whenever there's no previous data to divide by — a first month
    /// shows the headline figure alone rather than a meaningless "+100%".
    ///
    /// The percentage is only used for the chip, and the chip drops out past
    /// ±1000%: a previous period holding a single small transaction turns any
    /// ordinary month into "+4,200%", which is noise. The caption still states
    /// the absolute difference, which stays meaningful at any ratio.
    private var comparison: (delta: Decimal, percent: Int)? {
        guard let previous = previousComparable, previous > 0 else { return nil }
        let delta = headlineAmount - previous
        let percent = (delta / previous) * 100
        return (delta, Int((percent as NSDecimalNumber).doubleValue.rounded()))
    }

    /// Spending less than last period is the good direction, so the chip's
    /// color follows the sign of the change, not the expense hue.
    private var comparisonColor: Color {
        guard let comparison, comparison.percent != 0 else { return .secondary }
        return comparison.delta < 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    /// Label above the headline: the scrubbed date while dragging, otherwise
    /// what the figure is.
    private var eyebrowText: String {
        if let selectedItem {
            return AppDateFormatterCache.formatter(dateFormat: "d MMM", locale: .app)
                .string(from: selectedItem.date)
        }
        return "home.summary.spent".localized(with: currentPeriodName).uppercased()
    }

    private var captionText: String? {
        let currencyCode = CurrencyManager.shared.preferredCurrencyCode

        // While scrubbing, the useful second number is the ghost line's value at
        // the same day — that's what the gap on screen represents.
        if selectedItem != nil {
            guard let previous = previousComparable else { return nil }
            return "home.summary.scrubPrevious".localized(
                with: previousPeriodName,
                previous.formattedAmount(for: currencyCode)
            )
        }

        guard let comparison else { return nil }
        guard comparison.percent != 0 else {
            return "home.summary.deltaSame".localized(with: previousPeriodName)
        }
        let magnitude = abs(comparison.delta).formattedAmount(for: currencyCode)
        let key: String
        if comparison.delta < 0 {
            key = model.isPeriodOngoing ? "home.summary.deltaLessSoFar" : "home.summary.deltaLess"
        } else {
            key = model.isPeriodOngoing ? "home.summary.deltaMoreSoFar" : "home.summary.deltaMore"
        }
        return key.localized(with: magnitude, previousPeriodName)
    }

    /// A single point can't be drawn as a line, and an empty plot frame reads
    /// as a rendering bug — hide the chart until there's a shape to show.
    private var hasChartData: Bool {
        model.line.count > 1 || model.average.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center) {
                Text(eyebrowText)
                    .appFont(.caption2, weight: .bold)
                    .tracking(0.6)
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let onNavigateToPro {
                    ProDrillInChevron(action: onNavigateToPro)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headlineAmount.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                    .appFont(.title, weight: .bold)
                    .foregroundStyle(palette.primaryValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())

                if let comparison, comparison.percent != 0, abs(comparison.percent) < 1000 {
                    deltaChip(percent: comparison.percent, isDown: comparison.delta < 0)
                }
            }

            if let captionText {
                Text(captionText)
                    .appFont(.caption2)
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if hasChartData {
                chart
                    .frame(height: compact ? 132 : 152)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.15), value: selectedIndex)
        // A stale selection from the previous month would point at a day that
        // no longer exists in the new range.
        .onChange(of: startDate) { _, _ in rawSelectedDate = nil }
    }

    // MARK: Delta chip

    private func deltaChip(percent: Int, isDown: Bool) -> some View {
        HStack(spacing: 2) {
            Image(systemName: isDown ? "arrow.down" : "arrow.up")
                .appFont(.caption2, weight: .bold)
            Text("\(abs(percent))%")
                .appFont(.caption, weight: .semibold)
        }
        .foregroundStyle(comparisonColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(comparisonColor.opacity(0.14)))
        .accessibilityElement(children: .combine)
    }

    // MARK: Selection gesture

    /// Resolves a touch point to the day beneath it, in chart coordinates.
    ///
    /// The result is clamped to the selectable range here rather than at render
    /// time, so `rawSelectedDate` always holds exactly the day being shown. That
    /// keeps the tap-to-clear check honest: without it, two taps in the
    /// post-today region compare two different raw dates that both display as
    /// today, and the toggle never fires.
    private func day(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Date? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let plot = geometry[plotFrame]
        // Clamp rather than bail: a finger sliding past either end should stick
        // to the first/last day instead of dropping the selection mid-drag.
        let x = min(max(location.x - plot.origin.x, 0), plot.width)
        guard let date: Date = proxy.value(atX: x) else { return nil }

        let day = Calendar.current.startOfDay(for: date)
        guard let firstDay = model.cumulative.first?.date,
              let cap = model.comparisonIndex,
              cap < model.cumulative.count else { return nil }
        let lastSelectableDay = model.cumulative[cap].date

        if day < firstDay { return firstDay }
        if day > lastSelectableDay { return lastSelectableDay }
        return day
    }

    private func selectionGesture(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isGestureActive {
                    isGestureActive = true
                    selectionBeforeGesture = rawSelectedDate
                }
                guard let day = day(at: value.location, proxy: proxy, geometry: geometry) else { return }
                if let current = rawSelectedDate, Calendar.current.isDate(current, inSameDayAs: day) { return }
                rawSelectedDate = day
                HapticManager.shared.impact(style: .light)
            }
            .onEnded { value in
                // A tap on the day that was already selected clears it, which is
                // the only way back to the period summary without changing month.
                let isTap = abs(value.translation.width) < 8 && abs(value.translation.height) < 8
                if isTap,
                   let before = selectionBeforeGesture,
                   let now = rawSelectedDate,
                   Calendar.current.isDate(before, inSameDayAs: now) {
                    rawSelectedDate = nil
                }
                isGestureActive = false
                selectionBeforeGesture = nil
            }
    }

    // MARK: Chart

    /// The series plots expense, so it takes the user's configured expense hue
    /// rather than the app accent — the accent is chrome, this is data.
    ///
    /// Hoisted out of the chart body because `ThemeManager.expenseColor` parses
    /// its hex string on every read, and the chart wants it several times.
    private var expenseColor: Color { ThemeManager.shared.expenseColor }

    private var chart: some View {
        let expenseColor = self.expenseColor
        let currencyCode = CurrencyManager.shared.preferredCurrencyCode

        return Chart {
            // Previous period, ghosted. Runs the full width even though the
            // current line stops at today — that gap is the comparison.
            ForEach(model.average) { item in
                LineMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Previous", Double(truncating: item.cumulativeAmount as NSDecimalNumber)),
                    series: .value("Series", "Previous")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(palette.referenceLine)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3]))
            }

            ForEach(model.line) { item in
                AreaMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Current", Double(truncating: item.cumulativeAmount as NSDecimalNumber))
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [expenseColor.opacity(0.28), expenseColor.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            ForEach(model.line) { item in
                LineMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Current", Double(truncating: item.cumulativeAmount as NSDecimalNumber)),
                    series: .value("Series", "Current")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(expenseColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }

            if let selectedItem, let index = selectedIndex {
                RuleMark(x: .value("Selected", selectedItem.date, unit: .day))
                    .foregroundStyle(Color(.separator))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                // Only mark the drawn line: `line` stops at the last day with
                // spending, so beyond it there is no stroke to sit on.
                if selectedItem.date <= model.maxSpendingDate {
                    PointMark(
                        x: .value("Selected", selectedItem.date, unit: .day),
                        y: .value("Current", Double(truncating: selectedItem.cumulativeAmount as NSDecimalNumber))
                    )
                    .foregroundStyle(expenseColor)
                    .symbolSize(70)
                }

                if index < model.average.count {
                    let previousItem = model.average[index]
                    PointMark(
                        x: .value("Selected", previousItem.date, unit: .day),
                        y: .value("Previous", Double(truncating: previousItem.cumulativeAmount as NSDecimalNumber))
                    )
                    .foregroundStyle(palette.referenceLine)
                    .symbolSize(55)
                }
            } else if let lastPoint = model.line.last {
                // Emphasized endpoint: a card-colored disc punched out of the
                // area fill, with the expense dot on top.
                PointMark(
                    x: .value("Date", lastPoint.date, unit: .day),
                    y: .value("Current", Double(truncating: lastPoint.cumulativeAmount as NSDecimalNumber))
                )
                .foregroundStyle(Color(.secondarySystemGroupedBackground))
                .symbolSize(130)

                PointMark(
                    x: .value("Date", lastPoint.date, unit: .day),
                    y: .value("Current", Double(truncating: lastPoint.cumulativeAmount as NSDecimalNumber))
                )
                .foregroundStyle(expenseColor)
                .symbolSize(50)
            }
        }
        // Selection is driven by an explicit overlay gesture rather than
        // `.chartXSelection`. This card lives in a `List` row, and the list's
        // pan recognizer swallows the selection gesture that modifier installs —
        // taps and drags on the chart simply never arrived. A `minimumDistance:
        // 0` drag on our own overlay claims the touch on contact, so a single
        // tap selects and a horizontal drag scrubs, while vertical scrolling
        // still belongs to the list.
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(selectionGesture(proxy: proxy, geometry: geometry))
            }
        }
        // Pinned to the period, so a half-finished month renders as a line that
        // stops two-thirds across rather than being stretched to fill.
        .chartXScale(domain: startDate...endDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: compact ? 4 : 5)) { _ in
                AxisValueLabel(format: .dateTime.day())
                    .font(.app(.caption2))
                    .foregroundStyle(palette.muted)
            }
        }
        .chartYScale(domain: 0...model.maxYValue)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.12))
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(doubleValue.formattedAmountShort(for: currencyCode))
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
