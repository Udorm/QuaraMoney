import Foundation
import SwiftData
import Combine

/// Per-wallet display figures computed off the main thread.
struct WalletFigures: Sendable {
    let balance: Decimal
    let series: [Wallet.BalancePoint]
}

/// Computes wallet balances, per-wallet 30-day series, and the combined
/// net-worth series on a **background** `ModelContext`, publishing plain values
/// the wallet list reads synchronously.
///
/// Why: `Wallet.balance`/`dailyBalanceSeries` walk the wallet's full
/// relationship arrays — faulting every transaction the wallet ever had.
/// Previously that ran on the main actor in every row's `onAppear` and was
/// re-triggered for *all* wallets on every `.dataDidUpdate`. With years of data
/// that is the single biggest main-thread hitch in the app. Here the identical
/// per-transaction semantics run on a detached context instead, and the rows
/// become O(1) dictionary reads.
@MainActor
@Observable
final class WalletBalanceStore {
    private(set) var figures: [UUID: WalletFigures] = [:]
    private(set) var netWorthSeries: [Wallet.BalancePoint] = []
    private(set) var netWorthTotal: Decimal = 0
    /// False until the first computation lands, so views can render a quiet
    /// placeholder instead of flashing $0.
    private(set) var hasLoaded = false

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var needsRefresh = true

    private static let historyDays = 30

    init() {
        NotificationCenter.default.publisher(for: .dataDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleDataDidUpdate() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .preferredCurrencyDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleDataDidUpdate() }
            .store(in: &cancellables)
    }

    func configure(container: ModelContainer) {
        self.container = container
    }

    /// Visibility gating (same pattern as the tab view models): recompute on
    /// `.dataDidUpdate` only while the wallet list is on screen; defer otherwise.
    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible && needsRefresh {
            needsRefresh = false
            refresh()
        }
    }

    private func handleDataDidUpdate() {
        if isVisible {
            refresh()
        } else {
            needsRefresh = true
        }
    }

    func refresh() {
        guard let container else { return }
        let preferredCurrency = CurrencyManager.shared.preferredCurrencyCode
        let rates = CurrencyManager.shared.rates

        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        refreshTask = Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let result = Self.compute(
                context: context,
                days: Self.historyDays,
                netWorthCurrency: preferredCurrency,
                rates: rates
            )
            guard !Task.isCancelled else { return }
            await self.apply(result, generation: generation)
        }
    }

    private func apply(_ result: Computation, generation: Int) {
        guard generation == refreshGeneration else { return }
        figures = result.figures
        netWorthSeries = result.netWorthSeries
        netWorthTotal = result.netWorthTotal
        hasLoaded = true
    }

    // MARK: - Background computation

    private struct Computation: Sendable {
        let figures: [UUID: WalletFigures]
        let netWorthSeries: [Wallet.BalancePoint]
        let netWorthTotal: Decimal
    }

    nonisolated private static func compute(
        context: ModelContext,
        days: Int,
        netWorthCurrency: String,
        rates: [String: Double]
    ) -> Computation {
        let descriptor = FetchDescriptor<Wallet>(predicate: #Predicate { $0.deletedAt == nil })
        guard let wallets = try? context.fetch(descriptor) else {
            return Computation(figures: [:], netWorthSeries: [], netWorthTotal: 0)
        }

        var figures: [UUID: WalletFigures] = [:]
        figures.reserveCapacity(wallets.count)
        // Net worth covers active wallets only (matches the list's hero card).
        var netWorthByDay: [Date: Decimal] = [:]
        var netWorthTotal: Decimal = 0

        for wallet in wallets {
            // Fresh background context → the @Transient cache is empty, so this
            // computes from scratch using the exact same per-transaction
            // semantics as the main-actor path.
            let series = wallet.dailyBalanceSeries(days: days)
            let balance = wallet.balance
            figures[wallet.id] = WalletFigures(balance: balance, series: series)

            guard !wallet.isArchived else { continue }
            netWorthTotal += CurrencyManager.convert(
                amount: balance,
                from: wallet.currencyCode,
                to: netWorthCurrency,
                rates: rates
            )
            for point in series {
                let converted = CurrencyManager.convert(
                    amount: point.balance,
                    from: wallet.currencyCode,
                    to: netWorthCurrency,
                    rates: rates
                )
                netWorthByDay[point.date, default: 0] += converted
            }
        }

        let netWorthSeries = netWorthByDay
            .map { Wallet.BalancePoint(date: $0.key, balance: $0.value) }
            .sorted { $0.date < $1.date }

        return Computation(
            figures: figures,
            netWorthSeries: netWorthSeries,
            netWorthTotal: netWorthTotal
        )
    }
}
