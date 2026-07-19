import Foundation
import SwiftData

nonisolated struct PlanMaintenanceResult: Sendable, Equatable {
    let changed: Bool
    let markerKey: String
}

/// Idempotent additive migration plus old-client normalization for Plan data.
enum PlanDataMaintenance {
    nonisolated static let version = 1

    /// Store-format gate for the one-time budget category join reconciliation.
    /// The owner suffix mirrors the Plan maintenance marker so account switches
    /// never let one user's completed repair suppress another user's.
    nonisolated static let budgetCategoryStoreVersion = 1

    nonisolated static func markerKey(ownerID: UUID?) -> String {
        "planDataMigration.v\(version).\(ownerID?.uuidString ?? "local")"
    }

    nonisolated static func budgetCategoryReconciliationMarkerKey(ownerID: UUID) -> String {
        "budgetCategoryJoinReconciliation.v\(budgetCategoryStoreVersion).\(ownerID.uuidString)"
    }

    nonisolated static func needsBudgetCategoryReconciliation(
        ownerID: UUID,
        defaults: UserDefaults = .standard
    ) -> Bool {
        !defaults.bool(forKey: budgetCategoryReconciliationMarkerKey(ownerID: ownerID))
    }

    nonisolated static func commitBudgetCategoryReconciliation(
        ownerID: UUID,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(true, forKey: budgetCategoryReconciliationMarkerKey(ownerID: ownerID))
    }

    @discardableResult
    nonisolated static func run(in context: ModelContext, ownerID: UUID?, rates: [String: Double], calendar: Calendar = .current, now: Date = Date(), commitsMarker: Bool = true) throws -> PlanMaintenanceResult {
        let key = markerKey(ownerID: ownerID)
        let needsMigration = !UserDefaults.standard.bool(forKey: key)
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let goals = try context.fetch(FetchDescriptor<SavingsGoal>())
        var changed = false

        for budget in budgets where budget.deletedAt == nil {
            var budgetChanged = false
            let originalType = budget.periodType
            if case .percentOfIncome(let percentage) = budget.amountType {
                let current = originalType.currentPeriodRange(containing: now, calendar: calendar)
                let previousEnd = current.start
                let previousStart = originalType.dateRange(
                    from: originalType.periodStart(containing: calendar.date(byAdding: .second, value: -1, to: previousEnd) ?? previousEnd, calendar: calendar),
                    calendar: calendar
                ).start
                let income = transactions.lazy.filter {
                    $0.deletedAt == nil && $0.event == nil && !$0.excludeFromReports &&
                    $0.type == .income && $0.date >= previousStart && $0.date < previousEnd
                }.reduce(Decimal.zero) { total, transaction in
                    guard let converted = converted(transaction.amount, from: transaction.currencyCode,
                                                    to: budget.currencyCode, rates: rates) else { return total }
                    return total + converted
                }
                budget.amountLimit = income * Decimal(percentage)
                budget.amountType = .fixed(budget.amountLimit)
                changed = true; budgetChanged = true
            }

            let originalWindow = originalType.dateRange(from: budget.startDate, calendar: calendar)
            if originalType != .custom, !budget.isRecurring {
                budget.periodType = .custom
                budget.customEndDate = calendar.date(byAdding: .day, value: -1, to: originalWindow.end)
                changed = true; budgetChanged = true
            } else if originalType == .biweekly, budget.isRecurring {
                budget.periodType = .weekly
                budget.weekStartDay = calendar.firstWeekday
                changed = true; budgetChanged = true
            }
            if budget.targetKindRaw == nil { budget.targetKindRaw = budget.targetKind.rawValue; changed = true; budgetChanged = true }
            if budget.alertModeRaw == nil { budget.alertModeRaw = budget.alertMode.rawValue; changed = true; budgetChanged = true }
            if budget.periodType == .weekly, budget.weekStartDay == nil { budget.weekStartDay = calendar.firstWeekday; changed = true; budgetChanged = true }
            if budgetChanged { budget.updatedAt = now; budget.needsSync = true }
        }

        for goal in goals where goal.deletedAt == nil {
            if goal.currentAmount > 0, goal.startingBalanceCurrencyCode == nil {
                goal.startingBalanceCurrencyCode = goal.currencyCode
                goal.updatedAt = now
                goal.needsSync = true
                changed = true
            }
        }
        if needsMigration {
            for goal in goals where goal.deletedAt == nil {
                let startingCurrency = goal.startingBalanceCurrencyCode ?? goal.currencyCode
                var total = converted(goal.currentAmount, from: startingCurrency,
                                      to: goal.currencyCode, rates: rates) ?? 0
                for transaction in goal.linkedTransactions ?? [] where SavingsLedger.isEligible(transaction, for: goal) {
                    guard let side = TransferSideAmountResolver.ledgerAmount(for: transaction) else { continue }
                    guard let amount = converted(side.amount, from: side.currencyCode,
                                                 to: goal.currencyCode, rates: rates) else { continue }
                    total += transaction.savingsIsWithdrawal ? -amount : amount
                }
                let completed = max(0, total) >= goal.targetAmount
                if completed != goal.isCompleted {
                    goal.isCompleted = completed
                    goal.completedDate = completed ? now : nil
                    goal.needsSync = true
                    goal.updatedAt = now
                    changed = true
                }
            }
        }
        if changed && commitsMarker { try context.save() }
        if needsMigration && commitsMarker {
            // The durable marker is committed only after the guarded save above succeeds.
            UserDefaults.standard.set(true, forKey: key)
        }
        return PlanMaintenanceResult(changed: changed, markerKey: key)
    }

    nonisolated private static func converted(_ amount: Decimal, from sourceCode: String,
                                              to targetCode: String, rates: [String: Double]) -> Decimal? {
        guard sourceCode != targetCode else { return amount }
        guard let source = rates[sourceCode], let target = rates[targetCode], source > 0, target > 0 else { return nil }
        return amount / Decimal(source) * Decimal(target)
    }
}
