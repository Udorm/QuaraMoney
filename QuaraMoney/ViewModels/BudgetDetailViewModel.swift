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

    // MARK: - Init
    init(budget: Budget, transactions: [Transaction]) {
        self.budget = budget
        self.transactions = transactions
    }

    // MARK: - Derived Values

    var preferredCurrency: String {
        CurrencyManager.shared.preferredCurrencyCode
    }

    /// Transactions relevant to this budget (filtered by category, period, expense type)
    var relevantTransactions: [Transaction] {
        let periodRange = budget.periodDateRange
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
            targetCurrency: preferredCurrency
        )
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
