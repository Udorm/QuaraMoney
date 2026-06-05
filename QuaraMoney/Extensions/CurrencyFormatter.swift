import Foundation

extension Decimal {
    /// Formats the decimal as a currency string, respecting the currency code's native symbol.
    /// - Parameter currencyCode: The 3-letter ISO currency code (e.g., "USD", "KHR")
    /// - Returns: A localized, standard currency string (e.g., "៛1,000.00", "$1,000.00")
    nonisolated func formattedAmount(for currencyCode: String) -> String {
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
    
    /// Formats the decimal as a short currency string (e.g., "$1K", "$20.5K", "៛5M")
    nonisolated func formattedAmountShort(for currencyCode: String) -> String {
        let absValue = abs(self)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        
        let locale = NSLocale(localeIdentifier: currencyCode)
        if let symbol = locale.displayName(forKey: .currencySymbol, value: currencyCode) {
            formatter.currencySymbol = symbol
        }
        
        let valueToFormat: Decimal
        let suffix: String
        
        if absValue >= 1_000_000 {
            valueToFormat = self / 1_000_000
            suffix = "M"
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 1
        } else if absValue >= 1_000 {
            valueToFormat = self / 1_000
            suffix = "K"
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 1
        } else {
            valueToFormat = self
            suffix = ""
            let fractionDigits = currencyCode.uppercased() == "JPY" ? 0 : 2
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = fractionDigits
        }
        
        guard let formatted = formatter.string(from: NSDecimalNumber(decimal: valueToFormat)) else {
            return ""
        }
        return formatted + suffix
    }
}

extension Double {
    /// Formats the double as a currency string, respecting the currency code's native symbol.
    nonisolated func formattedAmount(for currencyCode: String) -> String {
        return Decimal(self).formattedAmount(for: currencyCode)
    }
    
    /// Formats the double as a short currency string.
    nonisolated func formattedAmountShort(for currencyCode: String) -> String {
        return Decimal(self).formattedAmountShort(for: currencyCode)
    }
}

extension Int64 {
    /// Formats the minor unit Int64 as a currency string using the provided currency code.
    nonisolated func formattedMinorAmount(for currencyCode: String) -> String {
        // Assume MoneyMinorUnitConverter handles the math, but we need to do it manually if not importing Services
        // A simple workaround based on the 2 digit standard since JPY is 0:
        let fractionDigits = currencyCode.uppercased() == "JPY" ? 0 : 2
        let divisor: Decimal = fractionDigits > 0 ? pow(10, fractionDigits) : 1
        let amount = Decimal(self) / divisor
        
        return amount.formattedAmount(for: currencyCode)
    }
}
