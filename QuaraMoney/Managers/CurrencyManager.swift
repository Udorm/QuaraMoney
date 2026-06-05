import Foundation
import SwiftUI
import Combine

@MainActor
class CurrencyManager: ObservableObject {
    static let shared = CurrencyManager()

    /// Fallback exchange rates relative to USD — safe to access from any isolation context.
    /// Used by Wallet balance computation where @MainActor rates may not be accessible.
    nonisolated static let fallbackRates: [String: Double] = [
        "USD": 1.0,
        "KHR": 4000.0,
        "EUR": 0.92,
        "THB": 35.0,
        "SGD": 1.35,
        "JPY": 150.0
    ]
    
    @Published var preferredCurrencyCode: String {
        didSet {
            UserDefaults.standard.set(preferredCurrencyCode, forKey: "preferredCurrencyCode")
            // Fetch rates if we switched to a non-USD currency and don't have recent data
             if preferredCurrencyCode != "USD" {
                 Task {
                     await fetchRates()
                 }
             }
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
    
    private let recentCurrenciesKey = "recentCurrencies"
    
    private init() {
        self.preferredCurrencyCode = UserDefaults.standard.string(forKey: "preferredCurrencyCode") ?? "USD"
        self.recentCurrencies = UserDefaults.standard.stringArray(forKey: "recentCurrencies") ?? []
        
        loadCachedRates()
        // Removed auto-fetch on launch to save resources as requested
    }
    
    @Published var recentCurrencies: [String] = [] {
        didSet {
            UserDefaults.standard.set(recentCurrencies, forKey: recentCurrenciesKey)
        }
    }
    
    func addToRecent(currencyCode: String) {
        // Remove if exists to move to top
        if let index = recentCurrencies.firstIndex(of: currencyCode) {
            recentCurrencies.remove(at: index)
        }
        
        // Insert at beginning
        recentCurrencies.insert(currencyCode, at: 0)
        
        // Limit to 5
        if recentCurrencies.count > 5 {
            recentCurrencies = Array(recentCurrencies.prefix(5))
        }
    }
    
    // Support all common ISO currencies
    var availableCurrencies: [String] {
        Locale.commonISOCurrencyCodes.sorted()
    }
    
    struct CurrencyInfo: Identifiable, Hashable {
        let id: String // Currency Code (e.g., "USD")
        let name: String
        let symbol: String
        
        var searchString: String {
            "\(id) \(name) \(symbol)".lowercased()
        }
    }
    
    private(set) lazy var availableCurrencyInfos: [CurrencyInfo] = {
        availableCurrencies.map { code in
            let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
            let symbol = String.currencySymbol(for: code)
            return CurrencyInfo(id: code, name: name, symbol: symbol)
        }
    }()
    
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
        // We only really need to fetch if it's been a while, or if we are forced.
        // For now, let's respect a simple cache duration of 24 hours to avoid spamming the API
        // even if the user switches currencies back and forth.
        let now = Date().timeIntervalSince1970
        if rates.count > 1 && now - lastRatesFetchDate < 86400 {
            return
        }

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
        do {
            let encoded = try JSONEncoder().encode(rates)
            UserDefaults.standard.set(encoded, forKey: ratesCacheKey)
        } catch {
            #if DEBUG
            print("[CurrencyManager] Failed to encode rates cache: \(error)")
            #endif
        }
    }
    
    private func loadCachedRates() {
        if let data = UserDefaults.standard.data(forKey: ratesCacheKey) {
            do {
                self.rates = try JSONDecoder().decode([String: Double].self, from: data)
            } catch {
                #if DEBUG
                print("[CurrencyManager] Failed to decode rates cache: \(error)")
                #endif
            }
        }
        
        // Ensure defaults exist
        if rates["USD"] == nil { rates["USD"] = 1.0 }
        if rates["KHR"] == nil { rates["KHR"] = 4000.0 }
    }
}

// MARK: - Static Currency Conversion (nonisolated)
extension CurrencyManager {
    /// Converts an amount between currencies using provided rates.
    /// Safe to call from any isolation context (nonisolated, static).
    nonisolated static func convert(amount: Decimal, from source: String, to target: String, rates: [String: Double]) -> Decimal {
        guard source != target else { return amount }
        guard let sourceRate = rates[source], let targetRate = rates[target] else {
            if source == "USD" && target == "KHR" { return amount * 4000 }
            if source == "KHR" && target == "USD" { return amount / 4000 }
            return amount
        }
        let amountUSD = amount / Decimal(sourceRate)
        return amountUSD * Decimal(targetRate)
    }
}

struct ExchangeRateResponse: Codable {
    let result: String
    let rates: [String: Double]
}


