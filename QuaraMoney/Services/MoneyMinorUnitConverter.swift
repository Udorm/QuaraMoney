import Foundation

enum MoneyMinorUnitConverter {
    // ISO fraction digits are constant per currency; resolving them requires a
    // NumberFormatter (expensive to build) and this runs inside every
    // `formattedAmount` call, so the answers are memoized.
    private static let digitsLock = NSLock()
    nonisolated(unsafe) private static var digitsByCurrency: [String: Int] = [:]

    nonisolated static func fractionDigits(for currencyCode: String) -> Int {
        digitsLock.lock(); defer { digitsLock.unlock() }
        if let cached = digitsByCurrency[currencyCode] { return cached }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let digits = max(0, formatter.maximumFractionDigits)
        digitsByCurrency[currencyCode] = digits
        return digits
    }

    nonisolated static func toMinorUnits(_ amount: Decimal, currencyCode: String) -> Int64 {
        let digits = fractionDigits(for: currencyCode)
        let multiplier = pow10(digits)
        let scaled = amount * multiplier
        let rounded = NSDecimalNumber(decimal: scaled).rounding(accordingToBehavior: nil)
        return rounded.int64Value
    }

    nonisolated static func fromMinorUnits(_ amountMinor: Int64, currencyCode: String) -> Decimal {
        let digits = fractionDigits(for: currencyCode)
        let divisor = pow10(digits)
        return Decimal(amountMinor) / divisor
    }

    nonisolated private static func pow10(_ exponent: Int) -> Decimal {
        guard exponent > 0 else { return 1 }
        var value: Decimal = 1
        for _ in 0..<exponent {
            value *= 10
        }
        return value
    }
}
