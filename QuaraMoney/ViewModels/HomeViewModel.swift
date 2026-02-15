import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    private var modelContext: ModelContext
    private var cancellables = Set<AnyCancellable>()
    
    // New Month Selection Logic
    @Published var selectedMonth: Date = Date() {
        didSet {
            updateDateRange()
            refreshData()
        }
    }
    
    // Last 12 months
    let availableMonths: [Date]
    
    // Keep FilterPeriod for now if needed, but we'll likely ignore it for date range
    // or maybe we just won't show the picker in UI.
    @Published var selectedPeriod: FilterPeriod = .thisMonth // Default to thisMonth
    
    @Published var customStartDate: Date = Date()
    @Published var customEndDate: Date = Date()
    
    @Published var searchText: String = ""
    
    @Published var selectedWallet: Wallet? {
        didSet { refreshData() }
    }
    
    private var startDate: Date = Date()
    private var endDate: Date = Date()
    
    var filterDescription: String {
        // filterDescription used to show "This Month • All Wallets"
        // Now the month is obvious from the tab bar.
        // Maybe just show Wallet filter status?
        // User said "reports... correspond to the month user selects".
        // The header in the list was "This Month • All Wallets".
        // If the tab bar is above, maybe we don't need the period part in the description.
        // But let's keep it simple.
        let walletDesc = selectedWallet?.name ?? "filter.allWallets".localized
        return walletDesc
        // If we want to show the date range:
        // let dateDesc = selectedMonth.formatted(.dateTime.month().year())
        // return "\(dateDesc) • \(walletDesc)"
    }
    
    @Published var incomeTotal: Decimal = 0
    @Published var expenseTotal: Decimal = 0
    @Published var dailySections: [DailyTransactionSection] = []
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        // Initialize available months (last 12 months including current)
        var months: [Date] = []
        let calendar = Calendar.current
        let now = Date()
        // Current month start
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        
        for i in 0..<12 {
            if let date = calendar.date(byAdding: .month, value: -i, to: currentMonthStart) {
                months.append(date)
            }
        }
        // Reverse so recent is at the end? User said: "recent month being on the right".
        // If we use standard LTR implementation, right is end of list.
        // So [Month-11, Month-10, ..., ThisMonth]
        self.availableMonths = months.reversed()
        self.selectedMonth = currentMonthStart
        
        updateDateRange()
        
        // Listen for data resets using Combine for automatic cleanup
        NotificationCenter.default.publisher(for: .dataDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resetAndRefresh()
            }
            .store(in: &cancellables)
            
        // Setup search debounce
        $searchText
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshData()
            }
            .store(in: &cancellables)
    }
    
    // Refresh data without clearing (to avoid flash)
    private func resetAndRefresh() {
        refreshData()
    }
    
    private func updateDateRange() {
        // Always use selectedMonth for the range now
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!.addingTimeInterval(-1)
        
        self.startDate = start
        self.endDate = end
    }
    
    func refreshData() {
        let start = startDate
        let end = endDate
        let walletId = selectedWallet?.id
        let search = searchText
        
        let container = modelContext.container
        let rates = CurrencyManager.shared.rates
        let preferredCurrency = CurrencyManager.shared.preferredCurrencyCode
        
        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            
            let dataID = TransactionProcessor.fetchAndProcess(
                context: context,
                startDate: start,
                endDate: end,
                walletId: walletId,
                rates: rates,
                targetCurrency: preferredCurrency,
                searchText: search
            )
            
            await self.applyData(dataID)
        }
    }
    
    private func applyData(_ dataID: ProcessedTransactionDataID) {
        self.incomeTotal = dataID.incomeTotal
        self.expenseTotal = dataID.expenseTotal
        
        // Resolve IDs to Objects on Main Actor
        var resolvedSections: [DailyTransactionSection] = []
        
        for section in dataID.dailySections {
            var transactions: [Transaction] = []
            for id in section.transactionIds {
                if let txn = self.modelContext.model(for: id) as? Transaction {
                    transactions.append(txn)
                }
            }
            
            if !transactions.isEmpty {
                resolvedSections.append(DailyTransactionSection(
                    date: section.date,
                    transactions: transactions,
                    dailyTotal: section.dailyTotal
                ))
            }
        }
        
        self.dailySections = resolvedSections
    }
    
    func deleteTransaction(_ transaction: Transaction) {
        // Invalidate wallet caches before deleting
        transaction.sourceWallet?.invalidateBalanceCache()
        transaction.destinationWallet?.invalidateBalanceCache()
        
        modelContext.delete(transaction)
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            // Force refresh immediately to update UI
            refreshData()
        } catch {
            #if DEBUG
            print("Error deleting transaction: \(error)")
            #endif
        }
    }
    
    var isFilterActive: Bool {
        // Filter is active if not the current month OR custom wallet selected?
        // User said: "remove date filter from context menu"
        // So checking if 'selectedPeriod' is default might be irrelevant for date.
        // But for UI state (e.g. clear filters), maybe we reset to this month?
        return !Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month) || selectedWallet != nil
    }
    
    func resetFilters() {
        selectedMonth = Date() // Back to today/this month
        selectedWallet = nil
        searchText = ""
    }
}
