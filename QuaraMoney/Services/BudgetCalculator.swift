import Foundation

/// Shared budget calculation utility.
///
/// Centralises spending, income, and limit calculations that were
/// previously duplicated across `BudgetDetailView`, `BudgetListView`,
/// `BudgetSummarySection`, `BudgetInsightsView`, and `ActiveBudgetsSummary`.
enum BudgetCalculator {

    // MARK: - Spending

    /// Total expense spending for a budget period, converted to `targetCurrency`.
    ///
    /// Filters on: `.expense` type, within `periodDateRange`, not excluded from
    /// reports, not linked to an event, and matching the budget's tracked categories.
    static func calculateSpending(
        for budget: Budget,
        transactions: [Transaction],
        targetCurrency: String
    ) -> Decimal {
        let periodRange = budget.periodDateRange
        let categoryIds = budget.trackedCategoryIds          // empty → total budget

        let relevant = transactions.filter { txn in
            guard !txn.excludeFromReports,
                  txn.event == nil,
                  txn.type == .expense,
                  txn.date >= periodRange.start && txn.date < periodRange.end else {
                return false
            }

            // Total budget → all expenses; otherwise match categories
            if categoryIds.isEmpty { return true }
            guard let txnCatId = txn.category?.id else { return false }
            return categoryIds.contains(txnCatId)
        }

        return relevant.reduce(Decimal.zero) { total, txn in
            total + CurrencyManager.shared.convert(
                amount: txn.amount,
                from: txn.currencyCode,
                to: targetCurrency
            )
        }
    }

    // MARK: - Income

    /// Total income within a budget's period, converted to `targetCurrency`
    /// (defaults to the **budget's own** currency so percent-of-income limits
    /// can be calculated before a second conversion).
    static func calculateIncome(
        for budget: Budget,
        transactions: [Transaction],
        targetCurrency: String? = nil
    ) -> Decimal {
        let currency = targetCurrency ?? budget.currencyCode
        let periodRange = budget.periodDateRange

        let relevant = transactions.filter { txn in
            txn.event == nil &&
            txn.type == .income &&
            txn.date >= periodRange.start &&
            txn.date < periodRange.end
        }

        return relevant.reduce(Decimal.zero) { total, txn in
            total + CurrencyManager.shared.convert(
                amount: txn.amount,
                from: txn.currencyCode,
                to: currency
            )
        }
    }

    // MARK: - Budget Limit

    /// Budget limit converted to `targetCurrency`, resolving percent-of-income
    /// budgets using the provided transactions.
    static func convertBudgetLimit(
        for budget: Budget,
        transactions: [Transaction],
        targetCurrency: String
    ) -> Decimal {
        let limit: Decimal
        if case .percentOfIncome = budget.amountType {
            let income = calculateIncome(for: budget, transactions: transactions)
            limit = budget.calculateEffectiveLimit(income: income)
        } else {
            limit = budget.effectiveLimit
        }

        return CurrencyManager.shared.convert(
            amount: limit,
            from: budget.currencyCode,
            to: targetCurrency
        )
    }
}
