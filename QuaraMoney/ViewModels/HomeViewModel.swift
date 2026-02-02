import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    private var modelContext: ModelContext
    
    enum Period: String, CaseIterable, Identifiable {
        case thisMonth = "This Month"
        case lastMonth = "Last Month"
        case thisYear = "This Year"
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
    
    private var startDate: Date = Date()
    private var endDate: Date = Date()
    
    var filterDescription: String {
        switch selectedPeriod {
        case .custom:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        default:
            return selectedPeriod.rawValue
        }
    }
    
    @Published var incomeTotal: Decimal = 0
    @Published var expenseTotal: Decimal = 0
    @Published var dailySections: [DailyTransactionSection] = []
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        updateDateRange()
        
        // Listen for data resets (e.g. from Settings)
        NotificationCenter.default.addObserver(
            forName: .dataDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resetAndRefresh()
        }
    }
    
    // Clear current data immediately then refresh
    private func resetAndRefresh() {
        self.dailySections = []
        self.incomeTotal = 0
        self.expenseTotal = 0
        // Small delay to ensure context is settled? Or immediate?
        // Immediate is safer to clear invalid objects from UI.
        // Then assume context is fresh.
        refreshData()
    }
    
    private func updateDateRange() {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedPeriod {
        case .thisMonth:
            guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return }
            self.startDate = start
            self.endDate = end
        case .lastMonth:
            guard let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                  let start = calendar.date(byAdding: .month, value: -1, to: thisMonthStart),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return }
            self.startDate = start
            self.endDate = end
        case .thisYear:
            guard let start = calendar.date(from: calendar.dateComponents([.year], from: now)),
                  let end = calendar.date(byAdding: .year, value: 1, to: start) else { return }
            self.startDate = start
            self.endDate = end
        case .custom:
            self.startDate = calendar.startOfDay(for: customStartDate)
            // End date should be end of the selected day
             if let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: customEndDate) {
                self.endDate = endOfDay
            } else {
                self.endDate = customEndDate
            }
        }
    }
    
    func refreshData() {
        fetchSummary()
        fetchDailyTransactions()
    }
    
    private func fetchSummary() {
        let start = self.startDate
        let end = self.endDate
        let walletId = selectedWallet?.id
        
        // Fetch all transactions for the selected period
        // Note: Predicate construction with optional values needs care.
        // We will fetch based on date first, then filter in memory if needed or construct predicate dynamically.
        // SwiftData predicates are strict.
        
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
        
        
        do {
            let transactions = try modelContext.fetch(descriptor)
            var inc: Decimal = 0
            var exp: Decimal = 0
            
            let targetCurrency = CurrencyManager.shared.preferredCurrencyCode
            
            for txn in transactions {
                // Determine transaction currency (default to wallet's if not stored, though schema says we store it now?)
                // Transaction struct has 'currencyCode'.
                // If it doesn't, we fallback to wallet or USD.
                // Assuming txn.currencyCode is populated correctly.
                
                let amountInTarget = CurrencyManager.shared.convert(
                    amount: txn.amount,
                    from: txn.currencyCode, 
                    to: targetCurrency
                )
                
                if txn.type == .income {
                    inc += amountInTarget
                } else if txn.type == .expense {
                    exp += amountInTarget
                }
            }
            
            self.incomeTotal = inc
            self.expenseTotal = exp
        } catch {
            print("Home Summary Fetch Error: \(error)")
        }
    }
    
    private func fetchDailyTransactions() {
        let start = self.startDate
        let end = self.endDate
        let walletId = selectedWallet?.id
        
        let descriptor: FetchDescriptor<Transaction>
        
        if let walletId = walletId {
             descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { txn in
                    txn.date >= start && txn.date < end &&
                    (txn.sourceWallet?.id == walletId || txn.destinationWallet?.id == walletId)
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { txn in
                    txn.date >= start && txn.date < end
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        }
        
        do {
            let transactions = try modelContext.fetch(descriptor)
            let targetCurrency = CurrencyManager.shared.preferredCurrencyCode
            
            // Group by Day
            let grouped = Dictionary(grouping: transactions) { txn -> Date in
                Calendar.current.startOfDay(for: txn.date)
            }
            
            let sortedKeys = grouped.keys.sorted(by: >)
            
            self.dailySections = sortedKeys.map { date in
                let txns = grouped[date] ?? []
                // Calculate daily total (Expenses negative? or just Sum?)
                // User asked for "Summary of each day how much did the money flow".
                // Flow = Income - Expense? Or just Expense?
                // Let's do Net Flow.
                let dailyFlow = txns.reduce(0 as Decimal) { result, txn in
                    let amountInTarget = CurrencyManager.shared.convert(
                        amount: txn.amount,
                        from: txn.currencyCode,
                        to: targetCurrency
                    )
                    
                    if txn.type == .income { return result + amountInTarget }
                    if txn.type == .expense { return result - amountInTarget }
                    return result
                }
                
                return DailyTransactionSection(date: date, transactions: txns, dailyTotal: dailyFlow)
            }
            
        } catch {
            print("Home Transactions Fetch Error: \(error)")
        }
    }
    
    func deleteTransaction(_ transaction: Transaction) {
        modelContext.delete(transaction)
        do {
            try modelContext.save()
            // Force refresh immediately to update UI
            refreshData()
        } catch {
            print("Error deleting transaction: \(error)")
        }
    }
    
    var isFilterActive: Bool {
        return selectedPeriod != .thisMonth || selectedWallet != nil
    }
    
    func resetFilters() {
        selectedPeriod = .thisMonth
        selectedWallet = nil
    }
}

struct DailyTransactionSection: Identifiable {
    let id = UUID()
    let date: Date
    let transactions: [Transaction]
    let dailyTotal: Decimal
}
