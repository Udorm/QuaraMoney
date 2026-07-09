import SwiftUI
import SwiftData

struct CategoryListView: View {
    @Query(filter: #Predicate<Category> { $0.deletedAt == nil }, sort: \Category.name) private var categories: [Category]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddCategory = false
    @State private var categoryToEdit: Category?
    
    var incomeCategories: [Category] {
        categories.filter { $0.type == .income }
    }
    
    var expenseCategories: [Category] {
        categories.filter { $0.type == .expense }
    }
    
    var body: some View {
        List {
            if !incomeCategories.isEmpty {
                Section(L10n.Transaction.TransactionType.income) {
                    ForEach(incomeCategories) { category in
                        CategoryRow(category: category)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !category.isSystem {
                                    categoryToEdit = category
                                }
                            }
                    }
                    .onDelete { indexSet in
                        deleteCategory(at: indexSet, from: incomeCategories)
                    }
                }
            }
            
            if !expenseCategories.isEmpty {
                Section(L10n.Transaction.TransactionType.expense) {
                    ForEach(expenseCategories) { category in
                        CategoryRow(category: category)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !category.isSystem {
                                    categoryToEdit = category
                                }
                            }
                    }
                    .onDelete { indexSet in
                        deleteCategory(at: indexSet, from: expenseCategories)
                    }
                }
            }
        }
        .navigationTitle(L10n.Category.title)
        .syncPullToRefresh(modelContext)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddCategory = true }) {
                    Label(L10n.Category.add, systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategoryView()
        }
        .sheet(item: $categoryToEdit) { category in
            AddCategoryView(categoryToEdit: category)
        }
    }
    
    private func deleteCategory(at offsets: IndexSet, from list: [Category]) {
        for index in offsets {
            let category = list[index]

            if category.isSystem {
                continue // System categories cannot be deleted
            }

            // Soft-delete; transactions are kept and become uncategorized.
            SoftDeleteService.deleteCategory(category)
        }
        try? modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
}

struct CategoryRow: View {
    let category: Category
    
    var body: some View {
        HStack {
            Image(systemName: category.icon)
                .frame(width: 32, height: 32)
                .background(Color(hex: category.colorHex) ?? .gray)
                .foregroundColor(.white)
                .clipShape(Circle())
            
            Text(category.displayName)

            Spacer()
            
            if category.isSystem {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .deleteDisabled(category.isSystem)
    }
}
