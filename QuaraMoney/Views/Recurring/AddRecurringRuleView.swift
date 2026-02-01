import SwiftUI
import SwiftData

struct AddRecurringRuleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Wallet.name) private var wallets: [Wallet]
    @Query(sort: \Category.name) private var categories: [Category]
    
    @State private var name: String = ""
    @State private var amountString: String = ""
    @State private var frequency: Frequency = .monthly
    @State private var startDate: Date = Date()
    @State private var selectedWallet: Wallet?
    @State private var selectedCategory: Category?
    
    // Default currency usually comes from wallet, but for logic we might need one.
    // For simplicity, we assume the selected wallet's currency.
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name (e.g., Netflix)", text: $name)
                    
                    HStack {
                        Text(selectedWallet?.currencyCode ?? "USD")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amountString)
                            .keyboardType(.decimalPad)
                    }
                    
                    Picker("Frequency", selection: $frequency) {
                        Text("Daily").tag(Frequency.daily)
                        Text("Weekly").tag(Frequency.weekly)
                        Text("Monthly").tag(Frequency.monthly)
                        Text("Yearly").tag(Frequency.yearly)
                    }
                    
                    DatePicker("Start Date", selection: $startDate, displayedComponents: [.date])
                }
                
                Section("Assignments") {
                    if wallets.isEmpty {
                        Text("Create a Wallet first to add subscriptions.")
                            .foregroundStyle(.red)
                    } else {
                        Picker("Wallet", selection: $selectedWallet) {
                            Text("Select Wallet").tag(nil as Wallet?)
                            ForEach(wallets) { wallet in
                                Text(wallet.name).tag(wallet as Wallet?)
                            }
                        }
                    }
                    
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
            .navigationTitle("New Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveRule()
                        dismiss()
                    }
                    .disabled(name.isEmpty || amountString.isEmpty || selectedWallet == nil)
                }
            }
            .onAppear {
                if let firstWallet = wallets.first, selectedWallet == nil {
                    selectedWallet = firstWallet
                }
            }
        }
    }
    
    private func saveRule() {
        guard let amount = Decimal(string: amountString), let wallet = selectedWallet else { return }
        
        let rule = RecurringRule(
            name: name,
            amount: amount,
            currencyCode: wallet.currencyCode,
            frequency: frequency,
            startDate: startDate
        )
        rule.wallet = wallet
        rule.category = selectedCategory
        // Note: nextDueDate is set to startDate in init, which is correct for first run.
        
        modelContext.insert(rule)
    }
}
