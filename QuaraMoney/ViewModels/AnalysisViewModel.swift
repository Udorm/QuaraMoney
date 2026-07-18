import Foundation
import SwiftData
import SwiftUI
import Combine

@Observable
@MainActor
class AnalysisViewModel {
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()

    /// In-flight refresh; cancelled + generation-checked so rapid filter changes
    /// can't apply stale results out of order.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0

    /// Visibility gating — see HomeViewModel.setVisible. Prevents every save in
    /// the app from re-running this screen's aggregation while it's off-screen.
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var needsRefresh = true

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible && needsRefresh {
            needsRefresh = false
            refreshData()
        }
    }

    private func handleDataDidUpdate() {
        if isVisible {
            refreshData()
        } else {
            needsRefresh = true
        }
    }
    
    // MARK: - Filters
    
    var selectedPeriod: AnalysisPeriod = .week {
        didSet {
            // Reset reference date to now when changing period
            currentReferenceDate = Date()
            updateDateRange()
            refreshData()
        }
    }
    
    var customStartDate: Date = Date() {
        didSet { if selectedPeriod == .custom { updateDateRange(); refreshData() } }
    }
    
    var customEndDate: Date = Date() {
        didSet { if selectedPeriod == .custom { updateDateRange(); refreshData() } }
    }
    
    var selectedWalletIds: Set<UUID> = [] {
        didSet { refreshData() }
    }
    
    var selectedTransactionType: TransactionTypeFilter = .expense {
        didSet { refreshData() }
    }
    
    // Reference date for navigation (scroll to change periods)
    var currentReferenceDate: Date = Date()
    
    // Internal Date Range derived from filters
    private(set) var startDate: Date = Date()
    private(set) var endDate: Date = Date()
    
    var grouping: TimeGrouping = .day
    
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
    var netWorth: Decimal = 0
    var totalIncome: Decimal = 0
    var totalExpense: Decimal = 0
    var savingsRate: Double = 0
    var isLoading = false
    var hasLoadedOnce = false
    
    // For Charts
    var dailyStats: [DailyStat] = []
    var categoryStats: [CategoryStat] = []
    
    var isFilterActive: Bool {
        return selectedPeriod != .day || !selectedWalletIds.isEmpty
    }

    var filterDescription: String {
        let periodDesc = selectedPeriod.description(
            referenceDate: currentReferenceDate,
            customStart: customStartDate,
            customEnd: customEndDate
        )
        let walletDesc: String
        if selectedWalletIds.isEmpty {
            walletDesc = "filter.allWallets".localized
        } else if selectedWalletIds.count == 1 {
            walletDesc = "filter.allWallets".localized // resolved by caller with wallet names
        } else {
            walletDesc = "analysis.pro.filter.nSelected".localized(with: selectedWalletIds.count)
        }
        return "\(periodDesc) • \(walletDesc)"
    }
    
    init() {
        updateDateRange()
        
        // Listen for data updates (e.g., wallet archive/unarchive)
        NotificationCenter.default.publisher(for: .dataDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleDataDidUpdate()
            }
            .store(in: &self.cancellables)
        NotificationCenter.default.publisher(for: .currencyRatesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleDataDidUpdate()
            }
            .store(in: &self.cancellables)
        NotificationCenter.default.publisher(for: .preferredCurrencyDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleDataDidUpdate()
            }
            .store(in: &self.cancellables)
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
        // Capture values for background task
        let start = self.startDate
        let end = self.endDate
        let walletIds = selectedWalletIds
        let periodGrouping = self.grouping
        let method = selectedTransactionType // "expense" or "income"

        let container = modelContext?.container
        let rates = CurrencyManager.shared.rates
        let preferredCurrency = CurrencyManager.shared.preferredCurrencyCode

        guard let container = container else { return }

        isLoading = true
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        refreshTask = Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)

            async let nw = Self.computeNetWorth(container: container, walletIds: walletIds, rates: rates, targetCurrency: preferredCurrency)

            let result = AnalysisDataProcessor.processTransactions(
                context: context,
                startDate: start,
                endDate: end,
                walletIds: walletIds,
                grouping: periodGrouping,
                transactionType: method,
                rates: rates,
                targetCurrency: preferredCurrency
            )

            let finalNW = await nw
            guard !Task.isCancelled else { return }
            await self.applyAnalysisResult(result, netWorth: finalNW, generation: generation)
        }
    }

    private func applyAnalysisResult(_ result: AnalysisDataProcessor.AnalysisResult, netWorth: Decimal, generation: Int) {
        // A newer refresh superseded this one while it was in flight.
        guard generation == refreshGeneration else { return }
        self.netWorth = netWorth
        self.totalIncome = result.totalIncome
        self.totalExpense = result.totalExpense
        self.savingsRate = result.savingsRate
        self.isLoading = false
        self.hasLoadedOnce = true
        
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
    
    nonisolated private static func computeNetWorth(container: ModelContainer, walletIds: Set<UUID>, rates: [String: Double], targetCurrency: String) -> Decimal {
        let context = ModelContext(container)
        do {
            let descriptor = FetchDescriptor<Wallet>(predicate: #Predicate { $0.deletedAt == nil })
            let wallets = try context.fetch(descriptor)

            var totalNW: Decimal = 0
            let walletsToSum = walletIds.isEmpty ? wallets : wallets.filter { walletIds.contains($0.id) }

            for wallet in walletsToSum {
                let balance = wallet.balance
                let converted = Self.convert(amount: balance, from: wallet.currencyCode, to: targetCurrency, rates: rates)
                totalNW += converted
            }

            return totalNW

        } catch {
            return 0
        }
    }
    
    nonisolated private static func convert(amount: Decimal, from source: String, to target: String, rates: [String: Double]) -> Decimal {
        CurrencyManager.convert(amount: amount, from: source, to: target, rates: rates)
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
