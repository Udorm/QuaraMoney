import SwiftUI
import SwiftData

struct AddCategoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var selectedType: TransactionType = .expense
    @State private var selectedIcon: String = "list.bullet"
    @State private var selectedColorHex: String = "#FF3B30"
    
    private var categoryToEdit: Category?
    
    init(categoryToEdit: Category? = nil) {
        self.categoryToEdit = categoryToEdit
        
        if let category = categoryToEdit {
            _name = State(initialValue: category.name)
            _selectedType = State(initialValue: category.type)
            _selectedIcon = State(initialValue: category.icon)
            _selectedColorHex = State(initialValue: category.colorHex)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header Section
                        VStack(spacing: 24) {
                            // Preview
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(hex: selectedColorHex) ?? .blue,
                                                (Color(hex: selectedColorHex) ?? .blue).opacity(0.7)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 100, height: 100)
                                    .shadow(color: (Color(hex: selectedColorHex) ?? .blue).opacity(0.3), radius: 10, x: 0, y: 5)
                                    .overlay(
                                        Circle()
                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                    )
                                
                                Image(systemName: selectedIcon)
                                    .font(.system(size: 40, weight: .semibold))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.1), radius: 2)
                            }
                            .padding(.top, 20)
                            
                            VStack(spacing: 16) {
                                TextField("Category Name", text: $name)
                                    .font(.title3.bold())
                                    .multilineTextAlignment(.center)
                                    .submitLabel(.done)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(12)
                                    .padding(.horizontal, 32)
                                
                                Picker("Type", selection: $selectedType) {
                                    Text("Expense").tag(TransactionType.expense)
                                    Text("Income").tag(TransactionType.income)
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal, 32)
                                .padding(.bottom, 8)
                            }
                        }
                        
                        // Pickers
                        VStack(spacing: 24) {
                            ColorPickerContainer(selectedColorHex: $selectedColorHex)
                                .padding(.horizontal, 16)
                            
                            SymbolPickerContainer(selectedIcon: $selectedIcon, selectedColorHex: selectedColorHex)
                                .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle(categoryToEdit != nil ? "Edit Category" : "New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCategory()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                    .fontWeight(.bold)
                }
            }
        }
    }
    
    private func saveCategory() {
        if let category = categoryToEdit {
            category.name = name
            category.icon = selectedIcon
            category.colorHex = selectedColorHex
            category.type = selectedType
        } else {
            let category = Category(name: name, icon: selectedIcon, colorHex: selectedColorHex, type: selectedType)
            modelContext.insert(category)
        }
    }
}
