
import SwiftUI
import SwiftData

struct MultiCategoryPicker: View {
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Category.name) private var allCategories: [Category]
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
                        Button {
                            toggleCategory(category)
                        } label: {
                            HStack {
                                Image(systemName: category.icon)
                                    .foregroundStyle(Color(hex: category.colorHex) ?? .gray)
                                    .frame(width: 30)
                                
                                Text(category.name)
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                if selectedCategories.contains(category.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $searchText, prompt: L10n.Common.search)
            .navigationTitle(L10n.Budget.selectCategories) // Make sure to add/use this key or literal "Select Categories"
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.done) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(selectedCategories.isEmpty ? L10n.Common.selectAll : L10n.Common.deselectAll) {
                        if selectedCategories.isEmpty {
                            selectAll()
                        } else {
                            deselectAll()
                        }
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
