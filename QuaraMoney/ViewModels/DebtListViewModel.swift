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
    
    func totalOwedToMe(_ allDebts: [Debt]) -> Decimal {
        allDebts.filter { $0.type == .owedToMe }.reduce(0) { $0 + $1.remainingAmount }
    }

    func totalIOwe(_ allDebts: [Debt]) -> Decimal {
        allDebts.filter { $0.type == .iOwe }.reduce(0) { $0 + $1.remainingAmount }
    }

    /// Number of wallet transactions that would be deleted along with this debt
    /// (Debt.transactions is a `.cascade` relationship).
    func linkedTransactionCount(_ debt: Debt) -> Int {
        debt.transactions?.count ?? 0
    }

    /// Deletes a debt and its cascade-linked transactions, invalidating the
    /// balance caches of every wallet those transactions touched so balances
    /// don't silently go stale.
    func deleteDebt(_ debt: Debt, context: ModelContext) {
        for txn in debt.transactions ?? [] {
            txn.sourceWallet?.invalidateBalanceCache()
            txn.destinationWallet?.invalidateBalanceCache()
        }

        context.delete(debt)
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
