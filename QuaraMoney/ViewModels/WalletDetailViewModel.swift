import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class WalletDetailViewModel: ObservableObject {
    private var modelContext: ModelContext
    let wallet: Wallet
    
    @Published var selectedTab: TabPeriodSelection = .month(Date()) {
        didSet {
            updateDateRange()
            fetchTransactions()
        }
    }
    
    @Published var customStartDate: Date = Date() {
        didSet {
            if selectedTab == .custom { updateDateRange(); fetchTransactions() }
        }
    }
    @Published var customEndDate: Date = Date() {
        didSet {
            if selectedTab == .custom { updateDateRange(); fetchTransactions() }
        }
    }
    
    // Last 12 months
    let availableMonths: [Date]
    
    @Published var searchText: String = ""
    
    @Published var transactions: [Transaction] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    private var startDate: Date = Date()
    private var endDate: Date = Date()
    
    var filterDescription: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        
        switch selectedTab {
        case .month(let date):
            if calendar.isDate(date, equalTo: Date(), toGranularity: .month) {
                return "This Month"
            } else {
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: date)
            }
        case .custom:
            formatter.dateStyle = .medium
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        }
    }
    
    init(modelContext: ModelContext, wallet: Wallet) {
        self.modelContext = modelContext
        self.wallet = wallet
        
        // Initialize available months (last 12 months including current)
        var months: [Date] = []
        let calendar = Calendar.current
        let now = Date()
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        
        for i in 0..<12 {
            if let date = calendar.date(byAdding: .month, value: -i, to: currentMonthStart) {
                months.append(date)
            }
        }
        self.availableMonths = months.reversed()
        self.selectedTab = .month(currentMonthStart)
        
        updateDateRange()
        
        // Setup search debounce
        $searchText
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetchTransactions()
            }
            .store(in: &cancellables)
            
        // Listen for data updates
        NotificationCenter.default.publisher(for: .dataDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetchTransactions()
            }
            .store(in: &cancellables)
            
        fetchTransactions()
    }
    
    private func updateDateRange() {
        let calendar = Calendar.current
        switch selectedTab {
        case .month(let date):
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
            let end = calendar.date(byAdding: .month, value: 1, to: start)!.addingTimeInterval(-1)
            self.startDate = start
            self.endDate = end
        case .custom:
            let start = calendar.startOfDay(for: customStartDate)
            let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: customEndDate) ?? customEndDate
            self.startDate = start
            self.endDate = end
        }
    }
    
    func fetchTransactions() {
        let start = startDate
        let end = endDate
        let walletId = wallet.id
        let search = searchText
        
        let container = modelContext.container
        let rates = CurrencyManager.shared.rates
        let preferredCurrency = CurrencyManager.shared.preferredCurrencyCode
        
        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            
            let result = TransactionProcessor.fetchAndProcess(
                context: context,
                startDate: start,
                endDate: end,
                walletId: walletId,
                rates: rates,
                targetCurrency: preferredCurrency,
                searchText: search
            )
            
            await self.applyTransactions(result)
        }
    }
    
    private func applyTransactions(_ result: ProcessedTransactionDataID) {
        var resolvedTransactions: [Transaction] = []
        
        // We only need the transactions list here, flattened
        // The processor returns daily sections, so we flatten them or we could modify processor to return flat list of IDs too.
        // But since we have dailySections, let's just collect all IDs.
        // Actually, TransactionProcessor.fetchAndProcess calculates totals and groups. 
        // WalletDetailViewModel just wants the list of transactions?
        // Looking at the original code: `self.transactions = result.transactions`
        // Wait, `ProcessedTransactionData` had `.transactions`. `ProcessedTransactionDataID` DOES NOT have a flat list of transaction IDs, only sections.
        
        // Let's modify applyTransactions to flatten the sections or I should have added a flat list to ProcessedTransactionDataID.
        // Iterating sections is fine.
        
        for section in result.dailySections {
            for id in section.transactionIds {
                if let txn = self.modelContext.model(for: id) as? Transaction {
                    resolvedTransactions.append(txn)
                }
            }
        }
        
        // Sort by date descending (should already be sorted by sections, but let's ensure)
        self.transactions = resolvedTransactions.sorted { $0.date > $1.date }
    }
    
    func deleteTransaction(_ transaction: Transaction) {
        // Invalidate wallet caches before deleting
        transaction.sourceWallet?.invalidateBalanceCache()
        transaction.destinationWallet?.invalidateBalanceCache()
        
        modelContext.delete(transaction)
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            fetchTransactions()
        } catch {
            #if DEBUG
            print("Error deleting transaction: \(error)")
            #endif
        }
    }
    
    var isFilterActive: Bool {
        if case .month(let date) = selectedTab {
            return !Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month)
        }
        return true
    }
}
