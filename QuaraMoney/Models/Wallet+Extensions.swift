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
    private func computeBalance() -> Decimal {
        var total: Decimal = 0
        
        // 1. Process Outgoing Transactions (Income, Expense, Transfer OUT)
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
        
        // 2. Process Incoming Transactions (Transfer IN)
        if let incoming = self.incomingTransactions {
            for txn in incoming {
                if txn.type == .transfer {
                    // Apply Exchange Rate if present
                    let rate = txn.exchangeRate > 0 ? txn.exchangeRate : 1.0
                    total += (txn.amount * rate)
                }
            }
        }
        
        return total
    }
}
