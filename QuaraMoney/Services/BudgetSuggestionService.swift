import Foundation
import SwiftData

/// Service for analyzing spending history and suggesting budget amounts
@MainActor
class BudgetSuggestionService {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Budget Suggestions
    
    /// Suggest a budget amount for a specific category based on spending history
    func suggestBudgetAmount(
        for category: Category,
        periodType: BudgetPeriodType = .monthly,
        months: Int = 3,
        bufferPercent: Double = 0.1
    ) -> BudgetSuggestion {
        let transactions = fetchTransactions(for: category, months: months)
        
        guard !transactions.isEmpty else {
            return BudgetSuggestion(
                suggestedAmount: nil,
                averageSpending: 0,
                minSpending: 0,
                maxSpending: 0,
                transactionCount: 0,
                confidence: .noData,
                periodType: periodType
            )
        }
        
        // Group transactions by period
        let periodicAmounts = groupTransactionsByPeriod(transactions, periodType: periodType)
        
        guard !periodicAmounts.isEmpty else {
            return BudgetSuggestion(
                suggestedAmount: nil,
                averageSpending: 0,
                minSpending: 0,
                maxSpending: 0,
                transactionCount: transactions.count,
                confidence: .noData,
                periodType: periodType
            )
        }
        
        let targetCurrency = CurrencyManager.shared.preferredCurrencyCode
        
        // Calculate statistics
        let amounts = periodicAmounts.map { (period, txns) -> Decimal in
            txns.reduce(Decimal.zero) { total, txn in
                total + CurrencyManager.shared.convert(
                    amount: txn.amount,
                    from: txn.currencyCode,
                    to: targetCurrency
                )
            }
        }
        
        let average = amounts.reduce(Decimal.zero, +) / Decimal(amounts.count)
        let minAmount = amounts.min() ?? 0
        let maxAmount = amounts.max() ?? 0
        
        // Add buffer to suggestion
        let bufferedAmount = average * (1 + Decimal(bufferPercent))
        
        // Determine confidence level
        let confidence = determineConfidence(amounts: amounts, transactionCount: transactions.count)
        
        return BudgetSuggestion(
            suggestedAmount: bufferedAmount,
            averageSpending: average,
            minSpending: minAmount,
            maxSpending: maxAmount,
            transactionCount: transactions.count,
            confidence: confidence,
            periodType: periodType
        )
    }
    

    
    /// Suggest total budget based on all expenses
    func suggestTotalBudget(
        periodType: BudgetPeriodType = .monthly,
        months: Int = 3,
        bufferPercent: Double = 0.1
    ) -> BudgetSuggestion {
        let transactions = fetchAllExpenseTransactions(months: months)
        
        guard !transactions.isEmpty else {
            return BudgetSuggestion(
                suggestedAmount: nil,
                averageSpending: 0,
                minSpending: 0,
                maxSpending: 0,
                transactionCount: 0,
                confidence: .noData,
                periodType: periodType
            )
        }
        
        let periodicAmounts = groupTransactionsByPeriod(transactions, periodType: periodType)
        let targetCurrency = CurrencyManager.shared.preferredCurrencyCode
        
        let amounts = periodicAmounts.map { (period, txns) -> Decimal in
            txns.reduce(Decimal.zero) { total, txn in
                total + CurrencyManager.shared.convert(
                    amount: txn.amount,
                    from: txn.currencyCode,
                    to: targetCurrency
                )
            }
        }
        
        guard !amounts.isEmpty else {
            return BudgetSuggestion(
                suggestedAmount: nil,
                averageSpending: 0,
                minSpending: 0,
                maxSpending: 0,
                transactionCount: transactions.count,
                confidence: .noData,
                periodType: periodType
            )
        }
        
        let average = amounts.reduce(Decimal.zero, +) / Decimal(amounts.count)
        let minAmount = amounts.min() ?? 0
        let maxAmount = amounts.max() ?? 0
        let bufferedAmount = average * (1 + Decimal(bufferPercent))
        let confidence = determineConfidence(amounts: amounts, transactionCount: transactions.count)
        
        return BudgetSuggestion(
            suggestedAmount: bufferedAmount,
            averageSpending: average,
            minSpending: minAmount,
            maxSpending: maxAmount,
            transactionCount: transactions.count,
            confidence: confidence,
            periodType: periodType
        )
    }
    
    // MARK: - Spending Insights
    
    /// Get categories that frequently overspend (for insights)
    func getOverspendingCategories(budgets: [Budget], transactions: [Transaction]) -> [CategoryInsight] {
        var insights: [CategoryInsight] = []
        
        for budget in budgets {
            guard let category = budget.category else { continue }
            
            // Get historical overspend rate
            let historicalBudgets = budgets.filter { 
                $0.category?.id == category.id && $0.isPeriodEnded
            }
            
            var overspendCount = 0
            for historicalBudget in historicalBudgets {
                let spent = calculateSpending(for: historicalBudget, transactions: transactions)
                if spent > historicalBudget.effectiveLimit {
                    overspendCount += 1
                }
            }
            
            let totalPeriods = historicalBudgets.count
            guard totalPeriods > 0 else { continue }
            
            let overspendRate = Double(overspendCount) / Double(totalPeriods)
            
            if overspendRate > 0.3 { // 30% overspend rate threshold
                insights.append(CategoryInsight(
                    category: category,
                    overspendRate: overspendRate,
                    totalPeriods: totalPeriods,
                    overspendPeriods: overspendCount
                ))
            }
        }
        
        return insights.sorted { $0.overspendRate > $1.overspendRate }
    }
    
