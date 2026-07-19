import Foundation

nonisolated enum TransactionReportExclusionPolicy: Sendable, Equatable {
    /// Existing callers keep excluded rows in the result set; aggregate helpers
    /// continue to omit them as they did before Plan v2.
    case include
    case exclude
}

nonisolated enum TransactionArchivedWalletPolicy: Sendable, Equatable {
    case exclude
    case include
}

nonisolated enum TransactionConversionPolicy: Sendable, Equatable {
    /// Historical behavior: known fallback rates are consulted, then an
    /// unavailable pair is treated as 1:1.
    case legacyFallback
    /// Plan opt-in: a missing/invalid rate yields no converted value.
    case rateChecked

    func convert(
        amount: Decimal,
        from source: String,
        to target: String,
        rates: [String: Double]
    ) -> Decimal? {
        switch self {
        case .legacyFallback:
            return CurrencyManager.convert(amount: amount, from: source, to: target, rates: rates)
        case .rateChecked:
            return CurrencyManager.convertOrNil(amount: amount, from: source, to: target, rates: rates)
        }
    }
}

nonisolated enum TransactionBudgetRelevancePolicy: Sendable, Equatable {
    /// Existing drill-downs keep their current result semantics.
    case disabled
    /// Budget drill-downs use the same event/report/type/scope predicate as the
    /// Plan projection, chart, and recent rows.
    case sharedPredicate
}

/// Lightweight category display info for filter chips.
struct FilterCategoryInfo: Sendable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let icon: String
    let colorHex: String
}

/// Captures all filter dimensions as plain values for the filtered transactions detail screen.
/// Reusable from analytics, budgets, and other screens.
struct TransactionFilterConfig: Sendable, Equatable {
    let title: String
    let startDate: Date
    let endDate: Date
    let walletId: UUID?
    let walletName: String?
    let categoryId: UUID?
    let categoryName: String?
    let categoryIcon: String?
    let categoryColorHex: String?
    let transactionType: TransactionTypeFilter?
    let dateRangeDescription: String
    /// Multiple category IDs for budget filtering (overrides categoryId when non-nil)
    let categoryIds: [UUID]?
    /// Category display info for showing individual chips (used by budgets with multiple categories)
    let categoryInfos: [FilterCategoryInfo]?
    let savingsGoalId: UUID?
    let savingsGoalName: String?
    let defaultSortOption: TransactionSortOption
    let reportExclusionPolicy: TransactionReportExclusionPolicy
    let archivedWalletPolicy: TransactionArchivedWalletPolicy
    /// Nil preserves the existing preferred-currency behavior.
    let summaryCurrencyCode: String?
    let conversionPolicy: TransactionConversionPolicy
    let budgetRelevancePolicy: TransactionBudgetRelevancePolicy

    /// Formatted date range string like "Mar 1 – Mar 31, 2026"
    var formattedDateRange: String {
        if startDate == .distantPast && endDate == .distantFuture {
            return L10n.Filter.allTime
        }
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: startDate) == calendar.component(.year, from: endDate)
        let sameMonth = sameYear && calendar.component(.month, from: startDate) == calendar.component(.month, from: endDate)

        func formatter(_ dateFormat: String) -> DateFormatter {
            AppDateFormatterCache.formatter(dateFormat: dateFormat, locale: .app)
        }
        // endDate is exclusive (< endDate), show day before
        let displayEnd = calendar.date(byAdding: .day, value: -1, to: endDate) ?? endDate

        if sameMonth {
            return "\(formatter("MMM d").string(from: startDate)) – \(formatter("d, yyyy").string(from: displayEnd))"
        } else if sameYear {
            return "\(formatter("MMM d").string(from: startDate)) – \(formatter("MMM d, yyyy").string(from: displayEnd))"
        } else {
            let f = formatter("MMM d, yyyy")
            return "\(f.string(from: startDate)) – \(f.string(from: displayEnd))"
        }
    }

    init(
        title: String,
        startDate: Date,
        endDate: Date,
        walletId: UUID? = nil,
        walletName: String? = nil,
        categoryId: UUID? = nil,
        categoryName: String? = nil,
        categoryIcon: String? = nil,
        categoryColorHex: String? = nil,
        transactionType: TransactionTypeFilter? = nil,
        dateRangeDescription: String,
        categoryIds: [UUID]? = nil,
        categoryInfos: [FilterCategoryInfo]? = nil,
        savingsGoalId: UUID? = nil,
        savingsGoalName: String? = nil,
        defaultSortOption: TransactionSortOption = .newestFirst,
        reportExclusionPolicy: TransactionReportExclusionPolicy = .include,
        archivedWalletPolicy: TransactionArchivedWalletPolicy = .exclude,
        summaryCurrencyCode: String? = nil,
        conversionPolicy: TransactionConversionPolicy = .legacyFallback,
        budgetRelevancePolicy: TransactionBudgetRelevancePolicy = .disabled
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.walletId = walletId
        self.walletName = walletName
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.categoryIcon = categoryIcon
        self.categoryColorHex = categoryColorHex
        self.transactionType = transactionType
        self.dateRangeDescription = dateRangeDescription
        self.categoryIds = categoryIds
        self.categoryInfos = categoryInfos
        self.savingsGoalId = savingsGoalId
        self.savingsGoalName = savingsGoalName
        self.defaultSortOption = defaultSortOption
        self.reportExclusionPolicy = reportExclusionPolicy
        self.archivedWalletPolicy = archivedWalletPolicy
        self.summaryCurrencyCode = summaryCurrencyCode
        self.conversionPolicy = conversionPolicy
        self.budgetRelevancePolicy = budgetRelevancePolicy
    }
}
