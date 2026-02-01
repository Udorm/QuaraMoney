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
            Form {
                Section("Details") {
                    TextField("Category Name", text: $name)
                    
                    Picker("Type", selection: $selectedType) {
                        Text("Expense").tag(TransactionType.expense)
                        Text("Income").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Appearance") {
                    // Visual Preview
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: selectedColorHex) ?? .blue)
                                    .frame(width: 80, height: 80)
                                    .shadow(radius: 5)
                                
                                Image(systemName: selectedIcon)
                                    .font(.system(size: 36))
                                    .foregroundColor(.white)
                            }
                            
                            Text("Preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical)
                    .listRowBackground(Color.clear)
                    
                    NavigationLink {
                        ColorPickerView(selectedColorHex: $selectedColorHex)
                            .navigationTitle("Select Color")
                    } label: {
                        HStack {
                            Text("Color")
                            Spacer()
                            Circle()
                                .fill(Color(hex: selectedColorHex) ?? .blue)
                                .frame(width: 24, height: 24)
                        }
                    }
                    
                    NavigationLink {
                        IconPickerView(selectedIcon: $selectedIcon, selectedColorHex: $selectedColorHex)
                            .navigationTitle("Select Icon")
                    } label: {
                        HStack {
                            Text("Icon")
                            Spacer()
                            Image(systemName: selectedIcon)
                                .foregroundColor(Color(hex: selectedColorHex) ?? .blue)
                        }
                    }
                }
            }
            .navigationTitle(categoryToEdit != nil ? "Edit Category" : "New Category")
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

// Helper for Hex Color from previous implementation or we check Utils
// Assuming Color(hex:) extension exists as used in other views.
