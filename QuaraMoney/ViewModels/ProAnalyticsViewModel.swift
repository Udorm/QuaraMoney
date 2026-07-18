import Foundation
import SwiftData
import SwiftUI
import Combine

/// Drives the Pro analytics dashboard. Owns period/wallet/type filters, computes the
/// previous comparable period for deltas, and offloads aggregation to
/// `ProAnalyticsProcessor` on a detached context (same pattern as `AnalysisViewModel`).
@Observable
@MainActor
final class ProAnalyticsViewModel {
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()

    /// In-flight refresh; cancelled + generation-checked so rapid filter changes
    /// can't apply stale results out of order.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0

    /// Visibility gating — see HomeViewModel.setVisible. Prevents every save in
    /// the app from re-running the full dashboard aggregation while off-screen.
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

    var selectedPeriod: AnalysisPeriod = .month {
        didSet {
            guard !isBatchingPeriodUpdate else { return }
            currentReferenceDate = Date()
            updateDateRange()
            refreshData()
        }
    }

    var customStartDate: Date = Date() {
        didSet { if !isBatchingPeriodUpdate, selectedPeriod == .custom { updateDateRange(); refreshData() } }
    }
    var customEndDate: Date = Date() {
        didSet { if !isBatchingPeriodUpdate, selectedPeriod == .custom { updateDateRange(); refreshData() } }
    }

    /// Suppresses the per-property `didSet` refreshes while `applyPeriodSelection` stages a
    /// whole period change (type + reference instance + custom bounds) in one shot.
    private var isBatchingPeriodUpdate = false

    /// Every non-period filter dimension (type, wallets, categories, amount range, exclusions).
    /// Single source of truth — the filter sheet and chip bar both mutate this.
    var filter: DashboardFilter = .default {
        didSet {
            guard filter != oldValue else { return }
            persistFilter()
            refreshData()
        }
    }

    /// Convenience read accessor used by chart cards that only care about the type.
    var selectedTransactionType: TransactionTypeFilter { filter.transactionType }

    /// The single selected wallet id when exactly one is chosen — used for drill-down configs.
    var singleSelectedWalletId: UUID? {
        filter.walletIds.count == 1 ? filter.walletIds.first : nil
    }

    // MARK: - Layout

    /// Which dashboard sections are visible and in what order. Persisted across launches.
    var layout: DashboardLayout = .default {
        didSet {
            guard layout != oldValue else { return }
            persistLayout()
        }
    }

    var currentReferenceDate: Date = Date()

    private(set) var startDate: Date = Date()
    private(set) var endDate: Date = Date()
    private(set) var prevStartDate: Date = Date()
    private(set) var prevEndDate: Date = Date()
    private(set) var grouping: TimeGrouping = .day

    // MARK: - Output

    var isLoading: Bool = false
    var result: ProAnalyticsProcessor.Result = .empty
    var hasLoadedOnce = false

    var preferredCurrency: String { CurrencyManager.shared.preferredCurrencyCode }

    var periodDescription: String {
        selectedPeriod.description(
            referenceDate: currentReferenceDate,
            customStart: customStartDate,
            customEnd: customEndDate
        )
    }

    /// Compact one-line summary of the period + the most salient active filters,
    /// reused as the drill-down sheet subtitle.
    var filterDescription: String {
        var parts: [String] = [periodDescription]
        switch filter.walletIds.count {
        case 0: break
        case 1: parts.append("analysis.pro.filter.oneWallet".localized)
        default: parts.append("analysis.pro.filter.nWallets".localized(with: filter.walletIds.count))
        }
        if !filter.categoryIds.isEmpty {
            parts.append("analysis.pro.filter.nCategories".localized(with: filter.categoryIds.count))
        }
        return parts.joined(separator: " • ")
    }

    private let layoutDefaultsKey = "proDashboardLayout.v1"
    private let filterDefaultsKey = "proDashboardFilter.v1"

    init() {
        loadLayout()
        loadFilter()
        updateDateRange()
        NotificationCenter.default.publisher(for: .dataDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleDataDidUpdate() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .currencyRatesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleDataDidUpdate() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .preferredCurrencyDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleDataDidUpdate() }
            .store(in: &cancellables)
    }

