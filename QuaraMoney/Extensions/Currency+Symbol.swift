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

extension String {
    /// Emoji flag for a currency code, derived from its ISO 3166 region prefix
    /// (e.g. "KHR" → 🇰🇭). Returns `nil` for supranational or metal codes
    /// (XAF, XAU, …) whose prefix isn't a real region.
    static func currencyFlag(for currencyCode: String) -> String? {
        let code = currencyCode.uppercased()
        let region = currencyFlagRegionOverrides[code] ?? String(code.prefix(2))
        guard region.count == 2, currencyFlagRegions.contains(region) else { return nil }

        var flag = ""
        for scalar in region.unicodeScalars {
            guard let indicator = UnicodeScalar(scalar.value + 127_397) else { return nil }
            flag.unicodeScalars.append(indicator)
        }
        return flag
    }
}

/// Currency codes whose first two letters aren't the region we want to show.
private let currencyFlagRegionOverrides: [String: String] = [
    "EUR": "EU"
]

/// Two-letter regions that render as a flag, computed once.
private let currencyFlagRegions: Set<String> = {
    var regions = Set(Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 })
    regions.insert("EU")
    return regions
}()
