import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class AnalysisViewModel: ObservableObject {
    private var modelContext: ModelContext?
    
    // MARK: - Filters
    enum Period: String, CaseIterable, Identifiable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
        case sixMonths = "6 Months"
        case year = "Year"
        case custom = "Custom"
        
        var id: String { self.rawValue }
    }
    
    @Published var selectedPeriod: Period = .day {
        didSet {
            // Reset reference date to now when changing period
            currentReferenceDate = Date()
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
    
    enum TransactionTypeFilter: String, CaseIterable {
        case expense = "Expense"
        case income = "Income"
    }
    
    @Published var selectedTransactionType: TransactionTypeFilter = .expense {
        didSet { refreshData() }
    }
    
    // Reference date for navigation (scroll to change periods)
    @Published var currentReferenceDate: Date = Date()
    
    // Internal Date Range derived from filters
    private var startDate: Date = Date()
    private var endDate: Date = Date()
    
    enum TimeGrouping {
        case hour
        case day
        case week
        case month
        case year
    }
    
    @Published var grouping: TimeGrouping = .day
    
    // MARK: - Navigation
    
    func navigateBack() {
        let calendar = Calendar.current
        switch selectedPeriod {
        case .day:
            currentReferenceDate = calendar.date(byAdding: .day, value: -1, to: currentReferenceDate) ?? currentReferenceDate
        case .week:
            currentReferenceDate = calendar.date(byAdding: .weekOfYear, value: -1, to: currentReferenceDate) ?? currentReferenceDate
        case .month:
            currentReferenceDate = calendar.date(byAdding: .month, value: -1, to: currentReferenceDate) ?? currentReferenceDate
        case .sixMonths:
            currentReferenceDate = calendar.date(byAdding: .month, value: -3, to: currentReferenceDate) ?? currentReferenceDate
        case .year:
            currentReferenceDate = calendar.date(byAdding: .year, value: -1, to: currentReferenceDate) ?? currentReferenceDate
        case .custom:
            break // No navigation for custom
        }
        updateDateRange()
        refreshData()
    }
    
    func navigateForward() {
        let calendar = Calendar.current
        switch selectedPeriod {
        case .day:
            currentReferenceDate = calendar.date(byAdding: .day, value: 1, to: currentReferenceDate) ?? currentReferenceDate
        case .week:
            currentReferenceDate = calendar.date(byAdding: .weekOfYear, value: 1, to: currentReferenceDate) ?? currentReferenceDate
        case .month:
            currentReferenceDate = calendar.date(byAdding: .month, value: 1, to: currentReferenceDate) ?? currentReferenceDate
        case .sixMonths:
            currentReferenceDate = calendar.date(byAdding: .month, value: 3, to: currentReferenceDate) ?? currentReferenceDate
        case .year:
            currentReferenceDate = calendar.date(byAdding: .year, value: 1, to: currentReferenceDate) ?? currentReferenceDate
        case .custom:
            break // No navigation for custom
        }
        updateDateRange()
        refreshData()
    }
    
    // MARK: - Output Data
    @Published var netWorth: Decimal = 0
    @Published var totalIncome: Decimal = 0
    @Published var totalExpense: Decimal = 0
    @Published var savingsRate: Double = 0
    
    // For Charts
    @Published var dailyStats: [DailyStat] = []
    @Published var categoryStats: [CategoryStat] = []
    
    var isFilterActive: Bool {
        return selectedPeriod != .day || selectedWallet != nil
    }
    
    var filterDescription: String {
        let calendar = Calendar.current
        
        switch selectedPeriod {
        case .day:
            // Show full date for the day
            return startDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        case .week:
            // Show week range: "Jan 27 - Feb 2, 2026"
            let weekEnd = calendar.date(byAdding: .day, value: -1, to: endDate) ?? endDate
            return "\(startDate.formatted(.dateTime.month(.abbreviated).day())) - \(weekEnd.formatted(.dateTime.month(.abbreviated).day().year()))"
        case .month:
            // Show month and year: "February 2026"
            return startDate.formatted(.dateTime.month(.wide).year())
        case .sixMonths:
            // Show range: "Sep 2025 - Feb 2026"
            let rangeEnd = calendar.date(byAdding: .day, value: -1, to: endDate) ?? endDate
            return "\(startDate.formatted(.dateTime.month(.abbreviated).year())) - \(rangeEnd.formatted(.dateTime.month(.abbreviated).year()))"
        case .year:
            // Show year: "2026"
            return startDate.formatted(.dateTime.year())
        case .custom:
            return "\(customStartDate.formatted(date: .abbreviated, time: .omitted)) - \(customEndDate.formatted(date: .abbreviated, time: .omitted))"
        }
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
        let refDate = currentReferenceDate
        
        switch selectedPeriod {
        case .day:
            // Day view: Shows hourly data for the reference date
            grouping = .hour
            self.startDate = calendar.startOfDay(for: refDate)
            self.endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? refDate
            
        case .week:
            // Week view: Shows daily data for the week containing reference date
            grouping = .day
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: refDate)
            guard let startOfWeek = calendar.date(from: components),
                  let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) else { return }
            
            self.startDate = startOfWeek
            self.endDate = endOfWeek
            
        case .month:
            // Month view: Shows daily data for the month containing reference date
            grouping = .day
            guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: refDate)),
                  let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else { return }
             
            self.startDate = startOfMonth
            self.endDate = endOfMonth
            
        case .sixMonths:
            // 6 Months view: Shows monthly data for the last 6 months from reference date
            grouping = .month
            // Get start of the month 5 months ago (so we have 6 months total including current)
            guard let startOfCurrentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: refDate)),
                  let startOfRange = calendar.date(byAdding: .month, value: -5, to: startOfCurrentMonth),
                  let endOfRange = calendar.date(byAdding: .month, value: 1, to: startOfCurrentMonth) else { return }
            
            self.startDate = startOfRange
            self.endDate = endOfRange
            
        case .year:
            // Year view: Shows monthly data for the year containing reference date
            grouping = .month
            guard let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: refDate)),
                  let endOfYear = calendar.date(byAdding: .year, value: 1, to: startOfYear) else { return }
            
            self.startDate = startOfYear
            self.endDate = endOfYear
            
        case .custom:
            self.startDate = calendar.startOfDay(for: customStartDate)
            if let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: customEndDate) {
                self.endDate = endOfDay
            } else {
                self.endDate = customEndDate
            }
            
            // Auto-detect grouping based on range duration for Custom
            if let days = calendar.dateComponents([.day], from: startDate, to: endDate).day {
                if days <= 1 {
                    grouping = .hour
                } else if days <= 60 {
                    grouping = .day
                } else if days <= 365 {
                    grouping = .week
                } else {
                    grouping = .month
                }
            } else {
                grouping = .day
            }
        }
    }
    
    func refreshData() {
        fetchNetWorth()
        fetchTransactionsAndComputeStats()
    }
    
    private func fetchNetWorth() {
        guard let modelContext = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<Wallet>()
            let wallets = try modelContext.fetch(descriptor)
            
            var totalNW: Decimal = 0
            let targetCurrency = CurrencyManager.shared.preferredCurrencyCode
            
            let walletsToSum = selectedWallet == nil ? wallets : wallets.filter { $0.id == selectedWallet?.id }
            
            for wallet in walletsToSum {
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
            
            var rawChartData: [Date: (income: Decimal, expense: Decimal)] = [:]
            var rawExpenseCategoryData: [Category: Decimal] = [:]
            var rawIncomeCategoryData: [Category: Decimal] = [:] 
            
            let calendar = Calendar.current
            
            for txn in transactions {
                // Convert Amount
                let amount = CurrencyManager.shared.convert(amount: txn.amount, from: txn.currencyCode, to: targetCurrency)
                
                // Grouping Logic
                let chartDate: Date
                switch grouping {
                case .hour:
                    // Group by hour
                    chartDate = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: txn.date)) ?? calendar.startOfDay(for: txn.date)
                case .day:
                    chartDate = calendar.startOfDay(for: txn.date)
                case .week:
                    // Group by start of week. 
                    // Note: This relies on user's calendar preferences (e.g. Sunday vs Monday start)
                    let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: txn.date)
                    chartDate = calendar.date(from: components) ?? calendar.startOfDay(for: txn.date)
                case .month:
                    chartDate = calendar.date(from: calendar.dateComponents([.year, .month], from: txn.date)) ?? calendar.startOfDay(for: txn.date)
                case .year:
                    chartDate = calendar.date(from: calendar.dateComponents([.year], from: txn.date)) ?? calendar.startOfDay(for: txn.date)
                }
                
                if txn.type == .income {
                    inc += amount
                    
                    var current = rawChartData[chartDate] ?? (0, 0)
                    current.income += amount
                    rawChartData[chartDate] = current
                    
                    // Track income categories
                    if let cat = txn.category {
                        rawIncomeCategoryData[cat, default: 0] += amount
                    }
                    
                } else if txn.type == .expense {
                    exp += amount
                    
                    var current = rawChartData[chartDate] ?? (0, 0)
                    current.expense += amount
                    rawChartData[chartDate] = current
                    
                    // Track expense categories
                    if let cat = txn.category {
                        rawExpenseCategoryData[cat, default: 0] += amount
                    }
                }
            }
            
            self.totalIncome = inc
            self.totalExpense = exp
            
            if inc > 0 {
                let savings = inc - exp
                self.savingsRate = Double(truncating: savings as NSNumber) / Double(truncating: inc as NSNumber)
            } else {
                self.savingsRate = 0
            }
            
            self.dailyStats = rawChartData.map { (date, values) in
                DailyStat(date: date, income: values.income, expense: values.expense)
            }.sorted { $0.date < $1.date }
            
            // Use the appropriate category data based on selected transaction type
            let categoryData = selectedTransactionType == .expense ? rawExpenseCategoryData : rawIncomeCategoryData
            self.categoryStats = categoryData.map { (cat, amount) in
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
