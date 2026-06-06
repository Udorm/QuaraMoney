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
    
    @Query(sort: \Budget.startDate, order: .reverse) private var budgets: [Budget]
    @State private var rawSelectedDate: Date? = nil
    @State private var showDetails = false
    
    init(
        income: Decimal,
        expense: Decimal,
        dailySections: [DailyTransactionSection] = [],
        startDate: Date = Date(),
        endDate: Date = Date(),
        showChart: Bool = true,
        previousPeriodCumulative: [Decimal] = []
    ) {
        self.income = income
        self.expense = expense
        self.dailySections = dailySections
        self.startDate = startDate
        self.endDate = endDate
        self.showChart = showChart
        self.previousPeriodCumulative = previousPeriodCumulative
    }
    
    // Dynamic properties
    var net: Decimal {
        income - expense
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
        formatter.locale = Locale.current
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
        formatter.locale = Locale.current
        formatter.dateFormat = "MMMM"
        return formatter.string(from: prevDate)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if showChart {
                // ── Header: Two-column legend like Apple Health ──
                chartHeader

                // ── Chart: Two smooth lines ──
                chartView
                    .frame(height: 120)
            } else {
                // Standard Net Total Header for non-chart summary (like Analysis View)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Analysis.net.uppercased())
                            .appFont(.caption2, weight: .bold)
                            .foregroundStyle(.secondary)

                        Text(net.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                            .appFont(.title, weight: .bold)
                            .foregroundStyle(net >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor)
                    }
                    Spacer()
                }
            }

            // Show/hide toggle for income & net details
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { showDetails.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Text(showDetails
                         ? L10n.Common.hide
                         : "\(L10n.Transaction.TransactionType.income) & \(L10n.Analysis.net)")
                        .appFont(.caption, weight: .semibold)
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .appFont(.caption2, weight: .semibold)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            if showDetails {
                metricsGridView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Chart Header (Apple Health Style)
    
    @ViewBuilder
    private var chartHeader: some View {
        HStack(alignment: .top, spacing: 0) {
            // Current Month Column
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(ThemeManager.shared.expenseColor)
                        .frame(width: 8, height: 8)
                    Text(isFullMonthSelected ? currentMonthName : L10n.Filter.thisMonth)
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
                
                Text(currentMonthTotal.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                    .appFont(.title2, weight: .bold)
                    .foregroundStyle(ThemeManager.shared.expenseColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Previous Month Column
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: 8, height: 8)
                    Text(isFullMonthSelected ? previousMonthName : L10n.Analysis.previousPeriod)
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
                
                Text(previousMonthTotal.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                    .appFont(.title2, weight: .bold)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .foregroundStyle(Color.gray.opacity(0.45))
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
                .foregroundStyle(Color(.separator).opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1))
                
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
                    .foregroundStyle(Color.gray)
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
                    .foregroundStyle(Color.gray.opacity(0.5))
                    .symbolSize(36)
                }
            }
        }
        .chartXSelection(value: $rawSelectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisValueLabel(format: .dateTime.day())
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYScale(domain: 0...maxYValue)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.08))
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(doubleValue.formattedAmountShort(for: CurrencyManager.shared.preferredCurrencyCode))
                            .font(.app(.caption2))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
    }
    
    @ViewBuilder
    private var metricsGridView: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(ThemeManager.shared.incomeColor)
                        .frame(width: 6, height: 6)
                    Text(L10n.Transaction.TransactionType.income.uppercased())
                        .appFont(.caption2, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
                Text(income.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                    .appFont(.subheadline, weight: .bold)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
                .frame(height: 24)
                .padding(.horizontal, 8)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(net >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor)
                        .frame(width: 6, height: 6)
                    Text(L10n.Analysis.net.uppercased())
                        .appFont(.caption2, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
                Text(net.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                    .appFont(.subheadline, weight: .bold)
                    .foregroundStyle(net >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
