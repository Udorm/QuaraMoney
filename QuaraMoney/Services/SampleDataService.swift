import Foundation
import SwiftData
import SwiftUI // For Notification



@MainActor
final class SampleDataService {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func populate() async throws {
        // Produce the large value-only payload before any SwiftData model is
        // created, so no model survives across this suspension point.
        let transactionData = await generateTransactionData()

        // Clear existing data
        try clearAllData()
        
        // Create Wallets
        let cashWallet = Wallet(name: "Cash", currencyCode: "USD", icon: "banknote", colorHex: "#4CAF50")
        let bankWallet = Wallet(name: "Bank Account", currencyCode: "USD", icon: "building.columns", colorHex: "#2196F3")
        let creditCardWallet = Wallet(name: "Credit Card", currencyCode: "USD", icon: "creditcard", colorHex: "#E91E63")
        
        modelContext.insert(cashWallet)
        modelContext.insert(bankWallet)
        modelContext.insert(creditCardWallet)
        
        // Create Categories
        let salaryCategory = Category(name: "Salary", icon: "dollarsign.circle", colorHex: "#4CAF50", type: .income)
        let freelanceCategory = Category(name: "Freelance", icon: "laptopcomputer", colorHex: "#8BC34A", type: .income)
        let foodCategory = Category(name: "Food & Dining", icon: "fork.knife", colorHex: "#FF5722", type: .expense)
        let transportCategory = Category(name: "Transport", icon: "car", colorHex: "#03A9F4", type: .expense)
        let shoppingCategory = Category(name: "Shopping", icon: "cart", colorHex: "#9C27B0", type: .expense)
        let entertainmentCategory = Category(name: "Entertainment", icon: "tv", colorHex: "#673AB7", type: .expense)
        let billsCategory = Category(name: "Bills & Utilities", icon: "doc.text", colorHex: "#607D8B", type: .expense)
        
        let allCategories = [salaryCategory, freelanceCategory, foodCategory, transportCategory, shoppingCategory, entertainmentCategory, billsCategory]
        for category in allCategories {
            modelContext.insert(category)
        }
        
        // Save wallets and categories first
        try modelContext.save()
        
        // Pre-compute arrays for faster random selection
        let expenseCategories = [foodCategory, transportCategory, shoppingCategory, entertainmentCategory, billsCategory]
        let expenseWallets = [cashWallet, creditCardWallet]
        let categoryNotes = expenseCategories.map { "Sample \($0.name)" }
        
        // Batch insert transactions
        let batchSize = 100
        var insertCount = 0
        
        for data in transactionData {
            let transaction = Transaction(
                amount: data.amount,
                currencyCode: "USD",
                date: data.date,
                type: data.type
            )
            
            switch data.type {
            case .expense:
                let categoryIndex = data.categoryIndex % expenseCategories.count
                transaction.category = expenseCategories[categoryIndex]
                transaction.sourceWallet = expenseWallets[data.walletIndex % expenseWallets.count]
                transaction.note = categoryNotes[categoryIndex]
            case .income:
                transaction.category = salaryCategory
                transaction.sourceWallet = bankWallet
                transaction.note = "Monthly Salary"
            case .transfer:
                transaction.sourceWallet = bankWallet
                transaction.destinationWallet = creditCardWallet
                transaction.note = "Pay Credit Card"
            case .adjustment:
                transaction.sourceWallet = bankWallet
                transaction.note = "Balance Adjustment"
            }
            
            modelContext.insert(transaction)
            insertCount += 1
            
            // Save in batches to avoid memory pressure
            if insertCount % batchSize == 0 {
                try modelContext.save()
            }
        }
        
        // Final save
        try modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
    
    // Generate transaction data off the main actor for better performance
    private nonisolated func generateTransactionData() async -> [TransactionData] {
        var data: [TransactionData] = []
        data.reserveCapacity(800) // Pre-allocate approximate size
        
        let calendar = Calendar.current
        let today = Date()
        
        // Generate daily expenses (2 years = 730 days)
        // Simplified: 1 transaction per day instead of random 0-3
        for i in 0..<730 {
            guard let date = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            
            // Create 1 expense per day (deterministic based on day for consistency)
            let amount = Decimal(10 + (i % 90)) // Varies from 10-99
            data.append(TransactionData(
                amount: amount,
                date: date,
                type: .expense,
                categoryIndex: i % 5,
                walletIndex: i % 2
            ))
        }
        
        // Monthly salary (24 months)
        for i in 0..<24 {
            if let date = calendar.date(byAdding: .month, value: -i, to: today) {
                data.append(TransactionData(
                    amount: 3000,
                    date: date,
                    type: .income,
                    categoryIndex: 0,
                    walletIndex: 0
                ))
            }
        }
        
        // Monthly credit card payments (24 months)
        for i in 0..<24 {
            if let date = calendar.date(byAdding: .month, value: -i, to: today) {
                data.append(TransactionData(
                    amount: 500,
                    date: date,
                    type: .transfer,
                    categoryIndex: 0,
                    walletIndex: 0
                ))
            }
        }
        
        return data
    }
    
    private func clearAllData() throws {
        // Fetch and delete - safer than bulk delete for SwiftData
        let transactions = try modelContext.fetch(FetchDescriptor<Transaction>())
        for transaction in transactions { modelContext.delete(transaction) }
        
        let eventParticipants = try modelContext.fetch(FetchDescriptor<EventLedgerParticipant>())
        for participant in eventParticipants { modelContext.delete(participant) }
        
        let eventLedgerTransactions = try modelContext.fetch(FetchDescriptor<EventLedgerTransaction>())
        for ledgerTransaction in eventLedgerTransactions { modelContext.delete(ledgerTransaction) }
        
        let eventMembers = try modelContext.fetch(FetchDescriptor<EventMember>())
        for member in eventMembers { modelContext.delete(member) }
        
        let settlementTransfers = try modelContext.fetch(FetchDescriptor<EventSettlementTransfer>())
        for transfer in settlementTransfers { modelContext.delete(transfer) }
        
        let settlementSnapshots = try modelContext.fetch(FetchDescriptor<EventSettlementSnapshot>())
        for snapshot in settlementSnapshots { modelContext.delete(snapshot) }
        
        let eventExportRecords = try modelContext.fetch(FetchDescriptor<EventWalletExportRecord>())
        for record in eventExportRecords { modelContext.delete(record) }
        
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
    
    func deleteAllTransactions() async throws {
        let transactions = try modelContext.fetch(FetchDescriptor<Transaction>())
        for transaction in transactions {
            modelContext.delete(transaction)
        }
        try modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
}

// Lightweight struct for generating data off main thread
private struct TransactionData {
    let amount: Decimal
    let date: Date
    let type: TransactionType
    let categoryIndex: Int
    let walletIndex: Int
}
