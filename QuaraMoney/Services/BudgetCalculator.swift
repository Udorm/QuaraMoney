import Foundation

/// Shared budget calculation utility.
///
/// Centralises spending, income, and limit calculations that were
/// previously duplicated across `BudgetDetailView`, `BudgetListView`,
/// budget detail, list, overview, and active-budget summaries.
enum BudgetCalculator {

    // MARK: - Spending

    /// Total expense spending for a budget period, converted to `targetCurrency`.
    ///
    /// Filters on: `.expense` type, within `periodDateRange`, not excluded from
    /// reports, not linked to an event, and matching the budget's tracked categories.
    static func calculateSpending(
        for budget: Budget,
        transactions: [Transaction],
        targetCurrency: String,
        periodRange overrideRange: (start: Date, end: Date)? = nil
    ) -> Decimal {
        let periodRange = overrideRange ?? budget.periodDateRange
        let categoryIds = budget.trackedCategoryIds          // empty → total budget

        let relevant = transactions.filter { txn in
            guard txn.event == nil,
                  txn.deletedAt == nil,
                  txn.type == .expense,
                  !txn.excludeFromReports,
                  txn.date >= periodRange.start && txn.date < periodRange.end else {
                return false
            }

            if budget.targetKind == .total { return true }
            guard !categoryIds.isEmpty else { return false }
            guard let txnCatId = txn.category?.id else { return false }
            return categoryIds.contains(txnCatId)
        }

        return TransactionProcessor.calculateTotal(
            relevant,
            rates: CurrencyManager.shared.rates,
            targetCurrency: targetCurrency,
            typeFilter: .expense
        )
    }

    /// Spending for many budgets in a **single pass** over `transactions`.
    ///
    /// Equivalent to calling `calculateSpending` per budget, but iterates the
    /// transaction list once instead of `O(budgets × transactions)` re-filtering
    /// on every view render. Returns spent-per-budget keyed by `budget.id`,
    /// converted to `targetCurrency`.
    static func spendingByBudget(
        for budgets: [Budget],
        transactions: [Transaction],
        targetCurrency: String
    ) -> [UUID: Decimal] {
        let rates = CurrencyManager.shared.rates

        // Precompute each budget's period window and tracked-category set once.
        struct BudgetContext {
            let range: (start: Date, end: Date)
            let categoryIds: Set<UUID>
            let isTotal: Bool
        }
        var contexts: [(id: UUID, ctx: BudgetContext)] = []
        var totals: [UUID: Decimal] = [:]
        for budget in budgets {
            contexts.append((budget.id, BudgetContext(range: budget.periodDateRange,
                                                      categoryIds: Set(budget.trackedCategoryIds),
                                                      isTotal: budget.targetKind == .total)))
            totals[budget.id] = 0
        }

        for txn in transactions {
            guard txn.deletedAt == nil, txn.event == nil, txn.type == .expense, !txn.excludeFromReports else { continue }
            let txnCategoryId = txn.category?.id

            for entry in contexts {
                let ctx = entry.ctx
                guard txn.date >= ctx.range.start && txn.date < ctx.range.end else { continue }
                if !ctx.isTotal {
                    guard !ctx.categoryIds.isEmpty else { continue }
                    guard let txnCategoryId, ctx.categoryIds.contains(txnCategoryId) else { continue }
                }
                let amount = CurrencyManager.convert(amount: txn.amount,
                                                     from: txn.currencyCode,
                                                     to: targetCurrency,
                                                     rates: rates)
                totals[entry.id, default: 0] += amount
            }
        }

        return totals
    }

    /// Single-pass spending where every budget is accumulated in its own currency.
    static func spendingByBudgetCurrency(
        for budgets: [Budget],
        transactions: [Transaction],
        rates: [String: Double]? = nil
    ) -> [UUID: Decimal] {
        let conversionRates = rates ?? CurrencyManager.shared.rates
        struct Context {
            let id: UUID
            let range: (start: Date, end: Date)
            let categoryIDs: Set<UUID>
            let isTotal: Bool
            let currencyCode: String
        }
        let contexts = budgets.map {
            Context(id: $0.id, range: $0.periodDateRange,
                    categoryIDs: Set($0.trackedCategoryIds),
                    isTotal: $0.targetKind == .total, currencyCode: $0.currencyCode)
        }
        var totals = Dictionary(uniqueKeysWithValues: budgets.map { ($0.id, Decimal.zero) })
        for transaction in transactions {
            guard transaction.deletedAt == nil, transaction.event == nil,
                  transaction.type == .expense, !transaction.excludeFromReports else { continue }
            for context in contexts {
                guard transaction.date >= context.range.start, transaction.date < context.range.end else { continue }
                if !context.isTotal {
                    guard !context.categoryIDs.isEmpty, let categoryID = transaction.category?.id,
                          context.categoryIDs.contains(categoryID) else { continue }
                }
                totals[context.id, default: 0] += CurrencyManager.convert(
                    amount: transaction.amount, from: transaction.currencyCode,
                    to: context.currencyCode, rates: conversionRates
                )
            }
        }
        return totals
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

        return TransactionProcessor.calculateTotal(
            relevant,
            rates: CurrencyManager.shared.rates,
            targetCurrency: currency,
            typeFilter: .income
        )
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

    /// Converted limits for many budgets with one income scan. Fixed budgets
    /// are resolved immediately; percent-of-income budgets share the same pass
    /// over transactions instead of each filtering the full array in row body.
    static func limitsByBudget(
        for budgets: [Budget],
        transactions: [Transaction],
        targetCurrency: String
    ) -> [UUID: Decimal] {
        let rates = CurrencyManager.shared.rates
        let percentBudgets = budgets.filter {
            if case .percentOfIncome = $0.amountType { return true }
            return false
        }
        var incomeByBudgetID = Dictionary(
            uniqueKeysWithValues: percentBudgets.map { ($0.id, Decimal.zero) }
        )

        for transaction in transactions where transaction.event == nil &&
            transaction.type == .income && !transaction.excludeFromReports {
            for budget in percentBudgets {
                let range = budget.periodDateRange
                guard transaction.date >= range.start && transaction.date < range.end else { continue }
                incomeByBudgetID[budget.id, default: 0] += CurrencyManager.convert(
                    amount: transaction.amount,
                    from: transaction.currencyCode,
                    to: budget.currencyCode,
                    rates: rates
                )
            }
        }

        return Dictionary(uniqueKeysWithValues: budgets.map { budget in
            let rawLimit: Decimal
            if case .percentOfIncome = budget.amountType {
                rawLimit = budget.calculateEffectiveLimit(income: incomeByBudgetID[budget.id] ?? 0)
            } else {
                rawLimit = budget.effectiveLimit
            }
            let converted = CurrencyManager.convert(
                amount: rawLimit,
                from: budget.currencyCode,
                to: targetCurrency,
                rates: rates
            )
            return (budget.id, converted)
        })
    }
}
