import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
class AddTransactionViewModel: BaseViewModel {
    // Expression-based input for calculator
    @Published var expression: String = ""
    @Published var evaluatedAmount: Decimal = 0
    
    @Published var type: TransactionType = .expense
    @Published var date: Date = Date()
    @Published var note: String = ""
    @Published var selectedCategory: Category?
    @Published var destinationWallet: Wallet?
    @Published var selectedWallet: Wallet?
    @Published var selectedEvent: Event?
    
    @Published var exchangeRate: Double = 1.0
    
    private var existingTransaction: Transaction?
    var isEditing: Bool { existingTransaction != nil }
    
    init(dataService: DataService, initialWallet: Wallet? = nil, initialEvent: Event? = nil, transaction: Transaction? = nil) {
        self.selectedWallet = initialWallet
        self.selectedEvent = initialEvent
        self.existingTransaction = transaction
        super.init(dataService: dataService)
        
        if let txn = transaction {
            self.evaluatedAmount = txn.amount
            self.expression = formatDecimalForExpression(txn.amount)
            self.type = txn.type
            self.date = txn.date
            self.note = txn.note ?? ""
            self.selectedWallet = txn.sourceWallet
            self.selectedEvent = txn.event
            
            if txn.type == .transfer {
                self.destinationWallet = txn.destinationWallet
                self.exchangeRate = NSDecimalNumber(decimal: txn.exchangeRate).doubleValue
            } else {
                self.selectedCategory = txn.category
            }
        }
    }
    
    private func formatDecimalForExpression(_ value: Decimal) -> String {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        if doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", doubleValue)
        } else {
            return String(format: "%.2f", doubleValue)
        }
    }
    
    var isValid: Bool {
        guard evaluatedAmount > 0 else { return false }
        guard selectedWallet != nil else { return false }
        
        if type == .transfer {
            guard let dest = destinationWallet else { return false }
            if dest.id == selectedWallet?.id { return false }
        } else {
            guard selectedCategory != nil else { return false }
        }
        return true
    }
    
    // Updates exchange rate when wallets change
    func updateExchangeRate() {
        guard type == .transfer,
              let source = selectedWallet,
              let dest = destinationWallet,
              source.currencyCode != dest.currencyCode else {
            exchangeRate = 1.0
            return
        }
        
        let manager = CurrencyManager.shared
        if let sourceRate = manager.rates[source.currencyCode],
           let destRate = manager.rates[dest.currencyCode] {
            self.exchangeRate = destRate / sourceRate
        } else {
            self.exchangeRate = 1.0
        }
    }
    
    func saveTransaction() {
        guard evaluatedAmount > 0, let wallet = selectedWallet else { return }
        
        let transaction: Transaction
        if let existing = existingTransaction {
            transaction = existing
            transaction.amount = evaluatedAmount
            transaction.currencyCode = wallet.currencyCode
            transaction.date = date
            transaction.type = type
        } else {
            transaction = Transaction(
                amount: evaluatedAmount,
                currencyCode: wallet.currencyCode,
                date: date,
                type: type
            )
        }
        
        transaction.note = note.isEmpty ? nil : note
        transaction.sourceWallet = wallet
        
        if type == .transfer {
            transaction.destinationWallet = destinationWallet
            transaction.exchangeRate = Decimal(exchangeRate)
            transaction.category = nil
        } else {
            transaction.category = selectedCategory
            transaction.destinationWallet = nil
            transaction.exchangeRate = 1.0
        }
        
        transaction.event = selectedEvent
        
        if existingTransaction == nil {
            dataService.insert(transaction)
        } else {
            try? dataService.save()
        }
    }
}
