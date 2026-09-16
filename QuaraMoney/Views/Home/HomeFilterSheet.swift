import SwiftUI

// MARK: - Toolbar Button

/// Home's toolbar filter control. It owns the sheet's presentation, so the
/// parent only hands in the applied filter and gets the confirmed one back.
struct HomeFilterButton: View {
    let filter: HomeTransactionFilter
    let wallets: [Wallet]
    let categories: [Category]
    let onApply: (HomeTransactionFilter) -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            // Same treatment as the shared `FilterSheetButton`: the glyph only
            // fills and tints while something is actually filtered.
            Image(systemName: "line.3.horizontal.decrease")
                .symbolVariant(filter.isActive ? .fill : .none)
                .appFont(.title3)
                .foregroundStyle(filter.isActive ? .blue : .primary)
        }
        .accessibilityLabel(L10n.Filter.title)
        .sheet(isPresented: $isPresented) {
            HomeFilterSheet(
                filter: filter,
                wallets: wallets,
                categories: categories,
                onApply: onApply
            )
        }
    }
}

// MARK: - Sheet

/// Deferred-apply filter sheet: edits stage locally and reach the list only on
/// confirm, so a multi-dimension change lands as one refresh.
///
/// Types and wallets are short, fixed lists and sit inline. Categories are long
/// and split by type, so they get their own pushed page behind a summary row.
struct HomeFilterSheet: View {
    let wallets: [Wallet]
    let categories: [Category]
    let onApply: (HomeTransactionFilter) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pending: HomeTransactionFilter

    init(
        filter: HomeTransactionFilter,
        wallets: [Wallet],
        categories: [Category],
        onApply: @escaping (HomeTransactionFilter) -> Void
    ) {
        self.wallets = wallets
        self.categories = categories
        self.onApply = onApply
        _pending = State(initialValue: filter)
    }

