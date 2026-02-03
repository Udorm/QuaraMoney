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
    
    @Published var transactions: [Transaction] = []
    
    private var startDate: Date = Date()
    private var endDate: Date = Date()
    
    var filterDescription: String {
        selectedPeriod.description(customStart: customStartDate, customEnd: customEndDate)
    }
    
    init(modelContext: ModelContext, wallet: Wallet) {
        self.modelContext = modelContext
        self.wallet = wallet
        updateDateRange()
        fetchTransactions()
    }
    
    private func updateDateRange() {
        let range = selectedPeriod.dateRange(customStart: customStartDate, customEnd: customEndDate)
        self.startDate = range.start
        self.endDate = range.end
    }
    
    func fetchTransactions() {
        let walletId = wallet.id
        let start = self.startDate
        let end = self.endDate
        
        // Fetch transactions for this wallet within the date range
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { txn in
                (txn.sourceWallet?.id == walletId || txn.destinationWallet?.id == walletId) &&
                txn.date >= start && txn.date < end
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        do {
            transactions = try modelContext.fetch(descriptor)
        } catch {
            #if DEBUG
            print("WalletDetail Transactions Fetch Error: \(error)")
            #endif
        }
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
