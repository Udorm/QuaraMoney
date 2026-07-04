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

    // MARK: - Per-transaction amounts

    /// Converts an amount into this wallet's currency using CurrencyManager's
    /// constant fallback rates (safe from any isolation context — keeps legacy
    /// balances stable rather than drifting with each network fetch).
    private func convertWithFallbackRates(_ amount: Decimal, from txnCurrency: String) -> Decimal {
        if txnCurrency == currencyCode {
            return amount
        }
        let rates = CurrencyManager.fallbackRates
        guard let sourceRate = rates[txnCurrency], let targetRate = rates[currencyCode] else {
            return amount
        }
        let amountInUSD = amount / Decimal(sourceRate)
        return amountInUSD * Decimal(targetRate)
    }

    /// Resolves a transaction's amount in THIS wallet's currency, preferring
    /// the deterministic rate recorded at creation time over any live/fallback
    /// recomputation. Order matters:
    ///   1. Same currency        → amount as-is (also the correct path for
    ///                             transfers OUT, whose storedRate targets the
    ///                             destination wallet, not this one).
    ///   2. storedRate present   → amount × storedRate (authoritative, and it
    ///                             respects a genuine 1.0 cross-currency rate).
    ///   3. legacy exchangeRate  → amount × exchangeRate (pre-storedRate rows).
    ///   4. constant fallback    → best-effort conversion for rows with no rate.
    func amountInWalletCurrency(for txn: Transaction) -> Decimal {
        if txn.currencyCode == currencyCode {
            return txn.amount
        }
        if let rate = txn.storedRate, rate > 0 {
            return txn.amount * rate
        }
        if txn.exchangeRate > 0 && txn.exchangeRate != 1.0 {
            return txn.amount * txn.exchangeRate
        }
        return convertWithFallbackRates(txn.amount, from: txn.currencyCode)
    }

    /// Signed effect of an outgoing transaction (this wallet is the source)
    /// on this wallet's balance, in the wallet's currency. Returns nil when the
    /// transaction should not count (tombstoned or legacy event-linked).
    private func outgoingDelta(for txn: Transaction) -> Decimal? {
        // Soft-deleted transactions are tombstones — never count them.
        if txn.deletedAt != nil { return nil }
        // Legacy event-linked wallet transactions are excluded from personal balance.
        if txn.event != nil { return nil }

        // Convert the amount into this wallet's currency. Same-currency is
        // checked first so transfers OUT (denominated in the source wallet's
        // currency, but whose stored rate targets the *dest*) are never
        // mis-converted.
        let convertedAmount = amountInWalletCurrency(for: txn)
        switch txn.type {
        case .income:
            return convertedAmount
        case .expense, .transfer:
            return -convertedAmount
        case .adjustment:
            // Adjustments directly affect balance (can be positive or negative)
            return convertedAmount
        }
    }

    /// Signed effect of an incoming transaction (this wallet is the destination)
    /// on this wallet's balance, in the wallet's currency. Only transfers land
    /// here; the amount is denominated in the source wallet's currency and
    /// storedRate (dest/source) converts it deterministically.
    private func incomingDelta(for txn: Transaction) -> Decimal? {
        if txn.deletedAt != nil { return nil }
        if txn.event != nil { return nil }
        guard txn.type == .transfer else { return nil }
        return amountInWalletCurrency(for: txn)
    }

    /// Core balance computation - iterates all transactions
    private func computeBalance() -> Decimal {
        var total: Decimal = 0
        for txn in outgoingTransactions ?? [] {
            if let delta = outgoingDelta(for: txn) { total += delta }
        }
        for txn in incomingTransactions ?? [] {
            if let delta = incomingDelta(for: txn) { total += delta }
        }
        return total
    }

    // MARK: - Balance history

    struct BalancePoint: Identifiable {
        let date: Date
        let balance: Decimal
        var id: Date { date }
    }

    /// End-of-day balance for each of the last `days` days (oldest first, last
    /// point is today). Walks backwards from the current balance subtracting
    /// each day's net delta, so it uses the exact same per-transaction
    /// semantics as `balance`.
    func dailyBalanceSeries(days: Int, calendar: Calendar = .current) -> [BalancePoint] {
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: Date())
        guard let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }

        // Net delta per day (start-of-day key) inside the window; recent
        // windows are small so a dictionary pass is cheap.
        var deltaByDay: [Date: Decimal] = [:]
        func accumulate(_ txn: Transaction, delta: Decimal?) {
            guard let delta, txn.date >= windowStart else { return }
            let day = calendar.startOfDay(for: min(txn.date, Date()))
            deltaByDay[day, default: 0] += delta
        }
        for txn in outgoingTransactions ?? [] {
            accumulate(txn, delta: outgoingDelta(for: txn))
        }
        for txn in incomingTransactions ?? [] {
            accumulate(txn, delta: incomingDelta(for: txn))
        }

        var points: [BalancePoint] = []
        points.reserveCapacity(days)
        var running = balance
        var day = today
        for _ in 0..<days {
            points.append(BalancePoint(date: day, balance: running))
            running -= deltaByDay[day] ?? 0
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return points.reversed()
    }
}
