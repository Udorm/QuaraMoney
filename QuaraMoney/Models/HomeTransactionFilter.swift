import Foundation

/// Home's browse filter, captured as plain values so it crosses into the
/// detached fetch in one piece. The sheet assigns the whole struct on confirm,
/// so changing several dimensions at once costs a single refresh.
///
/// Dimensions are AND-ed together; an empty set means "no constraint".
struct HomeTransactionFilter: Equatable, Sendable {
    var walletIds: Set<UUID> = []
    var types: Set<TransactionType> = []
    var categoryIds: Set<UUID> = []

    /// Every type the filter can offer, in the order the sheet lists them.
    static let selectableTypes: [TransactionType] = [.expense, .income, .transfer, .adjustment]

    /// Only income and expense transactions carry a category.
    static let categorizedTypes: Set<TransactionType> = [.income, .expense]

    var isActive: Bool {
        !walletIds.isEmpty || !types.isEmpty || !categoryIds.isEmpty
    }

    /// Category types worth offering for the chosen `types`: both when types
    /// are unconstrained, none when only transfers/adjustments are picked.
    var categoryTypes: Set<TransactionType> {
        types.isEmpty ? Self.categorizedTypes : types.intersection(Self.categorizedTypes)
    }

    /// Picking every type is the same as picking none; normalizing keeps the
    /// "All Types" row selected and the toolbar glyph out of its active state.
    mutating func setTypes(_ newTypes: Set<TransactionType>) {
        types = newTypes.count == Self.selectableTypes.count ? [] : newTypes
    }

    /// Drops ids that no longer resolve — a wallet archived or a category
    /// deleted after it was picked — so the list can't stay filtered by
    /// something the sheet can no longer show.
    func restricted(toWalletIds validWalletIds: Set<UUID>, categoryIds validCategoryIds: Set<UUID>) -> HomeTransactionFilter {
        var copy = self
        copy.walletIds.formIntersection(validWalletIds)
        copy.categoryIds.formIntersection(validCategoryIds)
        return copy
    }
}
