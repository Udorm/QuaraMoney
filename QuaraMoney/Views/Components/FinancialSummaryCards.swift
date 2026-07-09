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
    /// card) rather than the default page background — chart chrome and secondary
    /// labels switch to translucent white so they stay legible against the fill.
    let tintedBackground: Bool
    /// When set, a drill-in chevron is shown at the top-right of the header that
    /// invokes this closure (Home → Pro analytics). Nil hides the chevron.
    let onNavigateToPro: (() -> Void)?

    @Query(filter: #Predicate<Budget> { $0.deletedAt == nil }, sort: \Budget.startDate, order: .reverse) private var budgets: [Budget]
    @State private var rawSelectedDate: Date? = nil

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

    // Dynamic properties
    var net: Decimal {
        income - expense
    }

    // MARK: - Tinted-background-aware colors

    private var mutedTextColor: Color {
        tintedBackground ? Color.white.opacity(0.75) : .secondary
    }

    private var previousValueColor: Color {
        tintedBackground ? Color.white.opacity(0.9) : Color(.secondaryLabel)
    }

    private var referenceLineColor: Color {
        tintedBackground ? Color.white.opacity(0.55) : Color.gray.opacity(0.45)
    }

    private var referenceDotColor: Color {
        tintedBackground ? Color.white.opacity(0.7) : Color.gray
    }

    private var separatorColor: Color {
        tintedBackground ? Color.white.opacity(0.35) : Color(.separator).opacity(0.4)
    }

    private var gridlineColor: Color {
        tintedBackground ? Color.white.opacity(0.15) : Color.secondary.opacity(0.08)
    }

    private var primaryValueColor: Color {
        tintedBackground ? .white : .primary
    }

    /// Fixed ring drawn around/behind expense-or-income-colored swatches, lines,
    /// and points on the tinted hero card, so they stay legible no matter how
    /// close the user's chosen expense/income hue sits to the accent fill.
    private var haloColor: Color {
        Color.white.opacity(0.9)
    }

    /// The big "expense in period" figure can't rely on the raw expense hue for
    /// contrast against an arbitrary accent-colored background, so it falls back
    /// to the same neutral value color used for everything else on that card.
    private var expenseValueColor: Color {
        tintedBackground ? primaryValueColor : ThemeManager.shared.expenseColor
    }

    private func netValueColor(isPositive: Bool) -> Color {
        guard !tintedBackground else { return primaryValueColor }
        return isPositive ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    private var isFullMonthSelected: Bool {
        let calendar = Calendar.current
        guard calendar.component(.day, from: startDate) == 1 else { return false }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: endDate) else { return false }
        return calendar.component(.day, from: nextDay) == 1
    }
    

    
    // Continuous daily timeline mapping
    var chartData: [DailyExpenseItem] {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        
        var days: [Date] = []
        var current = startDay
        while current <= endDay {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        
        let targetCurrency = CurrencyManager.shared.preferredCurrencyCode
        let rates = CurrencyManager.shared.rates
        
        // Group dailySections by start-of-day
        let expenseMap: [Date: Decimal] = Dictionary(uniqueKeysWithValues: dailySections.map { section in
            let dayKey = calendar.startOfDay(for: section.date)
            let dailyExpense = section.transactions.reduce(Decimal.zero) { result, txn in
                if txn.excludeFromReports { return result }
                guard txn.type == .expense || (txn.type == .adjustment && txn.amount < 0) else { return result }
                let converted = CurrencyManager.convert(amount: txn.amount, from: txn.currencyCode, to: targetCurrency, rates: rates)
                return result + abs(converted)
            }
            return (dayKey, dailyExpense)
        })
        
        return days.map { day in
            DailyExpenseItem(date: day, amount: expenseMap[day] ?? 0)
        }
    }
    
    // Cumulative timeline data mapping
    var cumulativeChartData: [CumulativeExpenseItem] {
        let daily = chartData
        var runningTotal: Decimal = 0
        return daily.map { item in
            runningTotal += item.amount
            return CumulativeExpenseItem(
                date: item.date,
                dailyAmount: item.amount,
                cumulativeAmount: runningTotal
            )
        }
    }
    
    // Average cumulative timeline data mapping
    var averageChartData: [AverageExpenseItem] {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        
        var days: [Date] = []
        var current = startDay
        while current <= endDay {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        
        var result: [AverageExpenseItem] = []
        for (i, day) in days.enumerated() {
            guard i < previousPeriodCumulative.count else { break }
            result.append(AverageExpenseItem(date: day, cumulativeAmount: previousPeriodCumulative[i]))
        }
        return result
    }
    
    // Max cumulative expense including average line
    var maxCumulative: Double {
        var values = cumulativeChartData.map { Double(truncating: $0.cumulativeAmount as NSDecimalNumber) }
        let avgValues = averageChartData.map { Double(truncating: $0.cumulativeAmount as NSDecimalNumber) }
        values.append(contentsOf: avgValues)
        
        return max(10.0, values.max() ?? 10.0)
    }
    
    // Maximum Y value for the chart domain
    var maxYValue: Double {
        maxCumulative * 1.15
    }
    
    // Latest date with actual spending
    var maxSpendingDate: Date {
        let nonZeroDays = chartData.filter { $0.amount > 0 }
        return nonZeroDays.last?.date ?? startDate
    }
    
    // Cumulative chart data truncated to the latest spending date
    var lineChartData: [CumulativeExpenseItem] {
        let limitDate = maxSpendingDate
        return cumulativeChartData.filter { $0.date <= limitDate }
    }
    
    // Match selected date to cumulative item
    var selectedCumulativeItem: CumulativeExpenseItem? {
        guard let selectedDate = rawSelectedDate else { return nil }
        let calendar = Calendar.current
        return cumulativeChartData.first { calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }
    
    // Match selected date to average cumulative item
    var selectedAverageItem: AverageExpenseItem? {
        guard let selectedDate = rawSelectedDate else { return nil }
        return averageChartData.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }
    
    // Previous month's total (last value or selected)
    private var previousMonthTotal: Decimal {
        if let selectedAvg = selectedAverageItem {
            return selectedAvg.cumulativeAmount
        }
        return previousPeriodCumulative.last ?? Decimal.zero
    }
    
    // Current month display value
    private var currentMonthTotal: Decimal {
        if let selectedItem = selectedCumulativeItem {
            return selectedItem.cumulativeAmount
        }
        return expense
    }
    
    // Short month name for current period
    private var currentMonthName: String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.selectedLanguage.locale
        formatter.dateFormat = "MMMM"
        return formatter.string(from: startDate)
    }
    
    // Short month name for previous period
    private var previousMonthName: String {
        let calendar = Calendar.current
        guard let prevDate = calendar.date(byAdding: .month, value: -1, to: startDate) else {
            return L10n.Analysis.previousMonth
        }
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.selectedLanguage.locale
        formatter.dateFormat = "MMMM"
        return formatter.string(from: prevDate)
    }
    
    var body: some View {
        VStack(spacing: compact ? 12 : 16) {
            if showChart {
                // ── Header: Two-column legend like Apple Health, with an optional
                // drill-in chevron on the trailing edge ──
                chartHeader

                // ── Chart: Two smooth lines. The chart now claims the space that the
                // former income/net toggle occupied, keeping the card the same height. ──
                chartView
                    .frame(height: compact ? 130 : 150)
            } else {
                // Standard Net Total Header for non-chart summary (like Analysis View)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Analysis.net.uppercased())
                            .appFont(.caption2, weight: .bold)
                            .foregroundStyle(mutedTextColor)

                        Text(net.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                            .appFont(.title, weight: .bold)
                            .foregroundStyle(netValueColor(isPositive: net >= 0))
                    }
                    Spacer()
                    if let onNavigateToPro {
                        proChevronButton(action: onNavigateToPro)
                    }
                }
            }
        }
        .padding(.vertical, compact ? 0 : 8)
    }

    // MARK: - Pro Drill-in Chevron

    @ViewBuilder
    private func proChevronButton(action: @escaping () -> Void) -> some View {
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
    
    // MARK: - Chart Header (Apple Health Style)
    
    @ViewBuilder
    private var chartHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            // Current Month Column
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(ThemeManager.shared.expenseColor)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(haloColor, lineWidth: tintedBackground ? 1 : 0))
                    Text("analysis.expenseInPeriod".localized(with: isFullMonthSelected ? currentMonthName : L10n.Filter.thisMonth))
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(mutedTextColor)
                }

                Text(currentMonthTotal.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                    .appFont(compact ? .title3 : .title2, weight: .bold)
                    .foregroundStyle(expenseValueColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Previous Month Column
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(referenceDotColor)
                        .frame(width: 8, height: 8)
                    Text("analysis.expenseInPeriod".localized(with: isFullMonthSelected ? previousMonthName : L10n.Analysis.previousPeriod))
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(mutedTextColor)
                }

                Text(previousMonthTotal.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                    .appFont(compact ? .title3 : .title2, weight: .bold)
                    .foregroundStyle(previousValueColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Drill-in to the full Pro analytics dashboard (Home only).
            if let onNavigateToPro {
                proChevronButton(action: onNavigateToPro)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: rawSelectedDate == nil)
    }
    
    // MARK: - Chart View (Clean Two-Line)
    
    @ViewBuilder
    private var chartView: some View {
        Chart {
            // 1. Previous Month Reference Line (grey, thinner)
            if !averageChartData.isEmpty {
                ForEach(averageChartData) { item in
                    LineMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Previous", Double(truncating: item.cumulativeAmount as NSDecimalNumber)),
                        series: .value("Series", "Previous")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(referenceLineColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
            }
            
            // 2. Current Month Line (bold, colored, only up to max spending date)
            ForEach(lineChartData) { item in
                LineMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Current", Double(truncating: item.cumulativeAmount as NSDecimalNumber)),
                    series: .value("Series", "Current")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(ThemeManager.shared.expenseColor)
                .lineStyle(StrokeStyle(lineWidth: 3))
            }
            
            // 3. Selection Overlay
            if let selectedItem = selectedCumulativeItem {
                // Vertical rule
                RuleMark(
                    x: .value("Selected", selectedItem.date, unit: .day)
                )
                .foregroundStyle(separatorColor)
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

                // Point on current line
                if selectedItem.date <= maxSpendingDate {
                    PointMark(
                        x: .value("Selected", selectedItem.date, unit: .day),
                        y: .value("Current", Double(truncating: selectedItem.cumulativeAmount as NSDecimalNumber))
                    )
                    .foregroundStyle(ThemeManager.shared.expenseColor)
                    .symbolSize(60)
                }
                
                // Point on reference line
                if let selectedAvg = selectedAverageItem {
                    PointMark(
                        x: .value("Selected", selectedAvg.date, unit: .day),
                        y: .value("Previous", Double(truncating: selectedAvg.cumulativeAmount as NSDecimalNumber))
                    )
                    .foregroundStyle(referenceDotColor)
                    .symbolSize(60)
                }
            } else {
                // Endpoint dot on current month line
                if let lastPoint = lineChartData.last {
                    PointMark(
                        x: .value("Date", lastPoint.date, unit: .day),
                        y: .value("Current", Double(truncating: lastPoint.cumulativeAmount as NSDecimalNumber))
                    )
                    .foregroundStyle(ThemeManager.shared.expenseColor)
                    .symbolSize(40)
                }
                
                // Endpoint dot on previous month line
                if let lastAvg = averageChartData.last {
                    PointMark(
                        x: .value("Date", lastAvg.date, unit: .day),
                        y: .value("Previous", Double(truncating: lastAvg.cumulativeAmount as NSDecimalNumber))
                    )
                    .foregroundStyle(referenceDotColor)
                    .symbolSize(36)
                }
            }
        }
        .chartXSelection(value: $rawSelectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisValueLabel(format: .dateTime.day())
                    .font(.app(.caption2))
                    .foregroundStyle(mutedTextColor)
            }
        }
        .chartYScale(domain: 0...maxYValue)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(gridlineColor)
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(doubleValue.formattedAmountShort(for: CurrencyManager.shared.preferredCurrencyCode))
                            .font(.app(.caption2))
                            .foregroundStyle(mutedTextColor)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        // Each period's data spans a different date range, so morphing marks between
        // them (Swift Charts' default) reads as a jittery wobble. Give the chart a
        // fresh identity per period instead and simply cross-fade.
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
