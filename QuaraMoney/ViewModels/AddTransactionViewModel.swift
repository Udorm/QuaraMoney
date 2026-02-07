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
    
    // Multi-currency support: transaction currency (may differ from wallet currency)
    @Published var selectedCurrencyCode: String = "USD" {
        didSet {
            if oldValue != selectedCurrencyCode {
                updateTransactionCurrencyExchangeRate()
            }
        }
    }
    
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
            self.selectedCurrencyCode = txn.currencyCode
            self.exchangeRate = NSDecimalNumber(decimal: txn.exchangeRate).doubleValue
            
            if txn.type == .transfer {
                self.destinationWallet = txn.destinationWallet
            } else {
                self.selectedCategory = txn.category
            }
        } else if let wallet = initialWallet {
            self.selectedCurrencyCode = wallet.currencyCode
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
    
    // Maximum allowed transaction amount to prevent Decimal overflow
    static let maxTransactionAmount: Decimal = 999_999_999_999
    
    var isValid: Bool {
        // Amount must be positive and within bounds
        guard evaluatedAmount > 0, evaluatedAmount <= Self.maxTransactionAmount else { return false }
        guard selectedWallet != nil else { return false }
        
        if type == .transfer {
            guard let dest = destinationWallet else { return false }
            if dest.id == selectedWallet?.id { return false }
        } else {
            guard selectedCategory != nil else { return false }
        }
        return true
    }
    
    // Updates exchange rate when wallets change (for transfers)
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
    
    // Updates exchange rate when transaction currency changes (for income/expense)
    func updateTransactionCurrencyExchangeRate() {
        guard let wallet = selectedWallet else {
            exchangeRate = 1.0
            return
        }
        
        // If same currency, no conversion needed
        if selectedCurrencyCode == wallet.currencyCode {
            exchangeRate = 1.0
            return
        }
        
        // Get rate from transaction currency to wallet currency
        let manager = CurrencyManager.shared
        if let txnRate = manager.rates[selectedCurrencyCode],
           let walletRate = manager.rates[wallet.currencyCode] {
            // Exchange rate: how many wallet currency units per 1 transaction currency unit
            self.exchangeRate = walletRate / txnRate
        } else {
            self.exchangeRate = 1.0
        }
    }
    
    // Sync currency to wallet when wallet changes (if not editing)
    func syncCurrencyToWallet() {
        if !isEditing, let wallet = selectedWallet {
            selectedCurrencyCode = wallet.currencyCode
            exchangeRate = 1.0
        }
    }
    
    func saveTransaction() {
        guard evaluatedAmount > 0, let wallet = selectedWallet else { return }
        
        let transaction: Transaction
        if let existing = existingTransaction {
            transaction = existing
            transaction.amount = evaluatedAmount
            transaction.currencyCode = selectedCurrencyCode
            transaction.date = date
            transaction.type = type
        } else {
            transaction = Transaction(
                amount: evaluatedAmount,
                currencyCode: selectedCurrencyCode,
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
            // Store exchange rate for multi-currency income/expense
            transaction.exchangeRate = Decimal(exchangeRate)
        }
        
        transaction.event = selectedEvent
        
        if existingTransaction == nil {
            dataService.insert(transaction)
        } else {
            try? dataService.save()
        }
        
        // Invalidate wallet balance caches
        wallet.invalidateBalanceCache()
        destinationWallet?.invalidateBalanceCache()
    }
}
