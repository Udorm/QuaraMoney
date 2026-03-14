import Foundation
import SwiftUI
import SwiftData

@Observable
@MainActor
class AddTransactionViewModel: BaseViewModel {
    // Expression-based input for calculator
    var expression: String = ""
    var evaluatedAmount: Decimal = 0

    var type: TransactionType = .expense
    var date: Date = Date()
    var note: String = ""
    var selectedCategory: Category?
    var destinationWallet: Wallet?
    var selectedWallet: Wallet?
    var selectedEvent: Event?
    var excludeFromReports: Bool = false
    var debt: Debt?
    var selectedSavingsGoal: SavingsGoal?

    var exchangeRate: Double = 1.0

    // Multi-currency support: transaction currency (may differ from wallet currency)
    var selectedCurrencyCode: String = "USD" {
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
            self.excludeFromReports = txn.excludeFromReports
            self.selectedCurrencyCode = txn.currencyCode
            
            // Handle legacy exchangeRate (Decimal) -> Double
            self.exchangeRate = NSDecimalNumber(decimal: txn.exchangeRate).doubleValue
            
            self.debt = txn.debt
            
            if txn.type == .transfer {
                self.destinationWallet = txn.destinationWallet
                self.selectedSavingsGoal = txn.savingsGoal
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
            transaction.savingsGoal = selectedSavingsGoal
        } else {
            transaction.category = selectedCategory
            transaction.destinationWallet = nil
            transaction.savingsGoal = nil
            // Store exchange rate for multi-currency income/expense
            transaction.exchangeRate = Decimal(exchangeRate)
        }
        
        transaction.excludeFromReports = excludeFromReports
        // Event entries are now isolated in EventLedgerTransaction.
        // Keep wallet transactions detached from events to avoid double-accounting.
        transaction.event = nil
        
        if existingTransaction == nil {
            dataService.insert(transaction)
        }
        
        do {
            try dataService.save()
            HapticManager.shared.notification(type: .success)
        } catch {
            print("Error saving transaction: \(error)")
            HapticManager.shared.notification(type: .error)
        }
        
        // Invalidate wallet balance caches
        wallet.invalidateBalanceCache()
        destinationWallet?.invalidateBalanceCache()
    }
    // MARK: - OCR / Receipt Scanning
    func scanReceipt(image: UIImage, availableWallets: [Wallet] = []) async {
        do {
            let walletNames = availableWallets.map { $0.name }
            let parsedData = try await OCRService.shared.scanReceipt(from: image, availableWallets: walletNames)
            
            if let amount = parsedData.amount {
                self.evaluatedAmount = amount
                self.expression = formatDecimalForExpression(amount)
            }
            
            if let date = parsedData.date {
                self.date = date
            }
            
            if let merchant = parsedData.merchantName {
                // Determine if we should append or replace
                if self.note.isEmpty {
                    self.note = merchant
                } else {
                    self.note = "\(merchant) - \(self.note)"
                }
            }
            
            // Handle Currency
            if let currencyCode = parsedData.currencyCode, !currencyCode.isEmpty {
                self.selectedCurrencyCode = currencyCode.uppercased()
            }
            
            // Handle Wallet Suggestion
            if let suggestedName = parsedData.suggestedWalletName {
                if let match = availableWallets.first(where: { $0.name.localizedCaseInsensitiveContains(suggestedName) }) {
                    self.selectedWallet = match
                    
                    // If no currency was detected, sync to the suggested wallet's currency
                    if parsedData.currencyCode == nil {
                        self.syncCurrencyToWallet()
                    }
                }
            }
            
            // Ensure exchange rate is updated if we have a wallet and a currency (potentially different)
            self.updateTransactionCurrencyExchangeRate()
            
            HapticManager.shared.notification(type: .success)
        } catch {
            print("OCR Error: \(error)")
            HapticManager.shared.notification(type: .error)
        }
    }
}
