import SwiftUI

/// Full-height category picker presented from the "More" button on Add Transaction.
///
/// Layout:
/// - A scrollable **All Categories** section at the top.
/// - A sticky **Suggested** card pinned to the bottom (thumb-zone), hidden during search.
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
    @AppStorage("categoryPicker.useGridLayout") private var useGridLayout = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    private let maxSuggestions = 8

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
            ScrollView {
                allCategoriesSection
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showSuggestions {
                    suggestionCard
                }
            }
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
                // Suggestion card hides during search, so the two never coexist.
                if #available(iOS 26, *) {
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    // MARK: - Sticky Suggestion Card

    private let glowGradient = LinearGradient(
        colors: [.blue.opacity(0.75), .cyan, .indigo.opacity(0.85), .purple.opacity(0.65)],
        startPoint: .leading,
        endPoint: .trailing
    )

    private var suggestionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("transaction.suggestedCategories".localized)

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
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        // Glow bloom border
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(glowGradient, lineWidth: 5)
                .blur(radius: 4)
                .opacity(0.6)
        }
        // Crisp gradient border on top of the bloom
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(glowGradient, lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - All Categories Section

    private var allCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("transaction.allCategories".localized)
                Spacer()
                layoutToggle
            }

            if displayCategories.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
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
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayCategories.enumerated()), id: \.element.id) { index, category in
                        CategoryColorRow(
                            category: category,
                            isSelected: selectedCategoryID == category.id
                        ) {
                            onSelect(category)
                        }
                        if index < displayCategories.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.name)\(isSelected ? ", selected" : "")")
    }
}
