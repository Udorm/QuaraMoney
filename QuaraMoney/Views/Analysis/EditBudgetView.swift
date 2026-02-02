import SwiftUI
import SwiftData

struct EditBudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var budget: Budget
    
    @Query(sort: \Category.name) private var categories: [Category]
    
    @State private var selectedCategory: Category?
    @State private var amountString: String = ""
    @State private var selectedCurrency: String = ""
    @State private var month: Int = 1
    @State private var year: Int = 2026
    
    init(budget: Budget) {
        self.budget = budget
        // Initialize state from budget values
        _selectedCategory = State(initialValue: budget.category)
        _amountString = State(initialValue: "\(budget.amountLimit)")
        _selectedCurrency = State(initialValue: budget.currencyCode)
        _month = State(initialValue: budget.month)
        _year = State(initialValue: budget.year)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Target") {
                    if categories.isEmpty {
                        Text("No Categories Available")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Category", selection: $selectedCategory) {
                            Text("Select Category").tag(nil as Category?)
                            ForEach(categories) { category in
                                HStack {
                                    Image(systemName: category.icon)
                                    Text(category.name)
                                }
                                .tag(category as Category?)
                            }
                        }
                    }
                }
                
                Section("Limit") {
                    TextField("Amount", text: $amountString)
                        .keyboardType(.decimalPad)
                    
                    Picker("Currency", selection: $selectedCurrency) {
                        ForEach(CurrencyManager.shared.availableCurrencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                }
                
                Section("Period") {
                    Picker("Month", selection: $month) {
                        ForEach(1...12, id: \.self) { m in
                            Text(Calendar.current.monthSymbols[m-1]).tag(m)
                        }
                    }
                    
                    Picker("Year", selection: $year) {
                        ForEach(2025...2030, id: \.self) { y in
                            Text(String(format: "%d", y)).tag(y)
                        }
                    }
                }
            }
            .navigationTitle("Edit Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveBudget()
                        dismiss()
                    }
                    .disabled(selectedCategory == nil || amountString.isEmpty)
                }
            }
        }
    }
    
    private func saveBudget() {
        guard let category = selectedCategory,
              let amount = Decimal(string: amountString) else { return }
        
        // Update the budget properties
        budget.category = category
        budget.amountLimit = amount
        budget.currencyCode = selectedCurrency
        budget.month = month
        budget.year = year
    }
}

#Preview {
    @Previewable @State var budget = Budget(amountLimit: 500, currencyCode: "USD", category: nil, month: 2, year: 2026)
    
    EditBudgetView(budget: budget)
        .modelContainer(for: [Budget.self, Category.self], inMemory: true)
}
