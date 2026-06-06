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
        // Uses CurrencyManager's fallback rates (constant — keeps legacy balances
        // stable rather than drifting with each network fetch).
        func convertToWalletCurrency(_ amount: Decimal, from txnCurrency: String) -> Decimal {
            if txnCurrency == walletCurrency {
                return amount
            }

            // Use CurrencyManager's fallback rates (safe to access from any isolation context)
            let rates = CurrencyManager.fallbackRates
            guard let sourceRate = rates[txnCurrency], let targetRate = rates[walletCurrency] else {
                return amount
            }

            let amountInUSD = amount / Decimal(sourceRate)
            return amountInUSD * Decimal(targetRate)
        }

        // Resolves a transaction's amount in THIS wallet's currency, preferring
        // the deterministic rate recorded at creation time over any live/fallback
        // recomputation. Order matters:
        //   1. Same currency        → amount as-is (also the correct path for
        //                             transfers OUT, whose storedRate targets the
        //                             destination wallet, not this one).
        //   2. storedRate present   → amount × storedRate (authoritative, and it
        //                             respects a genuine 1.0 cross-currency rate).
        //   3. legacy exchangeRate  → amount × exchangeRate (pre-storedRate rows).
        //   4. constant fallback    → best-effort conversion for rows with no rate.
        func convertToWalletAmount(for txn: Transaction, fallbackFrom txnCurrency: String) -> Decimal {
            if txnCurrency == walletCurrency {
                return txn.amount
            }
            if let rate = txn.storedRate, rate > 0 {
                return txn.amount * rate
            }
            if txn.exchangeRate > 0 && txn.exchangeRate != 1.0 {
                return txn.amount * txn.exchangeRate
            }
            return convertToWalletCurrency(txn.amount, from: txnCurrency)
        }

        // 1. Process Outgoing Transactions (Income, Expense, Transfer OUT)
        if let outgoing = self.outgoingTransactions {
            for txn in outgoing {
                // Legacy event-linked wallet transactions are excluded from personal balance.
                if txn.event != nil { continue }

                // Convert the amount into this wallet's currency. Same-currency is
                // checked first so transfers OUT (denominated in the source
                // wallet's currency, but whose stored rate targets the *dest*) are
                // never mis-converted.
                let convertedAmount = convertToWalletAmount(for: txn, fallbackFrom: txn.currencyCode)

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
                // Legacy event-linked wallet transactions are excluded from personal balance.
                if txn.event != nil { continue }
                
                if txn.type == .transfer {
                    // Transfer IN: amount is denominated in the source wallet's
                    // currency; storedRate (dest/source) converts it into this
                    // (destination) wallet's currency deterministically.
                    total += convertToWalletAmount(for: txn, fallbackFrom: txn.currencyCode)
                }
            }
        }
        
        return total
    }
}
