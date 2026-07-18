import Foundation
import SwiftData
import UserNotifications

/// Value-only description of a rollover notification. No SwiftData model is
/// retained across the notification center's suspension points.
nonisolated struct BudgetRolloverNotificationPayload: Equatable, Sendable {
    let budgetID: UUID
    let budgetName: String
    let amount: Decimal
    let currencyCode: String

    var identifier: String { "rollover_\(budgetID.uuidString)" }
}

nonisolated struct BudgetRolloverPreparation: Equatable, Sendable {
    let processedBudgetIDs: [UUID]
    let notificationPayloads: [BudgetRolloverNotificationPayload]

    var hasChanges: Bool { !processedBudgetIDs.isEmpty }
}

/// Prepares budget period transitions without saving. The caller owns the
/// guarded commit so rollovers and category maintenance share one exact
/// identity snapshot/check/save-or-rollback boundary.
@MainActor
enum BudgetRolloverService {
    nonisolated static func prepareBudgetRollovers(
        modelContext: ModelContext,
        rates: [String: Double],
        preferredCurrency: String
    ) -> BudgetRolloverPreparation {
        let budgets = fetchAllBudgets(modelContext: modelContext)
        var processedBudgetIDs: [UUID] = []
        var notificationPayloads: [BudgetRolloverNotificationPayload] = []

        for budget in budgets where shouldProcessRollover(for: budget) {
            let spent = calculateSpending(
                for: budget,
                modelContext: modelContext,
                rates: rates,
                preferredCurrency: preferredCurrency
            )
            let unusedAmount = max(budget.effectiveLimit - spent, 0)

            #if DEBUG
            print("[BudgetRollover] Processing rollover for budget: \(budget.displayName)")
            #endif

            let payload = BudgetRolloverNotificationPayload(
                budgetID: budget.id,
                budgetName: budget.displayName,
                amount: unusedAmount,
                currencyCode: budget.currencyCode
            )
            let shouldNotify = budget.rolloverExcess && unusedAmount > 0

            budget.rolloverToNextPeriod(unusedAmount: unusedAmount)
            processedBudgetIDs.append(budget.id)
            if shouldNotify {
                notificationPayloads.append(payload)
            }
        }

        return BudgetRolloverPreparation(
            processedBudgetIDs: processedBudgetIDs,
            notificationPayloads: notificationPayloads
        )
    }

    nonisolated private static func shouldProcessRollover(for budget: Budget) -> Bool {
        budget.isRecurring && budget.isPeriodEnded
    }

    nonisolated private static func calculateSpending(
        for budget: Budget,
        modelContext: ModelContext,
        rates: [String: Double],
        preferredCurrency: String
    ) -> Decimal {
        let periodRange = budget.periodDateRange
        let transactions = fetchTransactions(
            for: budget,
            in: periodRange,
            modelContext: modelContext
        )

        return transactions.reduce(Decimal.zero) { total, transaction in
            total + CurrencyManager.convert(
                amount: transaction.amount,
                from: transaction.currencyCode,
                to: preferredCurrency,
                rates: rates
            )
        }
    }

    nonisolated private static func fetchTransactions(
        for budget: Budget,
        in range: (start: Date, end: Date),
        modelContext: ModelContext
    ) -> [Transaction] {
        let start = range.start
        let end = range.end
        let expenseType = TransactionType.expense
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { transaction in
                transaction.type == expenseType &&
                transaction.date >= start && transaction.date < end &&
                transaction.deletedAt == nil
            }
        )

        do {
            let transactions = try modelContext.fetch(descriptor)
                .filter { transaction in
                    transaction.event == nil &&
                    transaction.sourceWallet?.isArchived != true &&
                    !transaction.excludeFromReports
                }
            guard !budget.isTotalBudget else { return transactions }
            let categoryIDs = Set(budget.trackedCategoryIds)
            return transactions.filter { transaction in
                guard let categoryID = transaction.category?.id else { return false }
                return categoryIDs.contains(categoryID)
            }
        } catch {
            return []
        }
    }

    nonisolated private static func fetchAllBudgets(modelContext: ModelContext) -> [Budget] {
        let descriptor = FetchDescriptor<Budget>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startDate), SortDescriptor(\.id)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    static func scheduleNotification(_ payload: BudgetRolloverNotificationPayload) async {
        let content = UNMutableNotificationContent()
        content.title = "Budget Rolled Over"
        content.body = "Your \(payload.budgetName) budget has \(payload.amount.formattedAmount(for: payload.currencyCode)) carried over to the new period."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: payload.identifier,
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            #if DEBUG
            print("[BudgetRollover] Failed to schedule rollover notification: \(error)")
            #endif
        }
    }

    static func cancelNotifications(_ payloads: [BudgetRolloverNotificationPayload]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: payloads.map(\.identifier)
        )
    }
}
