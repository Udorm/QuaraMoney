import Foundation
import SwiftData

extension Wallet {
    /// Calculates the current balance of the wallet based on all linked transactions.
    /// This serves as the Single Source of Truth for balance display.
    var balance: Decimal {
        var total: Decimal = 0
        
        // 1. Process Outgoing Transactions
        // (Income, Expense, Transfer OUT)
        // Income is technically "Source = This Wallet" in our current schema usage? 
        // Wait, current schema:
        // Income: sourceWallet = this. Amount is Added?
        // Let's re-verify how Income is saved.
        // In AddTransactionViewModel: 
        //   transaction.sourceWallet = wallet
        //   type = .income
        // So yes, Income is in 'outgoingTransactions' relation on Wallet.
        
        if let outgoing = self.outgoingTransactions {
            for txn in outgoing {
                switch txn.type {
                case .income:
                    total += txn.amount
                case .expense:
                    total -= txn.amount
                case .transfer:
                    total -= txn.amount
                }
            }
        }
        
        // 2. Process Incoming Transactions
        // (Transfer IN)
        if let incoming = self.incomingTransactions {
            for txn in incoming {
                if txn.type == .transfer {
                    // Apply Exchange Rate if present
                    // Rate is typically Source -> Destination
                    // If stored rate is 4000 (1 USD -> 4000 KHR), and amount is 10 (USD), 
                    // result is 10 * 4000 = 40,000 (KHR).
                    // If currencies match, rate should be 1.0.
                    let rate = txn.exchangeRate > 0 ? txn.exchangeRate : 1.0
                    total += (txn.amount * rate)
                }
            }
        }
        
        return total
    }
}