    var body: some View {
        NavigationStack {
            // Category sits right under Type: it's one row, and which
            // categories it offers depends on the types picked above it.
            List {
                typeSection
                categorySection
                walletSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.Filter.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // One leading group so the close glyph stays outermost; a
                // separate `.cancellationAction` item lands *after* Reset.
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.Common.cancel)
                    Button("analysis.pro.filter.reset".localized) {
                        pending = HomeTransactionFilter()
                    }
                    .disabled(!pending.isActive)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onApply(pending)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Type

    private var typeSection: some View {
        Section {
            SelectableRow(
                title: "filter.allTypes".localized,
                icon: "list.bullet",
                isSelected: pending.types.isEmpty,
                selectionStyle: .circleCheckmark
            ) {
                updateTypes([])
            }

            ForEach(HomeTransactionFilter.selectableTypes) { type in
                SelectableRow(
                    title: type.title,
                    icon: Self.icon(for: type),
                    iconColor: Self.color(for: type),
                    isSelected: pending.types.contains(type),
                    selectionStyle: .circleCheckmark
                ) {
                    var types = pending.types
                    if types.contains(type) {
                        types.remove(type)
                    } else {
                        types.insert(type)
                    }
                    updateTypes(types)
                }
            }
        } header: {
            sectionHeader("analysis.transactionType".localized, selectedCount: pending.types.count)
        }
    }

    /// Category selections that no longer match the chosen types are dropped
    /// here, while the user can still see why, rather than silently matching
    /// nothing after confirm.
    private func updateTypes(_ types: Set<TransactionType>) {
        pending.setTypes(types)
        let offeredIds = Set(offeredCategories.map(\.id))
        pending.categoryIds.formIntersection(offeredIds)
    }

    // MARK: Wallet

    private var walletSection: some View {
        Section {
            SelectableRow(
                title: "filter.allWallets".localized,
                icon: "square.stack.3d.up",
                isSelected: pending.walletIds.isEmpty,
                selectionStyle: .circleCheckmark
            ) {
                pending.walletIds = []
            }

            ForEach(wallets) { wallet in
                SelectableRow(
                    title: wallet.name,
                    icon: wallet.icon.isEmpty ? "creditcard" : wallet.icon,
                    iconColor: Color(hex: wallet.colorHex) ?? .blue,
                    isSelected: pending.walletIds.contains(wallet.id),
                    selectionStyle: .circleCheckmark
                ) {
                    if pending.walletIds.contains(wallet.id) {
                        pending.walletIds.remove(wallet.id)
                    } else {
                        pending.walletIds.insert(wallet.id)
                    }
                }
            }
        } header: {
            sectionHeader("filter.wallet".localized, selectedCount: pending.walletIds.count)
        }
    }

    // MARK: Category

    /// Categories belonging to the staged types, in display order.
    private var offeredCategories: [Category] {
        let types = pending.categoryTypes
        return categories
            .filter { types.contains($0.type) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var categorySection: some View {
        let offered = offeredCategories
        let selected = offered.filter { pending.categoryIds.contains($0.id) }
        let isUnavailable = pending.categoryTypes.isEmpty

        return Section {
            NavigationLink {
                HomeCategoryFilterList(selection: $pending.categoryIds, categories: offered)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: categoryRowIcon(selected))
                        .foregroundStyle(categoryRowIconStyle(selected))
                        .frame(width: 24)
                    Text(categorySummary(selected))
                        .appFont(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
            }
            .disabled(offered.isEmpty)
        } header: {
            sectionHeader("filter.category".localized, selectedCount: selected.count)
        } footer: {
            if isUnavailable {
                Text("filter.category.unavailable".localized)
                    .appFont(.caption)
            }
        }
    }

    private func categorySummary(_ selected: [Category]) -> String {
        switch selected.count {
        case 0: return "analysis.pro.filter.allCategories".localized
        case 1: return selected[0].displayName
        default: return "analysis.pro.filter.nCategories".localized(with: selected.count)
        }
    }

    private func categoryRowIcon(_ selected: [Category]) -> String {
        guard selected.count == 1 else { return "square.grid.2x2" }
        return selected[0].icon.isEmpty ? "tag" : selected[0].icon
    }

    private func categoryRowIconStyle(_ selected: [Category]) -> Color {
        switch selected.count {
        case 0: return .secondary
        case 1: return Color(hex: selected[0].colorHex) ?? .blue
        default: return .blue
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String, selectedCount: Int) -> some View {
        HStack {
            Text(title)
                .appFont(.caption)
            Spacer()
            if selectedCount > 0 {
                Text("analysis.pro.filter.nSelected".localized(with: selectedCount))
                    .appFont(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Mirrors the fallback glyphs `TransactionRowView` draws for each type.
    static func icon(for type: TransactionType) -> String {
        switch type {
        case .expense: return "arrow.up.circle.fill"
        case .income: return "arrow.down.circle.fill"
        case .transfer: return "arrow.left.arrow.right"
        case .adjustment: return "slider.horizontal.3"
        }
    }

    static func color(for type: TransactionType) -> Color {
        switch type {
        case .expense: return ThemeManager.shared.expenseColor
        case .income: return ThemeManager.shared.incomeColor
        case .transfer: return .blue
        case .adjustment: return .orange
        }
    }
}

// MARK: - Category Page

/// Multi-select category list, grouped by type because income and expense can
/// share a name (both have "Debt & Loans"). Writes straight into the sheet's
/// staged filter; nothing applies until the sheet itself is confirmed.
private struct HomeCategoryFilterList: View {
    @Binding var selection: Set<UUID>
    let categories: [Category]

    var body: some View {
        List {
            Section {
                SelectableRow(
                    title: "analysis.pro.filter.allCategories".localized,
                    icon: "square.grid.2x2",
                    isSelected: selection.isEmpty,
                    selectionStyle: .circleCheckmark
                ) {
                    selection = []
                }
            }

            ForEach(HomeTransactionFilter.selectableTypes) { type in
                let group = categories.filter { $0.type == type }
                if !group.isEmpty {
                    Section {
                        ForEach(group) { category in
                            SelectableRow(
                                title: category.displayName,
                                icon: category.icon.isEmpty ? "tag" : category.icon,
                                iconColor: Color(hex: category.colorHex) ?? .blue,
                                isSelected: selection.contains(category.id),
                                selectionStyle: .circleCheckmark
                            ) {
                                if selection.contains(category.id) {
                                    selection.remove(category.id)
                                } else {
                                    selection.insert(category.id)
                                }
                            }
                        }
                    } header: {
                        Text(type.title)
                            .appFont(.caption)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("filter.category".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}
