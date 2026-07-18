import Foundation
import SwiftUI
import Observation

/// `@Observable` (not ObservableObject): rate-table merges (~160 keys after a
/// fetch) and recent-currency edits no longer invalidate every observer — views
/// re-render only when a property they actually read changes.
@MainActor
@Observable
final class CurrencyManager {
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
    
    var preferredCurrencyCode: String {
        didSet {
            UserDefaults.standard.set(preferredCurrencyCode, forKey: "preferredCurrencyCode")
            NotificationCenter.default.post(name: .preferredCurrencyDidChange, object: nil)
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
    var rates: [String: Double] = ["USD": 1.0]
    
    // Last fetch timestamp
    private var lastRatesFetchDate: Double {
        get { UserDefaults.standard.double(forKey: "lastRatesFetchDate") }
        set { UserDefaults.standard.set(newValue, forKey: "lastRatesFetchDate") }
    }
    nonisolated static let ratesCacheKey = "cachedRates"
    private var ratesCacheKey: String { Self.ratesCacheKey }

    /// The current exchange rates read without main-actor isolation: the cached
    /// daily rates when available, otherwise the static fallback table. Lets
    /// models (e.g. `Debt`) convert amounts using the same real rates the app
    /// fetched, instead of crude approximations.
    nonisolated static var currentRates: [String: Double] {
        if let data = UserDefaults.standard.data(forKey: ratesCacheKey),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        return fallbackRates
    }

    private let recentCurrenciesKey = "recentCurrencies"
    
    private init() {
        self.preferredCurrencyCode = UserDefaults.standard.string(forKey: "preferredCurrencyCode") ?? "USD"
        self.recentCurrencies = UserDefaults.standard.stringArray(forKey: "recentCurrencies") ?? []
        
        loadCachedRates()
        // Removed auto-fetch on launch to save resources as requested
    }
    
    var recentCurrencies: [String] = [] {
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
    
    // @ObservationIgnored: @Observable can't track lazy storage, and this list
    // is immutable after first computation anyway.
    @ObservationIgnored private(set) lazy var availableCurrencyInfos: [CurrencyInfo] = {
        availableCurrencies.map { code in
            let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
            let symbol = String.currencySymbol(for: code)
            return CurrencyInfo(id: code, name: name, symbol: symbol)
        }
    }()
    
    /// Instance conversion using the live rate table. Delegates to the single
    /// static implementation so every call site (net worth, reports, budgets)
    /// resolves missing rates through the same fallback table — previously this
    /// method skipped `fallbackRates` and silently returned the amount
    /// unchanged for unknown pairs, so screens could disagree about the same
    /// data depending on which convert they happened to call.
    func convert(amount: Decimal, from sourceCurrency: String, to targetCurrency: String) -> Decimal {
        Self.convert(amount: amount, from: sourceCurrency, to: targetCurrency, rates: rates)
    }
    
    @discardableResult
    func fetchRates() async -> Bool {
        // We only really need to fetch if it's been a while, or if we are forced.
        // For now, let's respect a simple cache duration of 24 hours to avoid spamming the API
        // even if the user switches currencies back and forth.
        let now = Date().timeIntervalSince1970
        if rates.count > 1 && now - lastRatesFetchDate < 86400 {
            return true
        }

        // Free API: open.er-api.com
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
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
            NotificationCenter.default.post(name: .currencyRatesDidChange, object: self)
            #if DEBUG
            print("Rates fetched successfully. USD -> KHR: \(self.rates["KHR"] ?? 0)")
            #endif
            return true
        } catch {
            #if DEBUG
            print("Failed to fetch rates: \(error)")
            #endif
            // Fallback defaults if empty
            if rates["KHR"] == nil { rates["KHR"] = 4000.0 }
            return false
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
    ///
    /// Falls back to `convertOrNil`; if conversion is genuinely impossible
    /// (unknown currency with no fallback rate) it returns the amount unchanged
    /// to preserve historical behavior. Prefer `convertOrNil` in new code so the
    /// caller can decide how to handle unconvertible amounts rather than silently
    /// mixing currencies 1:1.
    nonisolated static func convert(amount: Decimal, from source: String, to target: String, rates: [String: Double]) -> Decimal {
        convertOrNil(amount: amount, from: source, to: target, rates: rates) ?? amount
    }

    /// Converts an amount between currencies, returning `nil` when no rate is
    /// available for either currency (in `rates` or in `fallbackRates`).
    /// This lets callers exclude or flag unconvertible amounts instead of
    /// summing two different currencies as if they were equal.
    nonisolated static func convertOrNil(amount: Decimal, from source: String, to target: String, rates: [String: Double]) -> Decimal? {
        guard source != target else { return amount }

        // Resolve each rate from live rates first, then the static fallback table.
        let sourceRate = rates[source] ?? fallbackRates[source]
        let targetRate = rates[target] ?? fallbackRates[target]

        guard let sourceRate, let targetRate, sourceRate > 0 else {
            return nil
        }

        let amountUSD = amount / Decimal(sourceRate)
        return amountUSD * Decimal(targetRate)
    }
}

struct ExchangeRateResponse: Codable {
    let result: String
    let rates: [String: Double]
}

