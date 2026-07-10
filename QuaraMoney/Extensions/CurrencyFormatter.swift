import Foundation

/// Process-wide cache of fully configured `NumberFormatter`s.
///
/// `NumberFormatter` construction loads ICU locale data and is one of the most
/// expensive Foundation objects to create; the currency helpers below run in
/// every transaction/wallet row body, so they must never build one per call.
/// Formatters are configured once, cached, and only *read* afterwards
/// (`string(from:)` is thread-safe on iOS 7+ as long as the formatter isn't
/// mutated), which makes the cache safe for the nonisolated call sites.
enum CurrencyFormatterCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var formatters: [String: NumberFormatter] = [:]
    nonisolated(unsafe) private static var symbols: [String: String] = [:]

    /// Wipe on language change so symbols/locale-derived config can rebuild.
    nonisolated static func invalidate() {
        lock.lock(); defer { lock.unlock() }
        formatters.removeAll()
        symbols.removeAll()
    }

    /// The native symbol for a currency code (e.g. "$", "៛"), cached.
    nonisolated static func symbol(for currencyCode: String) -> String {
        lock.lock(); defer { lock.unlock() }
        if let cached = symbols[currencyCode] { return cached }
        let locale = NSLocale(localeIdentifier: currencyCode)
        let symbol = locale.displayName(forKey: .currencySymbol, value: currencyCode) ?? currencyCode
        symbols[currencyCode] = symbol
        return symbol
    }

    /// Plain decimal formatter for the calculator keypad's amount display
    /// (0–2 fraction digits, "," grouping — deliberately locale-fixed to match
    /// the keypad's Western-digit input).
    nonisolated(unsafe) static let keypadAmount: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        return formatter
    }()

    /// A currency formatter for `currencyCode` with the given fraction-digit
    /// bounds. The key includes the digit config because the "short" style
    /// (K/M suffixes) uses different bounds than the standard style.
    nonisolated static func formatter(for currencyCode: String, minFractionDigits: Int, maxFractionDigits: Int) -> NumberFormatter {
        let key = "\(currencyCode)-\(minFractionDigits)-\(maxFractionDigits)"
        lock.lock(); defer { lock.unlock() }
        if let cached = formatters[key] { return cached }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        // Ensure that the native symbol is used (Swift sometimes defaults to "KHR" instead of "៛")
        let locale = NSLocale(localeIdentifier: currencyCode)
        if let symbol = locale.displayName(forKey: .currencySymbol, value: currencyCode) {
            formatter.currencySymbol = symbol
        }
        formatter.minimumFractionDigits = minFractionDigits
        formatter.maximumFractionDigits = maxFractionDigits

        formatters[key] = formatter
        return formatter
    }
}

/// Same idea for `DateFormatter` (equally expensive to construct): cached per
/// (dateFormat, locale) pair. Callers pass the locale explicitly so the in-app
/// language (incl. Khmer digits) is honored; see `Locale.app`.
enum AppDateFormatterCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]

    nonisolated static func invalidate() {
        lock.lock(); defer { lock.unlock() }
        formatters.removeAll()
    }

    /// A cached `DateFormatter` for a fixed `dateFormat` string in `locale`.
    nonisolated static func formatter(dateFormat: String, locale: Locale) -> DateFormatter {
        let key = "\(dateFormat)|\(locale.identifier)"
        lock.lock(); defer { lock.unlock() }
        if let cached = formatters[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = dateFormat
        formatters[key] = formatter
        return formatter
    }
}

extension Decimal {
    /// Formats the decimal as a currency string, respecting the currency code's native symbol.
    /// - Parameter currencyCode: The 3-letter ISO currency code (e.g., "USD", "KHR")
    /// - Returns: A localized, standard currency string (e.g., "៛1,000.00", "$1,000.00")
    nonisolated func formattedAmount(for currencyCode: String) -> String {
        let fractionDigits = MoneyMinorUnitConverter.fractionDigits(for: currencyCode)
        let formatter = CurrencyFormatterCache.formatter(
            for: currencyCode,
            minFractionDigits: fractionDigits,
            maxFractionDigits: fractionDigits
        )
        return formatter.string(from: NSDecimalNumber(decimal: self)) ?? ""
    }

    /// Formats the decimal as a short currency string (e.g., "$1K", "$20.5K", "៛5M")
    nonisolated func formattedAmountShort(for currencyCode: String) -> String {
        let absValue = abs(self)

        let valueToFormat: Decimal
        let suffix: String
        let formatter: NumberFormatter

        if absValue >= 1_000_000 {
            valueToFormat = self / 1_000_000
            suffix = "M"
            formatter = CurrencyFormatterCache.formatter(for: currencyCode, minFractionDigits: 0, maxFractionDigits: 1)
        } else if absValue >= 1_000 {
            valueToFormat = self / 1_000
            suffix = "K"
            formatter = CurrencyFormatterCache.formatter(for: currencyCode, minFractionDigits: 0, maxFractionDigits: 1)
        } else {
            valueToFormat = self
            suffix = ""
            let fractionDigits = MoneyMinorUnitConverter.fractionDigits(for: currencyCode)
            formatter = CurrencyFormatterCache.formatter(for: currencyCode, minFractionDigits: 0, maxFractionDigits: fractionDigits)
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
        // Use the single source of truth for fraction digits so minor-unit math
        // matches MoneyMinorUnitConverter (the ledger). Avoids 10-100x drift for
        // currencies whose ISO minor unit isn't 2 (e.g. VND/CLP=0, KWD/BHD=3).
        let amount = MoneyMinorUnitConverter.fromMinorUnits(self, currencyCode: currencyCode)
        return amount.formattedAmount(for: currencyCode)
    }
}
