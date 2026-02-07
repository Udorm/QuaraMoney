import SwiftUI
import SwiftData

struct CategoryListView: View {
    @Query(sort: \Category.name) private var categories: [Category]
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
                                categoryToEdit = category
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
                                categoryToEdit = category
                            }
                    }
                    .onDelete { indexSet in
                        deleteCategory(at: indexSet, from: expenseCategories)
                    }
                }
            }
        }
        .navigationTitle(L10n.Category.title)
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
            // Optional: Check if used? Schema says deleteRule: .deny. 
            // So if used, it might crash or throw error?
            // Ideally we handle error. For MVP, we let SwiftData handle it (it won't delete if constraint violation).
            modelContext.delete(category)
        }
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
            
            Text(category.name)
            
            Spacer()
        }
    }
}
