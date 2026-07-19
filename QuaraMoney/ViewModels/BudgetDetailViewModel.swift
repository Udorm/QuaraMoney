import Foundation
import Observation

/// ViewModel for `BudgetDetailView`.
///
/// Extracts all budget-period calculations that were previously
/// inline computed properties inside the view.
@Observable
final class BudgetDetailViewModel {
    // MARK: - Inputs
    let budget: Budget
    let transactions: [Transaction]
    let periodOffset: Int

    // MARK: - Init
    init(budget: Budget, transactions: [Transaction], periodOffset: Int = 0) {
        self.budget = budget
        self.transactions = transactions
        self.periodOffset = periodOffset
    }

    // MARK: - Derived Values

    var preferredCurrency: String {
        CurrencyManager.shared.preferredCurrencyCode
    }

    /// Transactions relevant to this budget (filtered by category, period, expense type)
    var relevantTransactions: [Transaction] {
        let periodRange = displayedPeriodRange
        let categoryIds = budget.trackedCategoryIds

        return transactions.filter { txn in
            guard txn.type == .expense,
                  txn.event == nil,
                  txn.date >= periodRange.start && txn.date < periodRange.end else {
                return false
            }

            if categoryIds.isEmpty { return true }
            guard let txnCatId = txn.category?.id else { return false }
            return categoryIds.contains(txnCatId)
        }.sorted { $0.date > $1.date }
    }

    /// Total spending converted to preferred currency
    var totalSpent: Decimal {
        BudgetCalculator.calculateSpending(
            for: budget,
            transactions: transactions,
            targetCurrency: preferredCurrency,
            periodRange: displayedPeriodRange
        )
    }

    var showsPeriodNavigator: Bool { budget.periodType != .custom }

    var displayedPeriodRange: (start: Date, end: Date) {
        guard showsPeriodNavigator, periodOffset != 0 else { return budget.periodDateRange }
        let calendar = Calendar.current
        let current = budget.periodDateRange.start
        let reference: Date
        switch budget.periodType {
        case .weekly: reference = calendar.date(byAdding: .weekOfYear, value: periodOffset, to: current) ?? current
        case .biweekly: reference = calendar.date(byAdding: .day, value: periodOffset * 14, to: current) ?? current
        case .monthly: reference = calendar.date(byAdding: .month, value: periodOffset, to: current) ?? current
        case .quarterly: reference = calendar.date(byAdding: .month, value: periodOffset * 3, to: current) ?? current
        case .yearly: reference = calendar.date(byAdding: .year, value: periodOffset, to: current) ?? current
        case .custom: return budget.periodDateRange
        }
        return budget.periodDateRange(containing: reference)
    }

    /// Budget limit converted to preferred currency
    var budgetLimitConverted: Decimal {
        BudgetCalculator.convertBudgetLimit(
            for: budget,
            transactions: transactions,
            targetCurrency: preferredCurrency
        )
    }

    /// Remaining amount
    var remaining: Decimal {
        budgetLimitConverted - totalSpent
    }

    /// Progress ratio (0.0 to 1.0+)
    var progress: Double {
        guard budgetLimitConverted > 0 else { return 0 }
        return Double(truncating: totalSpent as NSNumber) / Double(truncating: budgetLimitConverted as NSNumber)
    }

    var isOverBudget: Bool {
        totalSpent > budgetLimitConverted
    }

    /// Daily spending average
    var dailyAverage: Decimal {
        let daysElapsed = budget.totalDays - budget.daysRemaining
        guard daysElapsed > 0 else { return 0 }
        return totalSpent / Decimal(daysElapsed)
    }

    /// Projected spending at current rate
    var projectedSpending: Decimal {
        dailyAverage * Decimal(budget.totalDays)
    }

    /// Daily budget to stay on track
    var dailyBudget: Decimal {
        guard budget.daysRemaining > 0 else { return 0 }
        return max(remaining, 0) / Decimal(budget.daysRemaining)
    }

    var budgetIcon: String {
        if let category = budget.category {
            return category.icon
        }
        return "sum"
    }
}
