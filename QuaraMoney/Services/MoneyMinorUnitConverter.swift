import Foundation

enum MoneyMinorUnitConverter {
    static func fractionDigits(for currencyCode: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return max(0, formatter.maximumFractionDigits)
    }
    
    static func toMinorUnits(_ amount: Decimal, currencyCode: String) -> Int64 {
        let digits = fractionDigits(for: currencyCode)
        let multiplier = pow10(digits)
        let scaled = amount * multiplier
        let rounded = NSDecimalNumber(decimal: scaled).rounding(accordingToBehavior: nil)
        return rounded.int64Value
    }
    
    static func fromMinorUnits(_ amountMinor: Int64, currencyCode: String) -> Decimal {
        let digits = fractionDigits(for: currencyCode)
        let divisor = pow10(digits)
        return Decimal(amountMinor) / divisor
    }
    
    private static func pow10(_ exponent: Int) -> Decimal {
        guard exponent > 0 else { return 1 }
        var value: Decimal = 1
        for _ in 0..<exponent {
            value *= 10
        }
        return value
    }
}
