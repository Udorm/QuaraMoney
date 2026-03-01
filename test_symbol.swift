import Foundation

func getSymbol(forCurrencyCode code: String) -> String {
    let locale = NSLocale(localeIdentifier: code)
    if let symbol = locale.displayName(forKey: .currencySymbol, value: code) {
        return symbol
    }
    return code
}

print(getSymbol(forCurrencyCode: "KHR"))
print(getSymbol(forCurrencyCode: "USD"))
print(getSymbol(forCurrencyCode: "EUR"))

