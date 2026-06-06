import SwiftUI

/// Full-height category picker presented from the "More" button on Add Transaction.
///
/// Layout (native inset-grouped `List`, so every section is a real system card —
/// identical corner radius / material to the rest of the app):
/// - A **Suggested** section at the top (hidden during search).
/// - An **All Categories** section below, switchable between list and grid.
struct TransactionCategoryPickerSheet: View {
    /// All categories of the current transaction type (already type-filtered, name-sorted).
    let allCategories: [Category]
    /// Engine-ranked categories for the current context (score 0 = no signal).
    let rankedSuggestions: [ScoredCategory]
    let selectedCategoryID: UUID?
    let onSelect: (Category) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""
    /// Persisted layout preference for the full list (suggestions are always a grid).
    @AppStorage("categoryPicker.useGridLayout") private var useGridLayout = true

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    private let maxSuggestions = 8
    /// Inner padding for a grid that sits as a single row inside a section card.
    private let gridRowInsets = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)

    /// Top suggestions that actually have a usage signal.
    private var suggestionItems: [ScoredCategory] {
        Array(rankedSuggestions.filter { $0.score > 0 }.prefix(maxSuggestions))
    }

    private var displayCategories: [Category] {
        guard !searchText.isEmpty else { return allCategories }
        return allCategories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    /// Hidden during search so it doesn't compete with the iOS 26 bottom-bar search pill.
    private var showSuggestions: Bool {
        searchText.isEmpty && !suggestionItems.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if showSuggestions {
                    suggestionSection
                }
                allCategoriesSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("transaction.selectCategory".localized)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .toolbar,
                prompt: "transaction.searchCategories".localized
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.Common.cancel)
                }
                // iOS 26+: move the search field to the native bottom bar pill.
                if #available(iOS 26, *) {
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    // MARK: - Suggested Section

    private var suggestionSection: some View {
        Section {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(suggestionItems) { scored in
                    CategoryGridItem(
                        category: scored.category,
                        isSelected: selectedCategoryID == scored.category.id,
                        isHighlighted: scored.isHighlighted
                    ) {
                        onSelect(scored.category)
                    }
                }
            }
            .listRowInsets(gridRowInsets)
        } header: {
            sectionHeader("transaction.suggestedCategories".localized)
        }
    }

    // MARK: - All Categories Section

    private var allCategoriesSection: some View {
        Section {
            if displayCategories.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
            } else if useGridLayout {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(displayCategories) { category in
                        CategoryGridItem(
                            category: category,
                            isSelected: selectedCategoryID == category.id
                        ) {
                            onSelect(category)
                        }
                    }
                }
                .listRowInsets(gridRowInsets)
            } else {
                ForEach(displayCategories) { category in
                    CategoryColorRow(
                        category: category,
                        isSelected: selectedCategoryID == category.id
                    ) {
                        onSelect(category)
                    }
                    // Align the row separator with the label text (past the icon).
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 44 }
                }
            }
        } header: {
            HStack {
                sectionHeader("transaction.allCategories".localized)
                Spacer()
                layoutToggle
            }
        }
    }

    private var layoutToggle: some View {
        Picker("", selection: $useGridLayout) {
            Image(systemName: "list.bullet").tag(false)
            Image(systemName: "square.grid.2x2").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(width: 92)
        .accessibilityLabel("transaction.allCategories".localized)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.app(.headline))
            .foregroundStyle(.primary)
            .textCase(nil)
    }
}

// MARK: - Color-coded list row

private struct CategoryColorRow: View {
    let category: Category
    let isSelected: Bool
    let action: () -> Void

    private var color: Color { Color(hex: category.colorHex) ?? .gray }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.app(.subheadline))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(color)
                    .clipShape(Circle())

                Text(category.name)
                    .font(.app(.body))
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.name)\(isSelected ? ", selected" : "")")
    }
}
