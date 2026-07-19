import Foundation

/// Plain-value savings ledger row used by private-context loaders and pure tests.
nonisolated struct SavingsLedgerEntrySnapshot: Sendable, Equatable, Identifiable {
    let id: UUID
    let goalID: UUID
    let date: Date
    let amount: Decimal
    let currencyCode: String
    let isWithdrawal: Bool
}

/// The single authority for savings-ledger arithmetic.
///
/// Conversion deliberately uses only the supplied live rate table. Unlike the
/// general display converter, it never consults fallback rates and never treats
/// two currencies as 1:1 when a live rate is unavailable. This preserves the
/// reconciler's established strict semantics while making the same formula
/// available to background Plan loaders.
nonisolated enum SavingsLedgerCalculator {
    struct Result: Sendable, Equatable {
        /// Floored balance presented by savings screens and completion logic.
        let total: Decimal
        /// Signed balance before the presentation floor. Charts keep this value
        /// running so a withdrawal below zero is not silently discarded.
        let rawTotal: Decimal
        let hasUnconvertedRows: Bool

        var isDeterminate: Bool { !hasUnconvertedRows }
    }

    static func calculate(
        startingBalance: Decimal,
        startingCurrencyCode: String,
        goalCurrencyCode: String,
        rows: [SavingsLedgerEntrySnapshot],
        rates: [String: Double]
    ) -> Result {
        var rawTotal: Decimal = 0
        var hasUnconvertedRows = false

        if startingBalance != 0 {
            if let converted = convertStrict(
                startingBalance,
                from: startingCurrencyCode,
                to: goalCurrencyCode,
                rates: rates
            ) {
                rawTotal += converted
            } else {
                hasUnconvertedRows = true
            }
        }

        for row in rows {
            guard let converted = convertStrict(
                row.amount,
                from: row.currencyCode,
                to: goalCurrencyCode,
                rates: rates
            ) else {
                hasUnconvertedRows = true
                continue
            }
            rawTotal += row.isWithdrawal ? -converted : converted
        }

        return Result(
            total: max(0, rawTotal),
            rawTotal: rawTotal,
            hasUnconvertedRows: hasUnconvertedRows
        )
    }

    static func convertStrict(
        _ amount: Decimal,
        from source: String,
        to target: String,
        rates: [String: Double]
    ) -> Decimal? {
        guard source != target else { return amount }
        guard let sourceRate = rates[source], sourceRate.isFinite, sourceRate > 0,
              let targetRate = rates[target], targetRate.isFinite, targetRate > 0 else {
            return nil
        }
        return amount / Decimal(sourceRate) * Decimal(targetRate)
    }
}
