import Foundation
import SwiftData
import SwiftUI
import Combine

@Observable
@MainActor
class HomeViewModel {
    @ObservationIgnored private var modelContext: ModelContext
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private let searchSubject = PassthroughSubject<String, Never>()

    var selectedTab: TabPeriodSelection = .month(Date()) {
        didSet {
            updateDateRange()
            refreshData()
        }
    }

    // Last 12 months
    let availableMonths: [Date]

    var selectedPeriod: FilterPeriod = .thisMonth

    var customStartDate: Date = Date() {
        didSet {
            if selectedTab == .custom {
                updateDateRange()
                refreshData()
            }
        }
    }
    var customEndDate: Date = Date() {
        didSet {
            if selectedTab == .custom {
                updateDateRange()
                refreshData()
            }
        }
    }

    var searchText: String = "" {
        didSet { searchSubject.send(searchText) }
    }

    var selectedWallet: Wallet? {
        didSet { refreshData() }
    }

    var sortOption: TransactionSortOption = .newestFirst {
        didSet { refreshData() }
    }

    var sortedTransactions: [Transaction] = []

    @ObservationIgnored private var startDate: Date = Date()
    @ObservationIgnored private var endDate: Date = Date()

    var currentStartDate: Date { startDate }
    var currentEndDate: Date { endDate }

    var filterDescription: String {
        let walletDesc = selectedWallet?.name ?? "filter.allWallets".localized
        return walletDesc
    }

    var incomeTotal: Decimal = 0
    var expenseTotal: Decimal = 0
    var dailySections: [DailyTransactionSection] = []
    var previousPeriodCumulative: [Decimal] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext

        // Initialize available months (last 12 months including current)
        var months: [Date] = []
        let calendar = Calendar.current
        let now = Date()
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

        for i in 0..<12 {
            if let date = calendar.date(byAdding: .month, value: -i, to: currentMonthStart) {
                months.append(date)
            }
        }
        self.availableMonths = months.reversed()
        self.selectedTab = .month(currentMonthStart)

        updateDateRange()

        // Listen for data resets using Combine for automatic cleanup
        NotificationCenter.default.publisher(for: .dataDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshData()
            }
            .store(in: &cancellables)

        // Setup search debounce
        searchSubject
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshData()
            }
            .store(in: &cancellables)
    }

    private func updateDateRange() {
        let calendar = Calendar.current

        if case .month(let date) = selectedTab {
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
            let end = (calendar.date(byAdding: .month, value: 1, to: start) ?? start).addingTimeInterval(-1)
            self.startDate = start
            self.endDate = end
        } else {
            let start = calendar.startOfDay(for: customStartDate)
            let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: customEndDate) ?? customEndDate
            self.startDate = start
            self.endDate = end
        }
    }

    func refreshData() {
        let start = startDate
        let end = endDate
        let walletId = selectedWallet?.id
        let search = searchText
        let currentSortOption = sortOption

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
                searchText: search,
                sortOption: currentSortOption,
                calculateReferenceLine: true
            )

            await self.applyData(dataID)
        }
    }

    private func applyData(_ dataID: ProcessedTransactionDataID) {
        self.incomeTotal = dataID.incomeTotal
        self.expenseTotal = dataID.expenseTotal
        self.previousPeriodCumulative = dataID.previousPeriodCumulative

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

        var resolvedTransactions: [Transaction] = []
        for id in dataID.sortedTransactionIds {
            if let txn = self.modelContext.model(for: id) as? Transaction {
                resolvedTransactions.append(txn)
            }
        }
        self.sortedTransactions = resolvedTransactions
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
        if case .month(let date) = selectedTab {
            return !Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month) || selectedWallet != nil
        }
        return true // Custom is active
    }

    func resetFilters() {
        let currentMonthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
        selectedTab = .month(currentMonthStart) // Back to today/this month
        selectedWallet = nil
        searchText = ""
    }
}
