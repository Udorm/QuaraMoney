import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    private var modelContext: ModelContext
    private var cancellables = Set<AnyCancellable>()
    
    @Published var selectedPeriod: FilterPeriod = .thisMonth {
        didSet {
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
    
    @Published var searchText: String = ""
    
    @Published var selectedWallet: Wallet? {
        didSet { refreshData() }
    }
    
    private var startDate: Date = Date()
    private var endDate: Date = Date()
    
    var filterDescription: String {
        let periodDesc = selectedPeriod.description(customStart: customStartDate, customEnd: customEndDate)
        let walletDesc = selectedWallet?.name ?? "filter.allWallets".localized
        return "\(periodDesc) • \(walletDesc)"
    }
    
    @Published var incomeTotal: Decimal = 0
    @Published var expenseTotal: Decimal = 0
    @Published var dailySections: [DailyTransactionSection] = []
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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
            .dropFirst() // Skip initial value
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshData()
            }
            .store(in: &cancellables)
    }
    
    // Clear current data immediately then refresh
    private func resetAndRefresh() {
        self.dailySections = []
        self.incomeTotal = 0
        self.expenseTotal = 0
        refreshData()
    }
    
    private func updateDateRange() {
        let range = selectedPeriod.dateRange(customStart: customStartDate, customEnd: customEndDate)
        self.startDate = range.start
        self.endDate = range.end
    }
    
    func refreshData() {
        // Single fetch + process instead of duplicate fetchSummary() + fetchDailyTransactions()
        let data = TransactionProcessor.fetchAndProcess(
            context: modelContext,
            startDate: startDate,
            endDate: endDate,
            walletId: selectedWallet?.id,
            searchText: searchText
        )
        
        self.incomeTotal = data.incomeTotal
        self.expenseTotal = data.expenseTotal
        self.dailySections = data.dailySections
    }
    
    func deleteTransaction(_ transaction: Transaction) {
        // Invalidate wallet caches before deleting
        transaction.sourceWallet?.invalidateBalanceCache()
        transaction.destinationWallet?.invalidateBalanceCache()
        
        modelContext.delete(transaction)
        do {
            try modelContext.save()
            // Force refresh immediately to update UI
            refreshData()
        } catch {
            #if DEBUG
            print("Error deleting transaction: \(error)")
            #endif
        }
    }
    
    var isFilterActive: Bool {
        return selectedPeriod != .thisMonth || selectedWallet != nil
    }
    
    func resetFilters() {
        selectedPeriod = .thisMonth
        selectedWallet = nil
        searchText = ""
    }
}
