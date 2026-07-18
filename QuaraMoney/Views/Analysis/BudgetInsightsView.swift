import SwiftUI
import SwiftData
import Charts

/// Analytics dashboard showing budget health metrics and insights
struct BudgetInsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Budget> { $0.deletedAt == nil }) private var budgets: [Budget]
    // Budgets only consider non-event transactions — scope the query accordingly.
    @Query(filter: #Predicate<Transaction> { $0.event == nil && $0.deletedAt == nil }) private var transactions: [Transaction]

    @State private var selectedTimeRange: InsightTimeRange = .sixMonths
    
    private var preferredCurrency: String {
        CurrencyManager.shared.preferredCurrencyCode
    }
    
    private struct InsightsSnapshot {
        let activeBudgets: [Budget]
        let performanceScore: Double
        let spendingTrend: SpendingTrend
        let overspendingCategories: [CategoryOverspend]
        let monthlyBudgetData: [MonthlyBudgetStat]
        let recurringCount: Int
        let spendingByBudgetID: [UUID: Decimal]
    }

    /// Computes every insight from one shared spending pass. The previous body
    /// re-scanned the complete transaction array for each metric and row.
    private func makeInsightsSnapshot() -> InsightsSnapshot {
        let calendar = Calendar.current
        let now = Date()
        let activeBudgets = budgets.filter(\.isActive)
        let completedBudgets = budgets.filter(\.isPeriodEnded)
        let spending = BudgetCalculator.spendingByBudget(
            for: budgets,
            transactions: transactions,
            targetCurrency: preferredCurrency
        )

        func recentCompleted(months: Int) -> [Budget] {
            let cutoff = calendar.date(byAdding: .month, value: -months, to: now) ?? now
            return completedBudgets.filter { $0.startDate >= cutoff }
        }

        func averageRatio(_ source: [Budget]) -> Double {
            let ratios = source.compactMap { budget -> Double? in
                guard budget.effectiveLimit > 0 else { return nil }
                return Double(truncating: (spending[budget.id] ?? 0) as NSNumber)
                    / Double(truncating: budget.effectiveLimit as NSNumber)
            }
            return ratios.isEmpty ? 0 : ratios.reduce(0, +) / Double(ratios.count)
        }

        let performanceBudgets = recentCompleted(months: selectedTimeRange.months)
        let performanceScore: Double
        if performanceBudgets.isEmpty {
            performanceScore = 0
        } else {
            let successful = performanceBudgets.filter {
                (spending[$0.id] ?? 0) <= $0.effectiveLimit
            }
            performanceScore = Double(successful.count) / Double(performanceBudgets.count)
        }

        let trendBudgets = recentCompleted(months: 3)
        let spendingTrend: SpendingTrend
        if trendBudgets.count < 2 {
            spendingTrend = .stable
        } else {
            let midpoint = trendBudgets.count / 2
            let change = averageRatio(Array(trendBudgets.prefix(midpoint)))
                - averageRatio(Array(trendBudgets.suffix(from: midpoint)))
            spendingTrend = change > 0.1 ? .increasing : (change < -0.1 ? .decreasing : .stable)
        }

        var categoryStats: [UUID: (overspend: Int, total: Int)] = [:]
        for budget in completedBudgets {
            guard let categoryID = budget.category?.id else { continue }
            var stats = categoryStats[categoryID] ?? (0, 0)
            stats.total += 1
            if (spending[budget.id] ?? 0) > budget.effectiveLimit {
                stats.overspend += 1
            }
            categoryStats[categoryID] = stats
        }
        let overspending: [CategoryOverspend] = categoryStats.compactMap { entry in
            let (categoryID, stats) = entry
            guard stats.total >= 2,
                  let category = budgets.first(where: { $0.category?.id == categoryID })?.category else {
                return nil
            }
            let rate = Double(stats.overspend) / Double(stats.total)
            guard rate > 0.3 else { return nil }
            return CategoryOverspend(category: category, overspendRate: rate, totalPeriods: stats.total)
        }.sorted { $0.overspendRate > $1.overspendRate }

        let cutoff = calendar.date(byAdding: .month, value: -selectedTimeRange.months, to: now) ?? now
        var monthlyStats: [Date: MonthlyBudgetStat] = [:]
        for budget in budgets where budget.startDate >= cutoff {
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: budget.startDate)) ?? budget.startDate
            var stat = monthlyStats[month] ?? MonthlyBudgetStat(month: month, budgeted: 0, spent: 0, budgetCount: 0)
            stat.budgeted += CurrencyManager.shared.convert(
                amount: budget.effectiveLimit,
                from: budget.currencyCode,
                to: preferredCurrency
            )
            stat.spent += spending[budget.id] ?? 0
            stat.budgetCount += 1
            monthlyStats[month] = stat
        }

        return InsightsSnapshot(
            activeBudgets: activeBudgets,
            performanceScore: performanceScore,
            spendingTrend: spendingTrend,
            overspendingCategories: overspending,
            monthlyBudgetData: monthlyStats.values.sorted { $0.month < $1.month },
            recurringCount: budgets.filter(\.isRecurring).count,
            spendingByBudgetID: spending
        )
    }
    
    var body: some View {
        let snapshot = makeInsightsSnapshot()

        ScrollView {
            VStack(spacing: 20) {
                // Time Range Picker
                Picker(L10n.Filter.title, selection: $selectedTimeRange) {
                    ForEach(InsightTimeRange.allCases, id: \.self) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Performance Score Card
                PerformanceScoreCard(
                    score: snapshot.performanceScore,
                    trend: snapshot.spendingTrend,
                    activeBudgetsCount: snapshot.activeBudgets.count
                )
                .padding(.horizontal)
                
                // Monthly Trend Chart
                if !snapshot.monthlyBudgetData.isEmpty {
                    MonthlyTrendChart(data: snapshot.monthlyBudgetData)
                        .padding(.horizontal)
                }
                
                // Key Metrics
                HStack(spacing: 12) {
                    MetricCard(
                        title: "budget.budgetsMet".localized,
                        value: "\(Int(snapshot.performanceScore * 100))%",
                        subtitle: "common.last".localized + " \(selectedTimeRange.months) " + "common.months".localized,
                        color: snapshot.performanceScore >= 0.7 ? ThemeManager.shared.incomeColor : (snapshot.performanceScore >= 0.5 ? .orange : ThemeManager.shared.expenseColor)
                    )
                    
                    MetricCard(
                        title: "budget.activeBudgets".localized,
                        value: "\(snapshot.activeBudgets.count)",
                        subtitle: snapshot.recurringCount > 0 ? "\(snapshot.recurringCount) \(L10n.Budget.recurring.lowercased())" : "common.none".localized,
                        color: .accentColor
                    )
                }
                .padding(.horizontal)
                
                // Overspending Categories
                if !snapshot.overspendingCategories.isEmpty {
                    OverspendingCategoriesCard(categories: snapshot.overspendingCategories)
                        .padding(.horizontal)
                }
                
                // Active Budgets Summary
                if !snapshot.activeBudgets.isEmpty {
                    ActiveBudgetsSummary(
                        budgets: snapshot.activeBudgets,
                        spendingByBudgetID: snapshot.spendingByBudgetID
                    )
                        .padding(.horizontal)
                }
                
                // Tips & Recommendations
                BudgetTipsCard(
                    performanceScore: snapshot.performanceScore,
                    overspendingCategories: snapshot.overspendingCategories
                )
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(L10n.Budget.insights)
        .background(Color(.systemGroupedBackground))
    }
    
}

// MARK: - Supporting Types

enum InsightTimeRange: String, CaseIterable {
    case threeMonths
    case sixMonths
    case oneYear
    
    var displayName: String {
        switch self {
        case .threeMonths: return "3 \("common.months".localized)"
        case .sixMonths: return "6 \("common.months".localized)"
        case .oneYear: return "1 \(L10n.Filter.year)"
        }
    }
    
    var months: Int {
        switch self {
        case .threeMonths: return 3
        case .sixMonths: return 6
        case .oneYear: return 12
        }
    }
}

enum SpendingTrend {
    case increasing
    case decreasing
    case stable
    
    var icon: String {
        switch self {
        case .increasing: return "arrow.up.right"
        case .decreasing: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }
    
    var color: Color {
        switch self {
        case .increasing: return ThemeManager.shared.expenseColor
        case .decreasing: return ThemeManager.shared.incomeColor
        case .stable: return .accentColor
        }
    }
    
    var description: String {
        switch self {
        case .increasing: return "Spending increasing"
        case .decreasing: return "Spending decreasing"
        case .stable: return "Spending stable"
        }
    }
}

struct CategoryOverspend: Identifiable {
    var id: UUID { category.id }
    let category: Category
    let overspendRate: Double
    let totalPeriods: Int
    
    var percentage: String {
        "\(Int(overspendRate * 100))%"
    }
}

struct MonthlyBudgetStat: Identifiable {
    var id: Date { month }
    let month: Date
    var budgeted: Decimal
    var spent: Decimal
    var budgetCount: Int
    
    var utilizationRate: Double {
        guard budgeted > 0 else { return 0 }
        return Double(truncating: spent as NSNumber) / Double(truncating: budgeted as NSNumber)
    }
}

// MARK: - Component Views

struct PerformanceScoreCard: View {
    let score: Double
    let trend: SpendingTrend
    let activeBudgetsCount: Int
    
    private var scoreColor: Color {
        if score >= 0.8 { return ThemeManager.shared.incomeColor }
        if score >= 0.6 { return .orange }
        return ThemeManager.shared.expenseColor
    }
    
    private var scoreGrade: String {
        if score >= 0.9 { return "A" }
        if score >= 0.8 { return "B" }
        if score >= 0.7 { return "C" }
        if score >= 0.6 { return "D" }
        return "F"
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("budget.performance".localized)
                        .appFont(.headline)
                    
                    HStack(spacing: 8) {
                        Image(systemName: trend.icon)
                            .foregroundStyle(trend.color)
                        Text(trend.description)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Score Circle
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 8)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(score))
                        .stroke(scoreColor.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    
                    Text(scoreGrade)
                        .appFont(.title, weight: .bold)
                        .foregroundStyle(scoreColor)
                }
                .frame(width: 60, height: 60)
            }
            
            // Score breakdown
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("\(Int(score * 100))%")
                        .appFont(.title3, weight: .bold)
                    Text("budget.successRate".localized)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                    .frame(height: 40)
                
                VStack(spacing: 4) {
                    Text("\(activeBudgetsCount)")
                        .appFont(.title3, weight: .bold)
                    Text(L10n.Budget.Filter.active)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

struct MonthlyTrendChart: View {
    let data: [MonthlyBudgetStat]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("budget.monthlyUtilization".localized)
                .appFont(.headline)
            
            Chart {
                ForEach(data) { stat in
                    BarMark(
                        x: .value("Month", stat.month, unit: .month),
                        y: .value("Budgeted", stat.budgeted)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.3))
                    .cornerRadius(4)
                    
                    BarMark(
                        x: .value("Month", stat.month, unit: .month),
                        y: .value("Spent", stat.spent)
                    )
                    .foregroundStyle(stat.spent > stat.budgeted ? ThemeManager.shared.expenseColor.gradient : ThemeManager.shared.incomeColor.gradient)
                    .cornerRadius(4)
                }
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                        .font(.app(.caption2))
                }
            }
            
            // Legend
            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.3))
                        .frame(width: 10, height: 10)
                    Text("budget.budgeted".localized)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(ThemeManager.shared.incomeColor)
                        .frame(width: 10, height: 10)
                    Text("budget.underBudget".localized)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(ThemeManager.shared.expenseColor)
                        .frame(width: 10, height: 10)
                    Text("budget.overBudget".localized)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .appFont(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .appFont(.title, weight: .bold)
                .foregroundStyle(color)
            
            Text(subtitle)
                .appFont(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

struct OverspendingCategoriesCard: View {
    let categories: [CategoryOverspend]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("budget.attentionCategories".localized)
                    .appFont(.headline)
            }
            
            ForEach(categories.prefix(3)) { item in
                HStack {
                    Image(systemName: item.category.icon)
                        .foregroundStyle(Color(hex: item.category.colorHex) ?? .gray)
                        .frame(width: 30)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.category.displayName)
                            .appFont(.subheadline)
                        Text("budget.insights.overBudgetFrequency".localized(with: item.percentage))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("budget.insights.periodsCount".localized(with: item.totalPeriods))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1)) // Keep semantic warning color for overspending
        .cornerRadius(16)
    }
}

