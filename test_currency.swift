import Foundation

let codes = ["USD", "KHR", "EUR", "JPY"]

for code in codes {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = code
    
    // Default locale
    print("\(code) default: \(formatter.string(from: 1000) ?? "") - symbol: \(formatter.currencySymbol ?? "")")
    
    formatter.locale = Locale(identifier: "en_US")
    print("\(code) en_US: \(formatter.string(from: 1000) ?? "") - symbol: \(formatter.currencySymbol ?? "")")
    
    formatter.locale = Locale(identifier: "km_KH")
    print("\(code) km_KH: \(formatter.string(from: 1000) ?? "") - symbol: \(formatter.currencySymbol ?? "")")
}

