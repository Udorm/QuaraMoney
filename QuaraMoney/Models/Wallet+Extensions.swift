import Foundation
import SwiftData

extension Wallet {
    /// Invalidates the cached balance - call when transactions change
    func invalidateBalanceCache() {
        _balanceCacheStale = true
        _cachedBalance = nil
    }
    
    /// Calculates the current balance of the wallet.
    /// Uses cached value when available, otherwise computes and caches.
    var balance: Decimal {
        // Return cached value if valid
        if !_balanceCacheStale, let cached = _cachedBalance {
            return cached
        }
        
        // Compute balance
        let computed = computeBalance()
        
        // Cache the result
        _cachedBalance = computed
        _balanceCacheStale = false
        
        return computed
    }
    
    /// Core balance computation - iterates all transactions
    /// Converts all transaction amounts to the wallet's current currency for accurate balance
    private func computeBalance() -> Decimal {
        var total: Decimal = 0
        let walletCurrency = self.currencyCode
        
        // Helper to convert transaction amount to wallet currency
        // Note: Using inline conversion to avoid @MainActor isolation issues
        func convertToWalletCurrency(_ amount: Decimal, from txnCurrency: String) -> Decimal {
            if txnCurrency == walletCurrency {
                return amount
            }
            
            // Inline currency conversion using known rates
            // Default rates relative to USD
            let rates: [String: Decimal] = [
                "USD": 1,
                "KHR": 4000,
                "EUR": 0.92,
                "THB": 35,
                "SGD": 1.35,
                "JPY": 150
            ]
            
            guard let sourceRate = rates[txnCurrency], let targetRate = rates[walletCurrency] else {
                // If unknown currency pair, return original amount
                return amount
            }
            
            // Convert: source -> USD -> target
            let amountInUSD = amount / sourceRate
            return amountInUSD * targetRate
        }
        
        // 1. Process Outgoing Transactions (Income, Expense, Transfer OUT)
        if let outgoing = self.outgoingTransactions {
            for txn in outgoing {
                // For multi-currency transactions (income/expense), use stored exchange rate if available
                let convertedAmount: Decimal
                if txn.currencyCode != walletCurrency && txn.exchangeRate > 0 && txn.exchangeRate != 1.0 {
                    // Use the exchange rate stored at time of transaction
                    convertedAmount = txn.amount * txn.exchangeRate
                } else {
                    // Same currency or fallback to computed rate
                    convertedAmount = convertToWalletCurrency(txn.amount, from: txn.currencyCode)
                }
                
                switch txn.type {
                case .income:
                    total += convertedAmount
                case .expense:
                    total -= convertedAmount
                case .transfer:
                    total -= convertedAmount
                case .adjustment:
                    // Adjustments directly affect balance (can be positive or negative)
                    total += convertedAmount
                }
            }
        }
        
        // 2. Process Incoming Transactions (Transfer IN)
        if let incoming = self.incomingTransactions {
            for txn in incoming {
                if txn.type == .transfer {
                    // For transfers, use exchange rate if set (user-provided rate for cross-currency transfers)
                    // Otherwise convert from transaction currency to wallet currency
                    if txn.exchangeRate > 0 && txn.exchangeRate != 1.0 {
                        // User-specified exchange rate: amount * rate gives destination currency amount
                        total += (txn.amount * txn.exchangeRate)
                    } else {
                        // No explicit rate, convert using CurrencyManager
                        let convertedAmount = convertToWalletCurrency(txn.amount, from: txn.currencyCode)
                        total += convertedAmount
                    }
                }
            }
        }
        
        return total
    }
}
