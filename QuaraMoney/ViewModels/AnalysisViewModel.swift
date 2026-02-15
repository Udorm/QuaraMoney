import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class AnalysisViewModel: ObservableObject {
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Filters
    
    @Published var selectedPeriod: AnalysisPeriod = .week {
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
        let periodDesc = selectedPeriod.description(
            referenceDate: currentReferenceDate,
            customStart: customStartDate,
            customEnd: customEndDate
        )
        let walletDesc = selectedWallet?.name ?? "filter.allWallets".localized
        return "\(periodDesc) • \(walletDesc)"
    }
    
    init() {
        updateDateRange()
        
        // Listen for data updates (e.g., wallet archive/unarchive)
        NotificationCenter.default.publisher(for: .dataDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshData()
            }
            .store(in: &cancellables)
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
        
        // Capture values for background task
        let start = self.startDate
        let end = self.endDate
        let walletId = selectedWallet?.id
        let periodGrouping = self.grouping
        let method = selectedTransactionType // "expense" or "income"
        
        let container = modelContext?.container
        let rates = CurrencyManager.shared.rates
        let preferredCurrency = CurrencyManager.shared.preferredCurrencyCode
        
        guard let container = container else { return }
        
        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            
            let result = AnalysisDataProcessor.processTransactions(
                context: context,
                startDate: start,
                endDate: end,
                walletId: walletId,
                grouping: periodGrouping,
                transactionType: method,
                rates: rates,
                targetCurrency: preferredCurrency
            )
            
            await self.applyAnalysisResult(result)
        }
    }
    
    private func applyAnalysisResult(_ result: AnalysisDataProcessor.AnalysisResult) {
        self.totalIncome = result.totalIncome
        self.totalExpense = result.totalExpense
        self.savingsRate = result.savingsRate
        
        // Map to UI models
        self.dailyStats = result.dailyStats.map { data in
            DailyStat(date: data.date, income: data.income, expense: data.expense)
        }
        
        self.categoryStats = result.categoryStats.map { data in
            CategoryStat(
                id: data.id,
                name: data.name,
                icon: data.icon,
                colorHex: data.colorHex,
                amount: data.amount
            )
        }
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
    
    // Removed old fetchTransactionsAndComputeStats as it is replaced by refreshData + background processor
}

// MARK: - Stats with Stable IDs for Chart Performance

struct DailyStat: Identifiable {
    var id: Date { date }
    let date: Date
    let income: Decimal
    let expense: Decimal
}

struct CategoryStat: Identifiable {
    let id: UUID
    let name: String
    let icon: String // SF Symbol name
    let colorHex: String
    let amount: Decimal
}

enum TransactionTypeFilter: String, CaseIterable, Sendable {
    case expense = "Expense"
    case income = "Income"
}
