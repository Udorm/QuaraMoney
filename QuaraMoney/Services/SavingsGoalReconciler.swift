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
        let rows = (goal.linkedTransactions ?? []).compactMap { transaction -> SavingsLedgerEntrySnapshot? in
            guard SavingsLedger.isEligible(transaction, for: goal),
                  let side = TransferSideAmountResolver.ledgerAmount(for: transaction) else {
                return nil
            }
            return SavingsLedgerEntrySnapshot(
                id: transaction.id,
                goalID: goal.id,
                date: transaction.date,
                amount: side.amount,
                currencyCode: side.currencyCode,
                isWithdrawal: transaction.savingsIsWithdrawal
            )
        }
        let result = SavingsLedgerCalculator.calculate(
            startingBalance: goal.currentAmount,
            startingCurrencyCode: goal.startingBalanceCurrencyCode ?? goal.currencyCode,
            goalCurrencyCode: goal.currencyCode,
            rows: rows,
            rates: rates
        )
        return Result(total: result.total, hasUnconvertedRows: result.hasUnconvertedRows)
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
}