    // MARK: - Private Helpers
    
    private func fetchTransactions(for category: Category, months: Int) -> [Transaction] {
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .month, value: -months, to: endDate) else {
            return []
        }
        
        let categoryId = category.id
        let expenseType = TransactionType.expense
        
        // Filter out archived wallets for budget suggestions
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { txn in
                txn.type == expenseType &&
                txn.date >= startDate && txn.date <= endDate &&
                txn.category?.id == categoryId &&
                txn.sourceWallet?.isArchived != true
            },
            sortBy: [SortDescriptor(\Transaction.date)]
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching transactions: \(error)")
            return []
        }
    }
    
    private func fetchAllExpenseTransactions(months: Int) -> [Transaction] {
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .month, value: -months, to: endDate) else {
            return []
        }
        
        let expenseType = TransactionType.expense
        
        // Filter out archived wallets for budget suggestions
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { txn in
                txn.type == expenseType &&
                txn.date >= startDate && txn.date <= endDate &&
                txn.sourceWallet?.isArchived != true
            },
            sortBy: [SortDescriptor(\Transaction.date)]
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching transactions: \(error)")
            return []
        }
    }
    
    private func groupTransactionsByPeriod(_ transactions: [Transaction], periodType: BudgetPeriodType) -> [Date: [Transaction]] {
        var grouped: [Date: [Transaction]] = [:]
        let calendar = Calendar.current
        
        for txn in transactions {
            let periodStart = periodType.periodStart(containing: txn.date, calendar: calendar)
            grouped[periodStart, default: []].append(txn)
        }
        
        return grouped
    }
    
    private func calculateSpending(for budget: Budget, transactions: [Transaction]) -> Decimal {
        let periodRange = budget.periodDateRange
        let targetCurrency = CurrencyManager.shared.preferredCurrencyCode
        
        let relevantTransactions = transactions.filter { txn in
            guard txn.type == .expense,
                  txn.date >= periodRange.start && txn.date < periodRange.end else {
                return false
            }
            
            if budget.isTotalBudget {
                return true
            } else if let categoryId = budget.category?.id {
                return txn.category?.id == categoryId
            }
            
            // Check if transaction category is in the budget's tracked categories using the new many-to-many relationship
            // This handles the new multi-category budget system
            if let transactionCategoryId = txn.category?.id {
                let trackedIds = budget.trackedCategoryIds
                return trackedIds.contains(transactionCategoryId)
            }
            
            return false
        }
        
        return relevantTransactions.reduce(Decimal.zero) { total, txn in
            total + CurrencyManager.shared.convert(
                amount: txn.amount,
                from: txn.currencyCode,
                to: targetCurrency
            )
        }
    }
    
    private func determineConfidence(amounts: [Decimal], transactionCount: Int) -> SuggestionConfidence {
        if amounts.count < 2 || transactionCount < 5 {
            return .low
        }
        
        // Calculate coefficient of variation (standard deviation / mean)
        let mean = amounts.reduce(Decimal.zero, +) / Decimal(amounts.count)
        guard mean > 0 else { return .low }
        
        let variance = amounts.reduce(Decimal.zero) { result, amount in
            let diff = amount - mean
            return result + (diff * diff)
        } / Decimal(amounts.count)
        
        let stdDev = sqrt(Double(truncating: variance as NSNumber))
        let cv = stdDev / Double(truncating: mean as NSNumber)
        
        if cv < 0.2 && amounts.count >= 3 {
            return .high
        } else if cv < 0.5 && amounts.count >= 2 {
            return .medium
        } else {
            return .low
        }
    }
}

// MARK: - Supporting Types

struct BudgetSuggestion {
    let suggestedAmount: Decimal?
    let averageSpending: Decimal
    let minSpending: Decimal
    let maxSpending: Decimal
    let transactionCount: Int
    let confidence: SuggestionConfidence
    let periodType: BudgetPeriodType
    
    var hasData: Bool {
        suggestedAmount != nil
    }
    
    var formattedSuggestion: String {
        guard let amount = suggestedAmount else { return "Not enough data" }
        return amount.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode))
    }
    
    var confidenceDescription: String {
        switch confidence {
        case .high: return "High confidence based on consistent spending"
        case .medium: return "Medium confidence - some variation in spending"
        case .low: return "Low confidence - limited or variable data"
        case .noData: return "Not enough transaction history"
        }
    }
}

enum SuggestionConfidence: String {
    case high
    case medium
    case low
    case noData
    
    var color: String {
        switch self {
        case .high: return "#10B981"    // Green
        case .medium: return "#F59E0B"  // Amber
        case .low: return "#EF4444"     // Red
        case .noData: return "#6B7280"  // Gray
        }
    }
    
    var icon: String {
        switch self {
        case .high: return "checkmark.circle.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .low: return "questionmark.circle.fill"
        case .noData: return "minus.circle.fill"
        }
    }
}

struct CategoryInsight: Identifiable {
    var id: UUID { category.id }
    let category: Category
    let overspendRate: Double
    let totalPeriods: Int
    let overspendPeriods: Int
    
    var overspendPercentage: String {
        "\(Int(overspendRate * 100))%"
    }
    
    var recommendation: String {
        if overspendRate > 0.7 {
            return "Consider increasing this budget significantly"
        } else if overspendRate > 0.5 {
            return "Consider increasing this budget"
        } else {
            return "Monitor this category closely"
        }
    }
}
