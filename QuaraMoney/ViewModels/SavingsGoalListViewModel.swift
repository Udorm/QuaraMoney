import Foundation

@Observable
@MainActor
class SavingsGoalListViewModel {
    var showCompletedGoals = false

    func activeGoals(from goals: [SavingsGoal], matching searchText: String) -> [SavingsGoal] {
        let filtered = goals.filter { !$0.isCompleted }
        if searchText.isEmpty { return filtered }
        return filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    func completedGoals(from goals: [SavingsGoal], matching searchText: String) -> [SavingsGoal] {
        let filtered = goals.filter { $0.isCompleted }
        if searchText.isEmpty { return filtered }
        return filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    func totalSaved(from goals: [SavingsGoal]) -> Decimal {
        let targetCurrency = CurrencyManager.shared.preferredCurrencyCode
        return goals.reduce(Decimal.zero) { total, goal in
            total + CurrencyManager.shared.convert(
                amount: goal.totalSaved(converter: CurrencyManager.shared.convert),
                from: goal.currencyCode,
                to: targetCurrency
            )
        }
    }

    func totalTarget(from goals: [SavingsGoal]) -> Decimal {
        let targetCurrency = CurrencyManager.shared.preferredCurrencyCode
        return goals.reduce(Decimal.zero) { total, goal in
            total + CurrencyManager.shared.convert(
                amount: goal.targetAmount,
                from: goal.currencyCode,
                to: targetCurrency
            )
        }
    }

    func overallProgress(from goals: [SavingsGoal]) -> Double {
        let target = totalTarget(from: goals)
        let saved = totalSaved(from: goals)
        return target > 0 ? Double(truncating: saved as NSNumber) / Double(truncating: target as NSNumber) : 0
    }
}
