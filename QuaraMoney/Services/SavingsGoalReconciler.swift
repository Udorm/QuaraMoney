import Foundation
import SwiftData

@MainActor
enum SavingsGoalReconciler {
    struct Result: Equatable {
        let total: Decimal
        let hasUnconvertedRows: Bool
    }

    static func total(for goal: SavingsGoal) -> Result {
        total(for: goal, rates: CurrencyManager.shared.rates)
    }

    static func total(for goal: SavingsGoal, rates: [String: Double]) -> Result {
        var raw = Decimal.zero
        var missing = false

        if goal.currentAmount > 0 {
            let code = goal.startingBalanceCurrencyCode ?? goal.currencyCode
            if let converted = convert(goal.currentAmount, from: code, to: goal.currencyCode, rates: rates) {
                raw += converted
            } else { missing = true }
        }

        for transaction in goal.linkedTransactions ?? [] where SavingsLedger.isEligible(transaction, for: goal) {
            guard let side = TransferSideAmountResolver.ledgerAmount(for: transaction),
                  let amount = convert(side.amount, from: side.currencyCode, to: goal.currencyCode, rates: rates) else {
                missing = true
                continue
            }
            raw += transaction.savingsIsWithdrawal ? -amount : amount
        }
        return Result(total: max(0, raw), hasUnconvertedRows: missing)
    }

    @discardableResult
    static func reconcile(_ goal: SavingsGoal, at date: Date = Date(), markNeedsSync: Bool = true) -> Bool {
        let completed = total(for: goal).total >= goal.targetAmount
        guard completed != goal.isCompleted else { return false }
        goal.isCompleted = completed
        goal.completedDate = completed ? date : nil
        goal.updatedAt = date
        if markNeedsSync { goal.needsSync = true }
        return true
    }

    @discardableResult
    static func reconcileAll(in context: ModelContext, markNeedsSync: Bool = true) throws -> Bool {
        let goals = try context.fetch(FetchDescriptor<SavingsGoal>()).filter { $0.deletedAt == nil }
        var changed = false
        for goal in goals { changed = reconcile(goal, markNeedsSync: markNeedsSync) || changed }
        if changed { try context.save() }
        return changed
    }

    private static func convert(_ amount: Decimal, from: String, to: String, rates: [String: Double]) -> Decimal? {
        guard from != to else { return amount }
        guard let source = rates[from], let target = rates[to], source > 0, target > 0 else { return nil }
        return amount / Decimal(source) * Decimal(target)
    }
}
