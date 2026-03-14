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

    func deleteDebts(_ debts: [Debt], at offsets: IndexSet, context: ModelContext) {
        let validOffsets = offsets.filter { $0 < debts.count }
        for index in validOffsets {
            let debt = debts[index]
            context.delete(debt)
        }
        do {
            try context.save()
        } catch {
            ErrorService.shared.handlePersistenceError(error, context: "DebtListViewModel.deleteDebts")
        }
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }

    func toggleCompletion(for debt: Debt) {
        debt.isCompleted.toggle()
    }
}
