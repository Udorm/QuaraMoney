import SwiftUI
import SwiftData

struct AddBudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Category.name) private var categories: [Category]
    @State private var selectedCategory: Category?
    @State private var amountString: String = ""
    @State private var month: Int = Calendar.current.component(.month, from: Date())
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    
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
            .navigationTitle("New Budget")
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
        guard let category = selectedCategory, let amount = Decimal(string: amountString) else { return }
        
        // MVP: Just creating. Real app should check for duplicate budget for same month/cat.
        let budget = Budget(amountLimit: amount, category: category, month: month, year: year)
        modelContext.insert(budget)
    }
}
