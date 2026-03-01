import Foundation

extension Decimal {
    func formattedAmount(for currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        // Force en_US locale to simulate user's environment where it fails
        formatter.locale = Locale(identifier: "en_US")
        
        let locale = NSLocale(localeIdentifier: currencyCode)
        if let symbol = locale.displayName(forKey: .currencySymbol, value: currencyCode) {
            formatter.currencySymbol = symbol
        }
        
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        
        return formatter.string(from: NSDecimalNumber(decimal: self)) ?? ""
    }
}

let amount: Decimal = 1000
print(amount.formattedAmount(for: "KHR"))
print(amount.formattedAmount(for: "USD"))
