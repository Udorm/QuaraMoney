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
    var selectedLocation: TransactionLocationSelection?

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
    
    init(dataService: DataService, initialWallet: Wallet? = nil, initialEvent: Event? = nil, transaction: Transaction? = nil, initialDate: Date? = nil, initialDebt: Debt? = nil, initialCategory: Category? = nil, initialAmount: Decimal? = nil, initialType: TransactionType? = nil) {
        self.selectedWallet = initialWallet
        self.selectedEvent = initialEvent
        self.existingTransaction = transaction
        super.init(dataService: dataService)

        if initialDate == nil && transaction == nil {
            // keep default Date()
        } else if transaction == nil, let d = initialDate {
            self.date = d
        }

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
            if let location = txn.location {
                self.selectedLocation = TransactionLocationSelection(location: location)
            }
            
            // Handle legacy exchangeRate (Decimal) -> Double
            self.exchangeRate = NSDecimalNumber(decimal: txn.exchangeRate).doubleValue
            
            self.debt = txn.debt
            
            if txn.type == .transfer {
                self.destinationWallet = txn.destinationWallet
                self.selectedSavingsGoal = txn.savingsGoal
            } else {
                self.selectedCategory = txn.category
            }
        } else if let debt = initialDebt {
            // New repayment for a debt/loan: preconfigure the entry to match the
            // debt (type, currency, managed category) and pre-fill the remaining
            // balance so the user only adjusts if paying a different amount.
            self.debt = debt
            self.type = debt.type == .owedToMe ? .income : .expense
            self.selectedCurrencyCode = debt.currencyCode
            self.selectedCategory = initialCategory
            // A caller-supplied amount (quick-pay preset) wins; otherwise default
            // to the full remaining balance. An explicit 0 means "let me type it".
            let prefill = initialAmount ?? debt.remainingAmount
            if prefill > 0 {
                self.evaluatedAmount = prefill
                self.expression = formatDecimalForExpression(prefill)
            }
            updateTransactionCurrencyExchangeRate()
        } else if let wallet = initialWallet {
            self.selectedCurrencyCode = wallet.currencyCode
        }

        // Caller-requested starting type (wallet quick actions) — only for new
        // entries; never override an existing transaction or a debt repayment.
        if transaction == nil, initialDebt == nil, let initialType {
            self.type = initialType
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
            // Debt-linked transactions use a managed system category (hidden in
            // the editor), so a manual category selection isn't required.
            guard selectedCategory != nil || debt != nil else { return false }
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
    
    /// Persists the transaction. Returns `true` on success so the caller can
    /// decide whether to dismiss. On failure the error is surfaced via
    /// `ErrorService` and `false` is returned (keep the sheet open for retry).
    @discardableResult
    func saveTransaction() -> Bool {
        guard evaluatedAmount > 0, let wallet = selectedWallet else { return false }
        
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
        transaction.tags = TransactionTagParser.tags(in: note)
        transaction.sourceWallet = wallet
        transaction.updatedAt = Date()
        
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

        // Record the authoritative rate so this transaction's contribution to
        // wallet balances is deterministic and never recomputed at live rates.
        transaction.storedRate = Decimal(exchangeRate)
        
        transaction.excludeFromReports = excludeFromReports
        if let selectedLocation {
            if let existingLocation = transaction.location {
                selectedLocation.apply(to: existingLocation)
            } else {
                transaction.location = selectedLocation.makePersistentLocation()
            }
        } else {
            if let existingLocation = transaction.location {
                existingLocation.markSoftDeleted()  // tombstone the replaced location
            }
            transaction.location = nil
        }

        // Event entries are now isolated in EventLedgerTransaction.
        // Keep wallet transactions detached from events to avoid double-accounting.
        transaction.event = nil

        // Link to a debt/loan (a new repayment recorded via the shared editor),
        // then re-derive the debt's cached fields so its total and completion
        // state stay consistent with the live ledger. For non-debt transactions
        // `debt` is nil, leaving the relationship untouched.
        transaction.debt = debt
        transaction.debt?.reconcile()

        if existingTransaction == nil {
            dataService.insert(transaction)
        }
        
        do {
            try dataService.save()
            HapticManager.shared.notification(type: .success)
            // Invalidate wallet balance caches only after a confirmed save.
            wallet.invalidateBalanceCache()
            destinationWallet?.invalidateBalanceCache()
            // Debt-linked saves broadcast an update so debt/list views refresh
            // promptly (mirrors the previous DebtService.recordRepayment path).
            if debt != nil {
                NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            }
            return true
        } catch {
            HapticManager.shared.notification(type: .error)
            ErrorService.shared.handlePersistenceError(error, context: "AddTransactionViewModel.saveTransaction")
            return false
        }
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
            #if DEBUG
            print("OCR Error: \(error)")
            #endif
            HapticManager.shared.notification(type: .error)
        }
    }
}
