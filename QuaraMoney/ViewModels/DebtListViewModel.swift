import SwiftUI
import SwiftData

@Observable
@MainActor
final class DebtListViewModel {
    var selectedType: DebtType = .iOwe
    var showCompleted = false
    var searchText: String = ""

    func filteredDebts(_ allDebts: [Debt]) -> [Debt] {
        var debts = allDebts.filter { $0.type == selectedType }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            debts = debts.filter { $0.personName.localizedCaseInsensitiveContains(query) }
        }
        return debts
    }

    /// True when a name search is currently narrowing the list.
    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Outstanding debts past their due date, surfaced above everything else so
    /// time-sensitive items never get buried. Most-overdue (soonest due) first.
    func overdueDebts(_ allDebts: [Debt]) -> [Debt] {
        filteredDebts(allDebts)
            .filter { !$0.isCompleted && $0.isOverdue }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    /// Outstanding debts that are not overdue, ordered by soonest due date first
    /// (undated debts fall to the bottom, newest-created among them first).
    func activeDebts(_ allDebts: [Debt]) -> [Debt] {
        filteredDebts(allDebts)
            .filter { !$0.isCompleted && !$0.isOverdue }
            .sorted { a, b in
                switch (a.dueDate, b.dueDate) {
                case let (x?, y?): return x < y
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):   return a.dateCreated > b.dateCreated
                }
            }
    }

    func completedDebts(_ allDebts: [Debt]) -> [Debt] {
        filteredDebts(allDebts).filter { $0.isCompleted }
    }
    
    /// Sum of outstanding balances owed to the user, converted to the
    /// preferred currency so multi-currency debts aggregate correctly.
    func totalOwedToMe(_ allDebts: [Debt]) -> Decimal {
        convertedRemaining(allDebts.filter { $0.type == .owedToMe })
    }

    /// Sum of outstanding balances the user owes, in the preferred currency.
    func totalIOwe(_ allDebts: [Debt]) -> Decimal {
        convertedRemaining(allDebts.filter { $0.type == .iOwe })
    }

    /// Net position (owed to me − I owe) in the preferred currency.
    func netPosition(_ allDebts: [Debt]) -> Decimal {
        totalOwedToMe(allDebts) - totalIOwe(allDebts)
    }

    private func convertedRemaining(_ debts: [Debt]) -> Decimal {
        let preferred = CurrencyManager.shared.preferredCurrencyCode
        let rates = CurrencyManager.shared.rates
        return debts.reduce(0) { sum, debt in
            sum + CurrencyManager.convert(
                amount: debt.displayRemaining,
                from: debt.currencyCode,
                to: preferred,
                rates: rates
            )
        }
    }

    /// Number of wallet transactions that would be deleted along with this debt
    /// (Debt.transactions is a `.cascade` relationship).
    func linkedTransactionCount(_ debt: Debt) -> Int {
        (debt.transactions ?? []).filter { $0.deletedAt == nil }.count
    }

    /// Deletes a debt and its cascade-linked transactions, invalidating the
    /// balance caches of every wallet those transactions touched so balances
    /// don't silently go stale.
    func deleteDebt(_ debt: Debt, context: ModelContext) {
        // Soft-delete the debt and its cascade-linked transactions (tombstones
        // replicate; balance caches are invalidated inside deleteTransaction).
        SoftDeleteService.deleteDebt(debt)
        do {
            try context.save()
        } catch {
            ErrorService.shared.handlePersistenceError(error, context: "DebtListViewModel.deleteDebt")
        }
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }

    func toggleCompletion(for debt: Debt) {
        debt.isCompleted.toggle()
    }
}
