import Foundation
import SwiftData
import SwiftUI

/// Removes its NotificationCenter observers when released. Lives outside the
/// @MainActor view model so this nonisolated `deinit` is legal.
private final class ObserverBag {
    var tokens: [NSObjectProtocol] = []
    deinit { tokens.forEach { NotificationCenter.default.removeObserver($0) } }
}

@Observable
@MainActor
final class RecurringProgressViewModel: BaseViewModel {
    var paidExpenses: Decimal = 0
    var expectedExpenses: Decimal = 0
    var receivedIncome: Decimal = 0
    var expectedIncome: Decimal = 0
    var preferredCurrencyCode: String = CurrencyManager.shared.preferredCurrencyCode

    @ObservationIgnored private let modelContext: ModelContext
    // Held in a plain (non-actor-isolated) box so its own deinit can remove the
    // observers — a @MainActor class can't provide a matching nonisolated deinit.
    @ObservationIgnored private let observerBag = ObserverBag()
    // Coalesces bursts of `.dataDidUpdate` (e.g. Post-All firing many writes)
    // into a single recompute.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(dataService: DataService, context: ModelContext) {
        self.modelContext = context
        super.init(dataService: dataService)

        observerBag.tokens.append(NotificationCenter.default.addObserver(forName: .dataDidUpdate, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        })
        observerBag.tokens.append(NotificationCenter.default.addObserver(forName: .languageDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.refreshCurrency()
        })

        Task { await calculateProgress() }
    }

    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            await self.calculateProgress()
        }
    }

    private func refreshCurrency() {
        preferredCurrencyCode = CurrencyManager.shared.preferredCurrencyCode
        refresh()
    }

    private func calculateProgress() async {
        // Snapshot the MainActor inputs, then do the fetch + conversion loop on a
        // background ModelContext so a large overdue catch-up never hitches the UI.
        let container = modelContext.container
        let rates = CurrencyManager.shared.rates
        let targetCurrency = CurrencyManager.shared.preferredCurrencyCode

        let result = await Task.detached(priority: .utility) {
            Self.computeProgress(container: container, rates: rates, targetCurrency: targetCurrency)
        }.value

        guard !Task.isCancelled else { return }
        self.paidExpenses = result.paidExpenses
        self.expectedExpenses = result.paidExpenses + result.pendingExpenses
        self.receivedIncome = result.receivedIncome
        self.expectedIncome = result.receivedIncome + result.pendingIncome
    }

    private struct ProgressResult: Sendable {
        var paidExpenses: Decimal = 0
        var pendingExpenses: Decimal = 0
        var receivedIncome: Decimal = 0
        var pendingIncome: Decimal = 0
    }

    /// Pure, background-safe computation: fetches this month's recurring
    /// transactions (paid) and projects each active rule's remaining occurrences
    /// (pending), all converted to `targetCurrency` at the supplied rates.
    nonisolated private static func computeProgress(
        container: ModelContainer,
        rates: [String: Double],
        targetCurrency: String
    ) -> ProgressResult {
        let context = ModelContext(container)
        let cal = Calendar.current
        let now = Date()

        guard let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)),
              let endOfMonth = cal.date(byAdding: DateComponents(month: 1, second: -1), to: startOfMonth) else {
            return ProgressResult()
        }

        var result = ProgressResult()

        // 1. Paid/received recurring transactions this month. (SwiftData can't
        // predicate the optional `recurringRule` relationship, so the fetch is
        // date-bounded and the relationship filtered in memory.)
        let txDescriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.deletedAt == nil && $0.date >= startOfMonth && $0.date <= endOfMonth }
        )
        if let transactions = try? context.fetch(txDescriptor) {
            for txn in transactions where txn.recurringRule != nil {
                let converted = CurrencyManager.convert(amount: txn.amount, from: txn.currencyCode, to: targetCurrency, rates: rates)
                if txn.type == .expense {
                    result.paidExpenses += converted
                } else if txn.type == .income {
                    result.receivedIncome += converted
                }
            }
        }

        // 2. Pending occurrences from active rules.
        let rulesDescriptor = FetchDescriptor<RecurringRule>(
            predicate: #Predicate { $0.deletedAt == nil && $0.isActive }
        )
        if let rules = try? context.fetch(rulesDescriptor) {
            for rule in rules {
                var due = rule.nextDueDate
                var guardN = 0
                // Count occurrences whose due date falls within THIS month. An
                // overdue rule's nextDueDate may sit in a prior month, so skip
                // (don't count) occurrences before the month start rather than
                // attributing those arrears to the current month's expected total.
                while due <= endOfMonth, guardN < 1000 {
                    if let end = rule.endDate, due > end { break }

                    if due >= startOfMonth {
                        let converted = CurrencyManager.convert(amount: rule.amount, from: rule.currencyCode, to: targetCurrency, rates: rates)
                        if rule.type == .expense {
                            result.pendingExpenses += converted
                        } else if rule.type == .income {
                            result.pendingIncome += converted
                        }
                    }

                    guard let next = RecurringRuleService.nextOccurrence(after: due, startDate: rule.startDate, frequency: rule.frequency, interval: rule.interval) else { break }
                    due = next
                    guardN += 1
                }
            }
        }

        return result
    }
}
