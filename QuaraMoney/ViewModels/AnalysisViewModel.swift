import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class AnalysisViewModel: ObservableObject {
    private var modelContext: ModelContext?
    
    // MARK: - Filters
    enum Period: String, CaseIterable, Identifiable {
        case thisMonth = "This Month"
        case lastMonth = "Last Month"
        case thisYear = "This Year"
        case allTime = "All Time"
        case custom = "Custom"
        
        var id: String { self.rawValue }
    }
    
    @Published var selectedPeriod: Period = .thisMonth {
        didSet {
            updateDateRange()
            refreshData()
        }
    }
    
    @Published var customStartDate: Date = Date() {
        didSet { if selectedPeriod == .custom { refreshData() } }
    }
    
    @Published var customEndDate: Date = Date() {
        didSet { if selectedPeriod == .custom { refreshData() } }
    }
    
    @Published var selectedWallet: Wallet? {
        didSet { refreshData() }
    }
    
    // Internal Date Range derived from filters
    private var startDate: Date = Date()
    private var endDate: Date = Date()
    
    enum TimeGrouping {
        case daily
        case monthly
    }
    
    @Published var grouping: TimeGrouping = .daily
    
    // MARK: - Output Data
    @Published var netWorth: Decimal = 0
    @Published var totalIncome: Decimal = 0
    @Published var totalExpense: Decimal = 0
    @Published var savingsRate: Double = 0
    
    // For Charts
    @Published var dailyStats: [DailyStat] = []
    @Published var categoryStats: [CategoryStat] = []
    
    var isFilterActive: Bool {
        return selectedPeriod != .thisMonth || selectedWallet != nil
    }
    
    var filterDescription: String {
        var text = selectedPeriod.rawValue
        if selectedPeriod == .custom {
             text = "\(customStartDate.formatted(date: .abbreviated, time: .omitted)) - \(customEndDate.formatted(date: .abbreviated, time: .omitted))"
        }
        
        if let wallet = selectedWallet {
            text += " • \(wallet.name)"
        }
        return text
    }
    
    init() {
        updateDateRange()
    }
    
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Logic
    
    private func updateDateRange() {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedPeriod {
        case .thisMonth:
            grouping = .daily
            guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return }
            self.startDate = start
            self.endDate = end
        case .lastMonth:
            grouping = .daily
            guard let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                  let start = calendar.date(byAdding: .month, value: -1, to: thisMonthStart),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return }
            self.startDate = start
            self.endDate = end
        case .thisYear:
            grouping = .monthly
            guard let start = calendar.date(from: calendar.dateComponents([.year], from: now)),
                  let end = calendar.date(byAdding: .year, value: 1, to: start) else { return }
            self.startDate = start
            self.endDate = end
        case .allTime:
            grouping = .monthly
            self.startDate = .distantPast
            self.endDate = .distantFuture
        case .custom:
            self.startDate = calendar.startOfDay(for: customStartDate)
            if let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: customEndDate) {
                self.endDate = endOfDay
            } else {
                self.endDate = customEndDate
            }
            
            // If range > 60 days, default to monthly
            if let days = calendar.dateComponents([.day], from: startDate, to: endDate).day, days > 60 {
                grouping = .monthly
            } else {
                grouping = .daily
            }
        }
    }
    
    func refreshData() {
        fetchNetWorth()
        fetchTransactionsAndComputeStats()
    }
    
    private func fetchNetWorth() {
        // Net Worth is a snapshot of CURRENT balances.
        // It is NOT affected by the Date Filter (usually), but IS affected by Wallet Filter.
        // If specific wallet selected -> Show that wallet's balance.
        // If All Wallets -> Sum of all balances.
        
        guard let modelContext = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<Wallet>()
            let wallets = try modelContext.fetch(descriptor)
            
            var totalNW: Decimal = 0
            let targetCurrency = CurrencyManager.shared.preferredCurrencyCode
            
            let walletsToSum = selectedWallet == nil ? wallets : wallets.filter { $0.id == selectedWallet?.id }
            
            for wallet in walletsToSum {
                // Wallet.balance logic is computed property in extension.
                // We assume it handles its own internal transaction summing correctly (which it does).
                // We just need to convert the resulting balance to target currency.
                
                let balance = wallet.balance
                let converted = CurrencyManager.shared.convert(amount: balance, from: wallet.currencyCode, to: targetCurrency)
                totalNW += converted
            }
            
            self.netWorth = totalNW
            
        } catch {
            print("Error fetching wallets for Net Worth: \(error)")
        }
    }
    
    private func fetchTransactionsAndComputeStats() {
        let start = self.startDate
        let end = self.endDate
        let walletId = selectedWallet?.id
        
        let descriptor: FetchDescriptor<Transaction>
        
        // Build Predicate
        if let walletId = walletId {
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { txn in
                    txn.date >= start && txn.date < end &&
                    (txn.sourceWallet?.id == walletId || txn.destinationWallet?.id == walletId)
                }
            )
        } else {
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { txn in
                    txn.date >= start && txn.date < end
                }
            )
        }
        
        guard let modelContext = modelContext else { return }
        
        do {
            let transactions = try modelContext.fetch(descriptor)
            
            var inc: Decimal = 0
            var exp: Decimal = 0
            let targetCurrency = CurrencyManager.shared.preferredCurrencyCode
            
            // For Charts
            var rawChartData: [Date: (income: Decimal, expense: Decimal)] = [:]
            var rawCategoryData: [Category: Decimal] = [:] // Expense only for now
            
            let calendar = Calendar.current
            
            for txn in transactions {
                // Convert Amount
                let amount = CurrencyManager.shared.convert(amount: txn.amount, from: txn.currencyCode, to: targetCurrency)
                
                // Determine Chart Entry specific Date based on Grouping
                let chartDate: Date
                if grouping == .monthly {
                    // Normalize to start of Month
                    chartDate = calendar.date(from: calendar.dateComponents([.year, .month], from: txn.date)) ?? txn.date
                } else {
                    // Normalize to start of Day
                    chartDate = calendar.startOfDay(for: txn.date)
                }
                
                if txn.type == .income {
                    inc += amount
                    
                    var current = rawChartData[chartDate] ?? (0, 0)
                    current.income += amount
                    rawChartData[chartDate] = current
                    
                } else if txn.type == .expense {
                    exp += amount
                    
                    var current = rawChartData[chartDate] ?? (0, 0)
                    current.expense += amount
                    rawChartData[chartDate] = current
                    
                    // Category Stat
                    if let cat = txn.category {
                        rawCategoryData[cat, default: 0] += amount
                    }
                }
            }
            
            self.totalIncome = inc
            self.totalExpense = exp
            
            // Savings Rate
            if inc > 0 {
                let savings = inc - exp
                self.savingsRate = Double(truncating: savings as NSNumber) / Double(truncating: inc as NSNumber)
            } else {
                self.savingsRate = 0
            }
            
            // Prepare Chart Data
            self.dailyStats = rawChartData.map { (date, values) in
                DailyStat(date: date, income: values.income, expense: values.expense)
            }.sorted { $0.date < $1.date }
            
            self.categoryStats = rawCategoryData.map { (cat, amount) in
                CategoryStat(category: cat, amount: amount, colorHex: cat.colorHex)
            }.sorted { $0.amount > $1.amount }
            
        } catch {
            print("Error fetching transactions for Analysis: \(error)")
        }
    }
}

struct DailyStat: Identifiable {
    let id = UUID()
    let date: Date
    let income: Decimal
    let expense: Decimal
}

struct CategoryStat: Identifiable {
    let id = UUID()
    let category: Category
    let amount: Decimal
    let colorHex: String
}
