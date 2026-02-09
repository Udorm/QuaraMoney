import SwiftUI
import SwiftData

struct AddRecurringRuleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(filter: #Predicate<Wallet> { !$0.isArchived }, sort: \Wallet.name) private var wallets: [Wallet]
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
                Section(L10n.Budget.details) {
                    TextField(L10n.Recurring.name, text: $name)
                    
                    HStack {
                        Text(selectedWallet?.currencyCode ?? "USD")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amountString)
                            .keyboardType(.decimalPad)
                    }
                    

                    
                    Picker(L10n.Recurring.frequency, selection: $frequency) {
                        ForEach(Frequency.allCases) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }
                    
                    DatePicker(L10n.Budget.startDate, selection: $startDate, displayedComponents: [.date])
                }
                
                Section(L10n.Recurring.assignments) {
                    if wallets.isEmpty {
                        Text(L10n.Recurring.createWalletFirst)
                            .foregroundStyle(.red)
                    } else {
                        Picker(L10n.Wallet.selectWallet, selection: $selectedWallet) {
                            Text(L10n.Wallet.selectWallet).tag(nil as Wallet?)
                            ForEach(wallets) { wallet in
                                Text(wallet.name).tag(wallet as Wallet?)
                            }
                        }
                    }
                    
                    Picker(L10n.Category.select, selection: $selectedCategory) {
                        Text(L10n.Category.select).tag(nil as Category?)
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
            .navigationTitle(L10n.Recurring.new)
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
                        saveRule()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
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
