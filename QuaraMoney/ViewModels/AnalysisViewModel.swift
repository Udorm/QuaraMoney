import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class AnalysisViewModel: ObservableObject {
    private var modelContext: ModelContext?
    
    // MARK: - Filters
    
    @Published var selectedPeriod: AnalysisPeriod = .day {
        didSet {
            // Reset reference date to now when changing period
            currentReferenceDate = Date()
            updateDateRange()
            refreshData()
        }
    }
    
    @Published var customStartDate: Date = Date() {
        didSet { if selectedPeriod == .custom { updateDateRange(); refreshData() } }
    }
    
    @Published var customEndDate: Date = Date() {
        didSet { if selectedPeriod == .custom { updateDateRange(); refreshData() } }
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
    
    @Published var grouping: TimeGrouping = .day
    
    // MARK: - Navigation
    
    func navigateBack() {
        guard selectedPeriod != .custom else { return }
        currentReferenceDate = selectedPeriod.navigateBack(from: currentReferenceDate)
        updateDateRange()
        refreshData()
    }
    
    func navigateForward() {
        guard selectedPeriod != .custom else { return }
        currentReferenceDate = selectedPeriod.navigateForward(from: currentReferenceDate)
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
        selectedPeriod.description(
            referenceDate: currentReferenceDate,
            customStart: customStartDate,
            customEnd: customEndDate
        )
    }
    
    init() {
        updateDateRange()
    }
    
    /// Configure the model context - call this on view appear
    /// Using configure pattern to handle SwiftData context lifecycle safely
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Logic
    
    private func updateDateRange() {
        let range = selectedPeriod.dateRange(
            referenceDate: currentReferenceDate,
            customStart: customStartDate,
            customEnd: customEndDate
        )
        self.startDate = range.start
        self.endDate = range.end
        
        // Update grouping
        if selectedPeriod == .custom {
            self.grouping = AnalysisPeriod.autoDetectGrouping(start: startDate, end: endDate)
        } else {
            self.grouping = selectedPeriod.grouping
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
            #if DEBUG
            print("Error fetching wallets for Net Worth: \(error)")
            #endif
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
            #if DEBUG
            print("Error fetching transactions for Analysis: \(error)")
            #endif
        }
    }
}

// MARK: - Stats with Stable IDs for Chart Performance

struct DailyStat: Identifiable {
    var id: Date { date }
    let date: Date
    let income: Decimal
    let expense: Decimal
}

struct CategoryStat: Identifiable {
    var id: UUID { category.id }
    let category: Category
    let amount: Decimal
    let colorHex: String
}
