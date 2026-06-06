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

    // MARK: - Filters

    var selectedPeriod: AnalysisPeriod = .month {
        didSet {
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

    var selectedWallet: Wallet? {
        didSet { refreshData() }
    }

    var selectedTransactionType: TransactionTypeFilter = .expense {
        didSet { refreshData() }
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

    var preferredCurrency: String { CurrencyManager.shared.preferredCurrencyCode }

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
        NotificationCenter.default.publisher(for: .dataDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshData() }
            .store(in: &cancellables)
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

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
        let walletId = selectedWallet?.id
        let periodGrouping = grouping
        let type = selectedTransactionType
        let rates = CurrencyManager.shared.rates
        let preferredCurrency = CurrencyManager.shared.preferredCurrencyCode
        let now = Date()

        guard let container = modelContext?.container else { return }

        isLoading = true
        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let result = ProAnalyticsProcessor.process(
                context: context,
                startDate: start,
                endDate: end,
                prevStartDate: prevStart,
                prevEndDate: prevEnd,
                walletId: walletId,
                grouping: periodGrouping,
                transactionType: type,
                rates: rates,
                targetCurrency: preferredCurrency,
                now: now
            )
            await self.apply(result)
        }
    }

    private func apply(_ result: ProAnalyticsProcessor.Result) {
        self.result = result
        self.isLoading = false
    }
}
