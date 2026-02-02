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
        // Single fetch + process instead of duplicate fetchSummary() + fetchDailyTransactions()
        let data = TransactionProcessor.fetchAndProcess(
            context: modelContext,
            startDate: startDate,
            endDate: endDate,
            walletId: selectedWallet?.id
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
