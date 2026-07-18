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

    var selectedWalletIds: Set<UUID> = [] {
        didSet { refreshData() }
    }

    var sortOption: TransactionSortOption = .newestFirst {
        didSet { refreshData() }
    }

    var sortedTransactions: [Transaction] = []

    @ObservationIgnored private var startDate: Date = Date()
    @ObservationIgnored private var endDate: Date = Date()

    /// In-flight refresh. Each refresh cancels its predecessor and the apply is
    /// generation-checked, so rapid filter changes can never land stale results
    /// out of order (two detached fetches finish in nondeterministic order).
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0

    /// Visibility gating: the tab views stay alive in the TabView, so without
    /// this every `.dataDidUpdate` (i.e. every save anywhere in the app) would
    /// re-run this screen's full fetch pipeline even while it's off-screen.
    /// Starts `needsRefresh` so the first appearance performs the initial load.
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var needsRefresh = true

    /// Called from the view's `onAppear`/`onDisappear`. Refreshes on appear
    /// only when a data change arrived while hidden (or on first load).
    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible && needsRefresh {
            needsRefresh = false
            refreshData()
        }
    }

    /// Route for `.dataDidUpdate`: refresh now if on screen, defer otherwise.
    private func handleDataDidUpdate() {
        if isVisible {
            refreshData()
        } else {
            needsRefresh = true
        }
    }

    var currentStartDate: Date { startDate }
    var currentEndDate: Date { endDate }

    var filterDescription: String {
        if selectedWalletIds.isEmpty { return "filter.allWallets".localized }
        if selectedWalletIds.count == 1 { return "filter.allWallets".localized } // fallback; callers should resolve names
        return "analysis.pro.filter.nSelected".localized(with: selectedWalletIds.count)
    }

    var incomeTotal: Decimal = 0
    var expenseTotal: Decimal = 0
    var dailySections: [DailyTransactionSection] = []
    var previousPeriodCumulative: [Decimal] = []

    /// Whether any (non-deleted) transaction exists at all — drives the
    /// first-run empty state vs. the empty-period one.
    var hasAnyTransactions: Bool = true
    /// False until the first fetch lands, so empty states don't flash on launch.
    var hasLoadedOnce: Bool = false

    /// Token for the transient Undo toast after a swipe-delete. Holding the
    /// model is safe: soft-delete keeps the row (tombstone) alive.
    struct DeletedTransactionToken: Identifiable {
        let id: UUID
        let transaction: Transaction
    }
    var recentlyDeleted: DeletedTransactionToken?

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
                self?.handleDataDidUpdate()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .currencyRatesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleDataDidUpdate()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .preferredCurrencyDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleDataDidUpdate()
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
        let walletIds = selectedWalletIds
        let search = searchText
        let currentSortOption = sortOption

        let container = modelContext.container
        let rates = CurrencyManager.shared.rates
        let preferredCurrency = CurrencyManager.shared.preferredCurrencyCode

        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        refreshTask = Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)

            let dataID = TransactionProcessor.fetchAndProcess(
                context: context,
                startDate: start,
                endDate: end,
                walletIds: walletIds,
                rates: rates,
                targetCurrency: preferredCurrency,
                searchText: search,
                sortOption: currentSortOption,
                calculateReferenceLine: true
            )

            // Cheap count query so the view can distinguish "brand new user"
            // from "nothing in this period / no search matches".
            let anyDescriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.deletedAt == nil }
            )
            let anyExist = ((try? context.fetchCount(anyDescriptor)) ?? 0) > 0

            guard !Task.isCancelled else { return }
            await self.applyData(dataID, hasAnyTransactions: anyExist, generation: generation)
        }
    }

    private func applyData(_ dataID: ProcessedTransactionDataID, hasAnyTransactions: Bool, generation: Int) {
        // A newer refresh superseded this one while it was in flight.
        guard generation == refreshGeneration else { return }
        self.hasAnyTransactions = hasAnyTransactions
        self.hasLoadedOnce = true
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

    /// Set when a debt-anchor deletion is blocked; drives a redirect alert.
    var blockedDeletionMessage: String?

    func deleteTransaction(_ transaction: Transaction) {
        // A debt's sole advance can't be deleted here — it would orphan the
        // debt. Send the user to the Debts screen to delete the whole record.
        if transaction.isDebtAnchor {
            blockedDeletionMessage = "debt.cannotDeleteAnchor".localized(with: transaction.debt?.personName ?? "")
            HapticManager.shared.warning()
            return
        }

        // Soft-delete (tombstone) so the deletion replicates to other devices.
        SoftDeleteService.deleteTransaction(transaction)
        do {
            try modelContext.save()
            // Offer a transient Undo — the tombstone makes restore trivial.
            recentlyDeleted = DeletedTransactionToken(id: transaction.id, transaction: transaction)
            // The .dataDidUpdate handler performs the refresh (single channel —
            // no direct refreshData() call, which used to double-fetch).
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
        } catch {
            #if DEBUG
            print("Error deleting transaction: \(error)")
            #endif
        }
    }

    /// Undoes a just-performed swipe-delete by clearing the soft-delete tombstone.
    func undoDelete(_ token: DeletedTransactionToken) {
        SoftDeleteService.restoreTransaction(token.transaction)
        do {
            try modelContext.save()
            HapticManager.shared.selection()
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
        } catch {
            #if DEBUG
            print("Error restoring transaction: \(error)")
            #endif
        }
    }

    var isFilterActive: Bool {
        if case .month(let date) = selectedTab {
            return !Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month) || !selectedWalletIds.isEmpty
        }
        return true // Custom is active
    }

    func resetFilters() {
        let currentMonthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
        selectedTab = .month(currentMonthStart) // Back to today/this month
        selectedWalletIds = []
        searchText = ""
    }
}
