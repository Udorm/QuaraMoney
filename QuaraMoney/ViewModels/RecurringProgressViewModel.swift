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
        Task { await calculateProgress() }
    }
    
    private func refreshCurrency() {
        preferredCurrencyCode = CurrencyManager.shared.preferredCurrencyCode
        Task { await calculateProgress() }
    }
    
    private func calculateProgress() async {
        let cal = Calendar.current
        let now = Date()
        
        // Find boundaries for current month
        guard let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)),
              let endOfMonth = cal.date(byAdding: DateComponents(month: 1, second: -1), to: startOfMonth) else {
            return
        }
        
        var tempPaidExpenses: Decimal = 0
        var tempReceivedIncome: Decimal = 0
        var tempPendingExpenses: Decimal = 0
        var tempPendingIncome: Decimal = 0
        
        let currencyManager = CurrencyManager.shared
        let targetCurrency = currencyManager.preferredCurrencyCode
        
        // 1. Fetch Paid/Received Transactions for this month
        let txDescriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.deletedAt == nil && $0.date >= startOfMonth && $0.date <= endOfMonth }
        )
        
        if let transactions = try? modelContext.fetch(txDescriptor) {
            for txn in transactions where txn.recurringRule != nil {
                let convertedAmount = currencyManager.convert(amount: txn.amount, from: txn.currencyCode, to: targetCurrency)
                if txn.type == .expense {
                    tempPaidExpenses += convertedAmount
                } else if txn.type == .income {
                    tempReceivedIncome += convertedAmount
                }
            }
        }
        
        // 2. Fetch Pending Rules
        let rulesDescriptor = FetchDescriptor<RecurringRule>(
            predicate: #Predicate { $0.deletedAt == nil && $0.isActive }
        )
        
        if let rules = try? modelContext.fetch(rulesDescriptor) {
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
                        let convertedAmount = currencyManager.convert(amount: rule.amount, from: rule.currencyCode, to: targetCurrency)

                        if rule.type == .expense {
                            tempPendingExpenses += convertedAmount
                        } else if rule.type == .income {
                            tempPendingIncome += convertedAmount
                        }
                    }

                    guard let next = RecurringRuleService.nextOccurrence(after: due, startDate: rule.startDate, frequency: rule.frequency, interval: rule.interval) else { break }
                    due = next
                    guardN += 1
                }
            }
        }
        
        self.paidExpenses = tempPaidExpenses
        self.expectedExpenses = tempPaidExpenses + tempPendingExpenses
        self.receivedIncome = tempReceivedIncome
        self.expectedIncome = tempReceivedIncome + tempPendingIncome
    }
}