    // MARK: - Persistence

    private func persistLayout() {
        if let data = try? JSONEncoder().encode(layout) {
            UserDefaults.standard.set(data, forKey: layoutDefaultsKey)
        }
    }

    private func loadLayout() {
        guard let data = UserDefaults.standard.data(forKey: layoutDefaultsKey),
              var decoded = try? JSONDecoder().decode(DashboardLayout.self, from: data) else { return }
        decoded.reconcileWithKnownSections()
        layout = decoded
    }

    private func persistFilter() {
        if let data = try? JSONEncoder().encode(filter) {
            UserDefaults.standard.set(data, forKey: filterDefaultsKey)
        }
    }

    private func loadFilter() {
        guard let data = UserDefaults.standard.data(forKey: filterDefaultsKey),
              let decoded = try? JSONDecoder().decode(DashboardFilter.self, from: data) else { return }
        filter = decoded
    }

    /// Toggles a section's visibility from the customize sheet.
    func toggleSection(_ section: DashboardSection) {
        if layout.hidden.contains(section) {
            layout.hidden.remove(section)
        } else {
            layout.hidden.insert(section)
        }
    }

    func resetLayout() {
        layout = .default
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Navigation

    /// Applies a complete period configuration from the filter sheet at once: the period type,
    /// the specific instance (via `referenceDate`), and custom bounds. Batched so the view only
    /// recomputes and refreshes a single time.
    func applyPeriodSelection(period: AnalysisPeriod, referenceDate: Date, customStart: Date, customEnd: Date) {
        isBatchingPeriodUpdate = true
        selectedPeriod = period
        customStartDate = customStart
        customEndDate = customEnd
        currentReferenceDate = referenceDate
        isBatchingPeriodUpdate = false
        updateDateRange()
        refreshData()
    }

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

    /// Whether navigating forward would move past the current period (disable the button).
    var canNavigateForward: Bool {
        guard selectedPeriod != .custom else { return false }
        return endDate < Date()
    }

    // MARK: - Date Range

    private func updateDateRange() {
        let range = selectedPeriod.dateRange(
            referenceDate: currentReferenceDate,
            customStart: customStartDate,
            customEnd: customEndDate
        )
        startDate = range.start
        endDate = range.end

        if selectedPeriod == .custom {
            let length = endDate.timeIntervalSince(startDate)
            prevEndDate = startDate
            prevStartDate = startDate.addingTimeInterval(-length)
            grouping = AnalysisPeriod.autoDetectGrouping(start: startDate, end: endDate)
        } else {
            let prevRef = selectedPeriod.navigateBack(from: currentReferenceDate)
            let prevRange = selectedPeriod.dateRange(
                referenceDate: prevRef,
                customStart: customStartDate,
                customEnd: customEndDate
            )
            prevStartDate = prevRange.start
            prevEndDate = prevRange.end
            grouping = selectedPeriod.grouping
        }
    }

    // MARK: - Data

    func refreshData() {
        let start = startDate
        let end = endDate
        let prevStart = prevStartDate
        let prevEnd = prevEndDate
        let activeFilter = filter
        let periodGrouping = grouping
        let rates = CurrencyManager.shared.rates
        let preferredCurrency = CurrencyManager.shared.preferredCurrencyCode
        let now = Date()

        guard let container = modelContext?.container else { return }

        isLoading = true
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        refreshTask = Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let result = ProAnalyticsProcessor.process(
                context: context,
                startDate: start,
                endDate: end,
                prevStartDate: prevStart,
                prevEndDate: prevEnd,
                filter: activeFilter,
                grouping: periodGrouping,
                rates: rates,
                targetCurrency: preferredCurrency,
                now: now
            )
            guard !Task.isCancelled else { return }
            await self.apply(result, generation: generation)
        }
    }

    private func apply(_ result: ProAnalyticsProcessor.Result, generation: Int) {
        // A newer refresh superseded this one while it was in flight.
        guard generation == refreshGeneration else { return }
        self.result = result
        self.isLoading = false
        self.hasLoadedOnce = true
    }
}
