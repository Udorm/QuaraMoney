import Foundation

extension String {
    /// Retrieves the native symbol for a given 3-letter currency code
    /// - Parameter currencyCode: The 3-letter ISO currency code (e.g., "USD", "KHR")
    /// - Returns: The native currency symbol (e.g., "$", "៛") or the code itself if not found
    static func currencySymbol(for currencyCode: String) -> String {
        // NSLocale construction + displayName lookup is expensive; cached.
        CurrencyFormatterCache.symbol(for: currencyCode)
    }
}
