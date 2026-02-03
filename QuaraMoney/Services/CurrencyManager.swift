import Foundation
import SwiftUI
import Combine

@MainActor
class CurrencyManager: ObservableObject {
    static let shared = CurrencyManager()
    
    @Published var preferredCurrencyCode: String {
        didSet {
            UserDefaults.standard.set(preferredCurrencyCode, forKey: "preferredCurrencyCode")
        }
    }
    
    // Rates relative to USD (Base)
    // Key: Currency Code, Value: Rate (e.g. "KHR": 4000.0)
    @Published var rates: [String: Double] = ["USD": 1.0]
    
    // Last fetch timestamp
    private var lastRatesFetchDate: Double {
        get { UserDefaults.standard.double(forKey: "lastRatesFetchDate") }
        set { UserDefaults.standard.set(newValue, forKey: "lastRatesFetchDate") }
    }
    private let ratesCacheKey = "cachedRates"
    
    private init() {
        self.preferredCurrencyCode = UserDefaults.standard.string(forKey: "preferredCurrencyCode") ?? "USD"
        
        loadCachedRates()
        // Auto-fetch if stale (> 24 hours) or empty
        if rates.count <= 1 || Date().timeIntervalSince1970 - lastRatesFetchDate > 86400 {
            Task {
                await fetchRates()
            }
        }
    }
    
    // Currencies we support for now (add more as needed)
    let availableCurrencies = ["USD", "KHR", "EUR", "THB", "SGD", "JPY"]
    
    func convert(amount: Decimal, from sourceCurrency: String, to targetCurrency: String) -> Decimal {
        guard let sourceRate = rates[sourceCurrency], let targetRate = rates[targetCurrency] else {
            // Fallback logic if rates are missing
             if sourceCurrency == "USD" && targetCurrency == "KHR" { return amount * 4000 }
             if sourceCurrency == "KHR" && targetCurrency == "USD" { return amount / 4000 }
             if sourceCurrency == targetCurrency { return amount }
            return amount // Return original if unknown (better than 0?)
        }
        
        // Convert to USD first (Base), then to Target
        // Amount (Source) / SourceRate = Amount (USD)
        // Amount (USD) * TargetRate = Amount (Target)
        
        let amountUSD = amount / Decimal(sourceRate)
        let amountTarget = amountUSD * Decimal(targetRate)
        
        return amountTarget
    }
    
    func fetchRates() async {
        // Free API: open.er-api.com
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ExchangeRateResponse.self, from: data)
            
            // Merge response rates into our rates
            for (code, rate) in response.rates {
                self.rates[code] = rate
            }
            
            // Hardcode KHR fallback if API returns weird value or network fails, 
            // but here we are in success block. 
            // Ensures common currencies exist.
            
            saveRatesToCache()
            
            self.lastRatesFetchDate = Date().timeIntervalSince1970
            #if DEBUG
            print("Rates fetched successfully. USD -> KHR: \(self.rates["KHR"] ?? 0)")
            #endif
            
        } catch {
            #if DEBUG
            print("Failed to fetch rates: \(error)")
            #endif
            // Fallback defaults if empty
            if rates["KHR"] == nil { rates["KHR"] = 4000.0 }
        }
    }
    
    private func saveRatesToCache() {
        if let encoded = try? JSONEncoder().encode(rates) {
            UserDefaults.standard.set(encoded, forKey: ratesCacheKey)
        }
    }
    
    private func loadCachedRates() {
        if let data = UserDefaults.standard.data(forKey: ratesCacheKey),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            self.rates = decoded
        }
        
        // Ensure defaults exist
        if rates["USD"] == nil { rates["USD"] = 1.0 }
        if rates["KHR"] == nil { rates["KHR"] = 4000.0 }
    }
}

struct ExchangeRateResponse: Codable {
    let result: String
    let rates: [String: Double]
}

// MARK: - Transaction Calculation Utilities
extension CurrencyManager {
    /// Calculate total of transactions converted to target currency
    /// - Parameters:
    ///   - transactions: Array of transactions to sum
    ///   - targetCurrency: The currency code to convert all amounts to (e.g., "USD")
    ///   - filter: Optional filter to apply before summing
    /// - Returns: Total amount in target currency
    func calculateTotal(
        transactions: [Transaction],
        targetCurrency: String,
        filter: ((Transaction) -> Bool)? = nil
    ) -> Decimal {
        let filtered = filter != nil ? transactions.filter(filter!) : transactions
        return filtered.reduce(Decimal.zero) { total, txn in
            let converted = convert(amount: txn.amount, from: txn.currencyCode, to: targetCurrency)
            return total + converted
        }
    }
    
    /// Calculate expense total (type == .expense) converted to target currency
    func calculateExpenseTotal(transactions: [Transaction], targetCurrency: String) -> Decimal {
        calculateTotal(transactions: transactions, targetCurrency: targetCurrency) { $0.type == .expense }
    }
    
    /// Calculate income total (type == .income) converted to target currency
    func calculateIncomeTotal(transactions: [Transaction], targetCurrency: String) -> Decimal {
        calculateTotal(transactions: transactions, targetCurrency: targetCurrency) { $0.type == .income }
    }
}
