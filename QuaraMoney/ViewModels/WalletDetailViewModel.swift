import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class WalletDetailViewModel: ObservableObject {
    private var modelContext: ModelContext
    let wallet: Wallet
    
    @Published var selectedPeriod: FilterPeriod = .thisMonth {
        didSet {
            updateDateRange()
            fetchTransactions()
        }
    }
    
    @Published var customStartDate: Date = Date() {
        didSet { if selectedPeriod == .custom { updateDateRange(); fetchTransactions() } }
    }
    @Published var customEndDate: Date = Date() {
        didSet { if selectedPeriod == .custom { updateDateRange(); fetchTransactions() } }
    }
    
    @Published var searchText: String = ""
    
    @Published var transactions: [Transaction] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    private var startDate: Date = Date()
    private var endDate: Date = Date()
    
    var filterDescription: String {
        selectedPeriod.description(customStart: customStartDate, customEnd: customEndDate)
    }
    
    init(modelContext: ModelContext, wallet: Wallet) {
        self.modelContext = modelContext
        self.wallet = wallet
        updateDateRange()
        
        // Setup search debounce
        $searchText
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetchTransactions()
            }
            .store(in: &cancellables)
            
        fetchTransactions()
    }
    
    private func updateDateRange() {
        let range = selectedPeriod.dateRange(customStart: customStartDate, customEnd: customEndDate)
        self.startDate = range.start
        self.endDate = range.end
    }
    
    func fetchTransactions() {
        let result = TransactionProcessor.fetchAndProcess(
            context: modelContext,
            startDate: startDate,
            endDate: endDate,
            walletId: wallet.id,
            searchText: searchText
        )
        self.transactions = result.transactions
    }
    
    func deleteTransaction(_ transaction: Transaction) {
        // Invalidate wallet caches before deleting
        transaction.sourceWallet?.invalidateBalanceCache()
        transaction.destinationWallet?.invalidateBalanceCache()
        
        modelContext.delete(transaction)
        do {
            try modelContext.save()
            fetchTransactions()
        } catch {
            #if DEBUG
            print("Error deleting transaction: \(error)")
            #endif
        }
    }
    
    var isFilterActive: Bool {
        return selectedPeriod != .thisMonth
    }
}