struct ActiveBudgetsSummary: View {
    let budgets: [Budget]
    let spendingByBudgetID: [UUID: Decimal]
    
    private var preferredCurrency: String {
        CurrencyManager.shared.preferredCurrencyCode
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("budget.activeBudgetsStatus".localized)
                .appFont(.headline)
            
            ForEach(budgets.prefix(5)) { budget in
                let spent = spendingByBudgetID[budget.id] ?? 0
                let limit = CurrencyManager.shared.convert(
                    amount: budget.effectiveLimit,
                    from: budget.currencyCode,
                    to: preferredCurrency
                )
                let progress = limit > 0 ? Double(truncating: spent as NSNumber) / Double(truncating: limit as NSNumber) : 0
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(budget.displayName)
                            .appFont(.subheadline, weight: .medium)
                        
                        ProgressView(value: min(progress, 1.0))
                            .tint(progress > 1 ? ThemeManager.shared.expenseColor : (progress > 0.8 ? .orange : ThemeManager.shared.incomeColor))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(progress * 100))%")
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(progress > 1 ? ThemeManager.shared.expenseColor : (progress > 0.8 ? .orange : ThemeManager.shared.incomeColor))
                        
                        Text("\(budget.daysRemaining)d left")
                            .appFont(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
    
}

struct BudgetTipsCard: View {
    let performanceScore: Double
    let overspendingCategories: [CategoryOverspend]
    
    private var tips: [BudgetTip] {
        var tips: [BudgetTip] = []
        
        if performanceScore < 0.5 {
            tips.append(BudgetTip(
                icon: "lightbulb.fill",
                title: "budget.tip.increase".localized,
                description: "budget.tip.increaseDesc".localized
            ))
        }
        
        if !overspendingCategories.isEmpty {
            let topCategory = overspendingCategories[0]
            tips.append(BudgetTip(
                icon: "exclamationmark.circle.fill",
                title: String(format: "budget.tip.review".localized, topCategory.category.displayName),
                description: String(format: "budget.tip.reviewDesc".localized, topCategory.percentage)
            ))
        }
        
        if performanceScore >= 0.8 {
            tips.append(BudgetTip(
                icon: "star.fill",
                title: "budget.tip.greatJob".localized,
                description: "budget.tip.greatJobDesc".localized
            ))
        }
        
        tips.append(BudgetTip(
            icon: "calendar.badge.clock",
            title: "budget.tip.checkWeekly".localized,
            description: "budget.tip.checkWeeklyDesc".localized
        ))
        
        return tips
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("budget.tips".localized)
                .appFont(.headline)
            
            ForEach(tips.prefix(3), id: \.title) { tip in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: tip.icon)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tip.title)
                            .appFont(.subheadline, weight: .medium)
                        Text(tip.description)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

struct BudgetTip {
    let icon: String
    let title: String
    let description: String
}

#Preview {
    NavigationStack {
        BudgetInsightsView()
    }
    .modelContainer(for: [Budget.self, Transaction.self, TransactionLocation.self, Category.self], inMemory: true)
}
