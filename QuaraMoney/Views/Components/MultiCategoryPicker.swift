
import SwiftUI
import SwiftData

struct MultiCategoryPicker: View {
    @Environment(\.dismiss) private var dismiss
    
    @Query(filter: #Predicate<Category> { $0.deletedAt == nil }, sort: \Category.name) private var allCategories: [Category]
    @Binding var selectedCategories: Set<UUID>
    
    // Search
    @State private var searchText = ""
    
    var filteredCategories: [Category] {
        let expenseCategories = allCategories.filter { $0.type == .expense }
        
        if searchText.isEmpty {
            return expenseCategories
        }
        
        return expenseCategories.filter { category in
            category.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if filteredCategories.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(filteredCategories) { category in
                        SelectableRow(
                            title: category.name,
                            icon: category.icon,
                            iconColor: Color(hex: category.colorHex) ?? .gray,
                            isSelected: selectedCategories.contains(category.id),
                            selectionStyle: .circleCheckmark
                        ) {
                            toggleCategory(category)
                        }
                    }
                }
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: L10n.Common.search)
            .navigationTitle(L10n.Budget.selectCategories)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if selectedCategories.isEmpty {
                            selectAll()
                        } else {
                            deselectAll()
                        }
                    } label: {
                        Text(selectedCategories.isEmpty ? L10n.Common.selectAll : L10n.Common.deselectAll)
                            .font(.app(.subheadline))
                    }
                }
            }
        }
    }
    
    private func toggleCategory(_ category: Category) {
        if selectedCategories.contains(category.id) {
            selectedCategories.remove(category.id)
        } else {
            selectedCategories.insert(category.id)
        }
    }
    
    private func selectAll() {
        let expenseIds = allCategories.filter { $0.type == .expense }.map { $0.id }
        selectedCategories = Set(expenseIds)
    }
    
    private func deselectAll() {
        selectedCategories.removeAll()
    }
}

#Preview {
    @Previewable @State var selected: Set<UUID> = []
    
    MultiCategoryPicker(selectedCategories: $selected)
        .modelContainer(for: [Category.self], inMemory: true)
}
