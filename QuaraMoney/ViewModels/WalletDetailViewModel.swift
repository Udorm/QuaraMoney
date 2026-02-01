import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class WalletDetailViewModel: ObservableObject {
    private var modelContext: ModelContext
    let wallet: Wallet
    
    // We can reuse the same Period enum logic or define it here.
    // Defining here for encapsulation.
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
            fetchTransactions()
        }
    }
    
    @Published var customStartDate: Date = Date() {
        didSet { if selectedPeriod == .custom { fetchTransactions() } }
    }
    @Published var customEndDate: Date = Date() {
        didSet { if selectedPeriod == .custom { fetchTransactions() } }
    }
    
    @Published var transactions: [Transaction] = []
    
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
    
    init(modelContext: ModelContext, wallet: Wallet) {
        self.modelContext = modelContext
        self.wallet = wallet
        updateDateRange()
        fetchTransactions()
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
             if let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: customEndDate) {
                self.endDate = endOfDay
            } else {
                self.endDate = customEndDate
            }
        }
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
            print("WalletDetail Transactions Fetch Error: \(error)")
        }
    }
    
    func deleteTransaction(_ transaction: Transaction) {
        modelContext.delete(transaction)
        do {
            try modelContext.save()
            fetchTransactions()
        } catch {
            print("Error deleting transaction: \(error)")
        }
    }
    
    var isFilterActive: Bool {
        return selectedPeriod != .thisMonth
    }
}
