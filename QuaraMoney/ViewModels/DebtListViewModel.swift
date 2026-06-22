import SwiftUI
import SwiftData

@Observable
@MainActor
final class DebtListViewModel {
    var selectedType: DebtType? = nil
    var showCompleted = false

    func filteredDebts(_ allDebts: [Debt]) -> [Debt] {
        var debts = allDebts
        if let type = selectedType {
            debts = debts.filter { $0.type == type }
        }
        return debts
    }
    
    func activeDebts(_ allDebts: [Debt]) -> [Debt] {
        filteredDebts(allDebts).filter { !$0.isCompleted }
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
