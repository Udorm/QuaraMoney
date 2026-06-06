import Foundation

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

    /// Formatted date range string like "Mar 1 – Mar 31, 2026"
    var formattedDateRange: String {
        if startDate == .distantPast && endDate == .distantFuture {
            return L10n.Filter.allTime
        }
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: startDate) == calendar.component(.year, from: endDate)
        let sameMonth = sameYear && calendar.component(.month, from: startDate) == calendar.component(.month, from: endDate)

        let startFormatter = DateFormatter()
        let endFormatter = DateFormatter()

        if sameMonth {
            startFormatter.dateFormat = "MMM d"
            // endDate is exclusive (< endDate), show day before
            let displayEnd = calendar.date(byAdding: .day, value: -1, to: endDate) ?? endDate
            endFormatter.dateFormat = "d, yyyy"
            return "\(startFormatter.string(from: startDate)) – \(endFormatter.string(from: displayEnd))"
        } else if sameYear {
            startFormatter.dateFormat = "MMM d"
            let displayEnd = calendar.date(byAdding: .day, value: -1, to: endDate) ?? endDate
            endFormatter.dateFormat = "MMM d, yyyy"
            return "\(startFormatter.string(from: startDate)) – \(endFormatter.string(from: displayEnd))"
        } else {
            startFormatter.dateFormat = "MMM d, yyyy"
            let displayEnd = calendar.date(byAdding: .day, value: -1, to: endDate) ?? endDate
            endFormatter.dateFormat = "MMM d, yyyy"
            return "\(startFormatter.string(from: startDate)) – \(endFormatter.string(from: displayEnd))"
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
        defaultSortOption: TransactionSortOption = .newestFirst
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
    }
}
