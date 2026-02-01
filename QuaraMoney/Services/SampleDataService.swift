import Foundation
import SwiftData

@MainActor
final class SampleDataService {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func populate() async throws {
        // Clear existing data
        try await clearAllData()
        
        // create Wallets
        let cashWallet = Wallet(name: "Cash", currencyCode: "USD", icon: "banknote", colorHex: "#4CAF50")
        let bankWallet = Wallet(name: "Bank Account", currencyCode: "USD", icon: "building.columns", colorHex: "#2196F3")
        let creditCardWallet = Wallet(name: "Credit Card", currencyCode: "USD", icon: "creditcard", colorHex: "#E91E63")
        
        modelContext.insert(cashWallet)
        modelContext.insert(bankWallet)
        modelContext.insert(creditCardWallet)
        
        try modelContext.save() // Save wallets first
        
        // Create Categories
        // Income
        let salaryCategory = Category(name: "Salary", icon: "dollarsign.circle", colorHex: "#4CAF50", type: .income)
        let freelanceCategory = Category(name: "Freelance", icon: "laptopcomputer", colorHex: "#8BC34A", type: .income)
        
        // Expense
        let foodCategory = Category(name: "Food & Dining", icon: "fork.knife", colorHex: "#FF5722", type: .expense)
        let transportCategory = Category(name: "Transport", icon: "car", colorHex: "#03A9F4", type: .expense)
        let shoppingCategory = Category(name: "Shopping", icon: "cart", colorHex: "#9C27B0", type: .expense)
        let entertainmentCategory = Category(name: "Entertainment", icon: "tv", colorHex: "#673AB7", type: .expense)
        let billsCategory = Category(name: "Bills & Utilities", icon: "doc.text", colorHex: "#607D8B", type: .expense)
        
        modelContext.insert(salaryCategory)
        modelContext.insert(freelanceCategory)
        modelContext.insert(foodCategory)
        modelContext.insert(transportCategory)
        modelContext.insert(shoppingCategory)
        modelContext.insert(entertainmentCategory)
        modelContext.insert(billsCategory)
        
        try modelContext.save() // Save categories
        
        // Generate Transactions
        let calendar = Calendar.current
        let today = Date()
        
        // Last 3 months
        for i in 0..<90 {
            guard let date = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            
            // Random chance to create transaction
            let numberOfTransactions = Int.random(in: 0...3)
            
            for _ in 0..<numberOfTransactions {
                // expense
                if Bool.random() { 
                    let amount = Decimal(Int.random(in: 5...100))
                    let category = [foodCategory, transportCategory, shoppingCategory, entertainmentCategory].randomElement()!
                    let wallet = [cashWallet, creditCardWallet].randomElement()!
                    
                    let transaction = Transaction(amount: amount, currencyCode: "USD", date: date, type: .expense)
                    transaction.category = category
                    transaction.sourceWallet = wallet
                    transaction.note = "Sample \(category.name)"
                    modelContext.insert(transaction)
                }
            }
        }
        
        // Monthly Salary
        for i in 0..<3 {
            if let date = calendar.date(byAdding: .month, value: -i, to: today) {
                let transaction = Transaction(amount: 3000, currencyCode: "USD", date: date, type: .income)
                transaction.category = salaryCategory
                transaction.sourceWallet = bankWallet // Salary usually goes to bank
                transaction.note = "Monthly Salary"
                modelContext.insert(transaction)
            }
        }
        
        // Pay Credit Card Bill (Transfer)
        for i in 0..<3 {
             if let date = calendar.date(byAdding: .month, value: -i, to: today) {
                let transferAmount: Decimal = 500
                let transaction = Transaction(amount: transferAmount, currencyCode: "USD", date: date, type: .transfer)
                transaction.sourceWallet = bankWallet
                transaction.destinationWallet = creditCardWallet
                transaction.note = "Pay Credit Card"
                modelContext.insert(transaction)
            }
        }
        
        try modelContext.save()
    }
    
    private func clearAllData() async throws {
        // Fetch and delete all data manually to ensure context updates are propagated correctly to the UI
        let transactions = try modelContext.fetch(FetchDescriptor<Transaction>())
        for transaction in transactions { modelContext.delete(transaction) }
        
        let budgets = try modelContext.fetch(FetchDescriptor<Budget>())
        for budget in budgets { modelContext.delete(budget) }
        
        let rules = try modelContext.fetch(FetchDescriptor<RecurringRule>())
        for rule in rules { modelContext.delete(rule) }
        
        let categories = try modelContext.fetch(FetchDescriptor<Category>())
        for category in categories { modelContext.delete(category) }
        
        let wallets = try modelContext.fetch(FetchDescriptor<Wallet>())
        for wallet in wallets { modelContext.delete(wallet) }
        
        let events = try modelContext.fetch(FetchDescriptor<Event>())
        for event in events { modelContext.delete(event) }
        
        try modelContext.save()
    }
}
