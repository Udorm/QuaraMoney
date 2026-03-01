import SwiftUI
import SwiftData
import Charts

/// Analytics dashboard showing budget health metrics and insights
struct BudgetInsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var budgets: [Budget]
    @Query private var transactions: [Transaction]
    
    @State private var selectedTimeRange: InsightTimeRange = .sixMonths
    
    private var preferredCurrency: String {
        CurrencyManager.shared.preferredCurrencyCode
    }
    
    // MARK: - Computed Metrics
    
    private var activeBudgets: [Budget] {
        budgets.filter { $0.isActive }
    }
    
    private var completedBudgets: [Budget] {
        budgets.filter { $0.isPeriodEnded }
    }
    
    private var budgetPerformanceScore: Double {
        let recentBudgets = getRecentCompletedBudgets(months: selectedTimeRange.months)
        guard !recentBudgets.isEmpty else { return 0 }
        
        let successfulBudgets = recentBudgets.filter { budget in
            let spent = calculateSpending(for: budget)
            return spent <= budget.effectiveLimit
        }
        
        return Double(successfulBudgets.count) / Double(recentBudgets.count)
    }
    
    private var overallSpendingTrend: SpendingTrend {
        let recentBudgets = getRecentCompletedBudgets(months: 3)
        guard recentBudgets.count >= 2 else { return .stable }
        
        // Compare recent spending to older spending
        let midPoint = recentBudgets.count / 2
        let recentHalf = Array(recentBudgets.prefix(midPoint))
        let olderHalf = Array(recentBudgets.suffix(from: midPoint))
        
        let recentAvg = averageSpendingRatio(for: recentHalf)
        let olderAvg = averageSpendingRatio(for: olderHalf)
        
        let change = recentAvg - olderAvg
        if change > 0.1 {
            return .increasing
        } else if change < -0.1 {
            return .decreasing
        }
        return .stable
    }
    
    private var overspendingCategories: [CategoryOverspend] {
        var categoryStats: [UUID: (overspend: Int, total: Int)] = [:]
        
        for budget in completedBudgets {
            guard let categoryId = budget.category?.id else { continue }
            
            var stats = categoryStats[categoryId] ?? (0, 0)
            stats.total += 1
            
            let spent = calculateSpending(for: budget)
            if spent > budget.effectiveLimit {
                stats.overspend += 1
            }
            
            categoryStats[categoryId] = stats
        }
        
        return categoryStats.compactMap { (categoryId, stats) in
            guard stats.total >= 2,
                  let category = budgets.first(where: { $0.category?.id == categoryId })?.category else {
                return nil
            }
            
            let rate = Double(stats.overspend) / Double(stats.total)
            guard rate > 0.3 else { return nil } // 30% threshold
            
            return CategoryOverspend(
                category: category,
                overspendRate: rate,
                totalPeriods: stats.total
            )
        }.sorted { $0.overspendRate > $1.overspendRate }
    }
    
    private var monthlyBudgetData: [MonthlyBudgetStat] {
        let calendar = Calendar.current
        var monthlyStats: [Date: MonthlyBudgetStat] = [:]
        
        let cutoffDate = calendar.date(byAdding: .month, value: -selectedTimeRange.months, to: Date()) ?? Date()
        
        for budget in budgets {
            guard budget.startDate >= cutoffDate else { continue }
            
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: budget.startDate)) ?? budget.startDate
            
            var stat = monthlyStats[monthStart] ?? MonthlyBudgetStat(month: monthStart, budgeted: 0, spent: 0, budgetCount: 0)
            
            let limitConverted = CurrencyManager.shared.convert(
                amount: budget.effectiveLimit,
                from: budget.currencyCode,
                to: preferredCurrency
            )
            
            let spentConverted = calculateSpending(for: budget)
            
            stat.budgeted += limitConverted
            stat.spent += spentConverted
            stat.budgetCount += 1
            
            monthlyStats[monthStart] = stat
        }
        
        return monthlyStats.values.sorted { $0.month < $1.month }
    }
    
    var body: some View {
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
                    score: budgetPerformanceScore,
                    trend: overallSpendingTrend,
                    activeBudgetsCount: activeBudgets.count
                )
                .padding(.horizontal)
                
                // Monthly Trend Chart
                if !monthlyBudgetData.isEmpty {
                    MonthlyTrendChart(data: monthlyBudgetData)
                        .padding(.horizontal)
                }
                
                // Key Metrics
                HStack(spacing: 12) {
                    MetricCard(
                        title: "budget.budgetsMet".localized,
                        value: "\(Int(budgetPerformanceScore * 100))%",
                        subtitle: "common.last".localized + " \(selectedTimeRange.months) " + "common.months".localized,
                        color: budgetPerformanceScore >= 0.7 ? .green : (budgetPerformanceScore >= 0.5 ? .orange : .red)
                    )
                    
                    MetricCard(
                        title: "budget.activeBudgets".localized,
                        value: "\(activeBudgets.count)",
                        subtitle: budgets.filter { $0.isRecurring }.count > 0 ? "\(budgets.filter { $0.isRecurring }.count) \(L10n.Budget.recurring.lowercased())" : "common.none".localized,
                        color: .accentColor
                    )
                }
                .padding(.horizontal)
                
                // Overspending Categories
                if !overspendingCategories.isEmpty {
                    OverspendingCategoriesCard(categories: overspendingCategories)
                        .padding(.horizontal)
                }
                
                // Active Budgets Summary
                if !activeBudgets.isEmpty {
                    ActiveBudgetsSummary(budgets: activeBudgets, transactions: transactions)
                        .padding(.horizontal)
                }
                
                // Tips & Recommendations
                BudgetTipsCard(
                    performanceScore: budgetPerformanceScore,
                    overspendingCategories: overspendingCategories
                )
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(L10n.Budget.insights)
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Helper Methods
    
    private func getRecentCompletedBudgets(months: Int) -> [Budget] {
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .month, value: -months, to: Date()) ?? Date()
        
        return completedBudgets.filter { $0.startDate >= cutoffDate }
    }
    
    private func calculateSpending(for budget: Budget) -> Decimal {
        let periodRange = budget.periodDateRange
        
        let relevantTransactions = transactions.filter { txn in
            guard txn.type == .expense,
                  txn.date >= periodRange.start && txn.date < periodRange.end else {
                return false
            }
            
            if budget.isTotalBudget {
                return true
            } else if !budget.trackedCategoryIds.isEmpty {
                let categoryIds = budget.trackedCategoryIds
                return categoryIds.contains(txn.category?.id ?? UUID())
            }
            
            return false
        }
        
        return relevantTransactions.reduce(Decimal.zero) { total, txn in
            total + CurrencyManager.shared.convert(
                amount: txn.amount,
                from: txn.currencyCode,
                to: preferredCurrency
            )
        }
    }
    
    private func averageSpendingRatio(for budgets: [Budget]) -> Double {
        guard !budgets.isEmpty else { return 0 }
        
        let ratios = budgets.compactMap { budget -> Double? in
            let limit = budget.effectiveLimit
            guard limit > 0 else { return nil }
            let spent = calculateSpending(for: budget)
            return Double(truncating: spent as NSNumber) / Double(truncating: limit as NSNumber)
        }
        
        guard !ratios.isEmpty else { return 0 }
        return ratios.reduce(0, +) / Double(ratios.count)
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
        case .increasing: return .red
        case .decreasing: return .green
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
        if score >= 0.8 { return .green }
        if score >= 0.6 { return .orange }
        return .red
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
                        .font(.app(.headline))
                    
                    HStack(spacing: 8) {
                        Image(systemName: trend.icon)
                            .foregroundStyle(trend.color)
                        Text(trend.description)
                            .font(.app(.caption))
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
                        .font(.app(.title, weight: .bold))
                        .foregroundStyle(scoreColor)
                }
                .frame(width: 60, height: 60)
            }
            
            // Score breakdown
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("\(Int(score * 100))%")
                        .font(.app(.title3, weight: .bold))
                    Text("budget.successRate".localized)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                    .frame(height: 40)
                
                VStack(spacing: 4) {
                    Text("\(activeBudgetsCount)")
                        .font(.app(.title3, weight: .bold))
                    Text(L10n.Budget.Filter.active)
                        .font(.app(.caption))
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
                .font(.app(.headline))
            
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
                    .foregroundStyle(stat.spent > stat.budgeted ? Color.red.gradient : Color.green.gradient)
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
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                    Text("budget.underBudget".localized)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                    Text("budget.overBudget".localized)
                        .font(.app(.caption))
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
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.app(.title, weight: .bold))
                .foregroundStyle(color)
            
            Text(subtitle)
                .font(.app(.caption2))
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
                    .font(.app(.headline))
            }
            
            ForEach(categories.prefix(3)) { item in
                HStack {
                    Image(systemName: item.category.icon)
                        .foregroundStyle(Color(hex: item.category.colorHex) ?? .gray)
                        .frame(width: 30)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.category.name)
                            .font(.app(.subheadline))
                        Text("Over budget \(item.percentage) of the time")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("\(item.totalPeriods) periods")
                        .font(.app(.caption))
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
    let transactions: [Transaction]
    
    private var preferredCurrency: String {
        CurrencyManager.shared.preferredCurrencyCode
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("budget.activeBudgetsStatus".localized)
                .font(.app(.headline))
            
            ForEach(budgets.prefix(5)) { budget in
                let spent = calculateSpending(for: budget)
                let limit = CurrencyManager.shared.convert(
                    amount: budget.effectiveLimit,
                    from: budget.currencyCode,
                    to: preferredCurrency
                )
                let progress = limit > 0 ? Double(truncating: spent as NSNumber) / Double(truncating: limit as NSNumber) : 0
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(budget.displayName)
                            .font(.app(.subheadline, weight: .medium))
                        
                        ProgressView(value: min(progress, 1.0))
                            .tint(progress > 1 ? .red : (progress > 0.8 ? .orange : .green))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(progress * 100))%")
                            .font(.app(.caption, weight: .semibold))
                            .foregroundStyle(progress > 1 ? .red : (progress > 0.8 ? .orange : .green))
                        
                        Text("\(budget.daysRemaining)d left")
                            .font(.app(.caption2))
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
    
    private func calculateSpending(for budget: Budget) -> Decimal {
        let periodRange = budget.periodDateRange
        
        let relevantTransactions = transactions.filter { txn in
            guard txn.type == .expense,
                  txn.date >= periodRange.start && txn.date < periodRange.end else {
                return false
            }
            
            if budget.isTotalBudget {
                return true
            } else if !budget.trackedCategoryIds.isEmpty {
                let categoryIds = budget.trackedCategoryIds
                return categoryIds.contains(txn.category?.id ?? UUID())
            }
            
            return false
        }
        
        return relevantTransactions.reduce(Decimal.zero) { total, txn in
            total + CurrencyManager.shared.convert(
                amount: txn.amount,
                from: txn.currencyCode,
                to: preferredCurrency
            )
        }
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
                title: String(format: "budget.tip.review".localized, topCategory.category.name),
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
                .font(.app(.headline))
            
            ForEach(tips.prefix(3), id: \.title) { tip in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: tip.icon)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tip.title)
                            .font(.app(.subheadline, weight: .medium))
                        Text(tip.description)
                            .font(.app(.caption))
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
    .modelContainer(for: [Budget.self, Transaction.self, Category.self], inMemory: true)
}
