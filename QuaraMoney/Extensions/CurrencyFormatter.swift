import Foundation

extension Decimal {
    /// Formats the decimal as a currency string, respecting the currency code's native symbol.
    /// - Parameter currencyCode: The 3-letter ISO currency code (e.g., "USD", "KHR")
    /// - Returns: A localized, standard currency string (e.g., "៛1,000.00", "$1,000.00")
    func formattedAmount(for currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        
        // Ensure that the native symbol is used (Swift sometimes defaults to "KHR" instead of "៛")
        let locale = NSLocale(localeIdentifier: currencyCode)
        if let symbol = locale.displayName(forKey: .currencySymbol, value: currencyCode) {
            formatter.currencySymbol = symbol
        }
        
        let fractionDigits = currencyCode.uppercased() == "JPY" ? 0 : 2
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        
        return formatter.string(from: NSDecimalNumber(decimal: self)) ?? ""
    }
}

extension Double {
    /// Formats the double as a currency string, respecting the currency code's native symbol.
    func formattedAmount(for currencyCode: String) -> String {
        return Decimal(self).formattedAmount(for: currencyCode)
    }
}

extension Int64 {
    /// Formats the minor unit Int64 as a currency string using the provided currency code.
    func formattedMinorAmount(for currencyCode: String) -> String {
        // Assume MoneyMinorUnitConverter handles the math, but we need to do it manually if not importing Services
        // A simple workaround based on the 2 digit standard since JPY is 0:
        let fractionDigits = currencyCode.uppercased() == "JPY" ? 0 : 2
        let divisor: Decimal = fractionDigits > 0 ? pow(10, fractionDigits) : 1
        let amount = Decimal(self) / divisor
        
        return amount.formattedAmount(for: currencyCode)
    }
}
