import Foundation
import SwiftData

/// Service for handling budget period transitions and rollovers
struct BudgetRolloverService {
    // MARK: - Period Checking
    
    /// Check all budgets and process any that have ended their period
    nonisolated static func checkAndProcessBudgetRollovers(
        modelContext: ModelContext,
        rates: [String: Double],
        preferredCurrency: String
    ) {
        let budgets = fetchAllBudgets(modelContext: modelContext)
        
        for budget in budgets {
            if shouldProcessRollover(for: budget) {
                processBudgetRollover(budget, modelContext: modelContext, rates: rates, preferredCurrency: preferredCurrency)
            }
        }
        
        // Save changes
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("[BudgetRollover] Failed to save rollover changes: \(error)")
            #endif
        }
    }
    
    /// Check if a budget needs rollover processing
    nonisolated private static func shouldProcessRollover(for budget: Budget) -> Bool {
        // Only process recurring budgets that have ended
        guard budget.isRecurring && budget.isPeriodEnded else {
            return false
        }
        
        return true
    }
    
    /// Process rollover for a single budget
    nonisolated private static func processBudgetRollover(
        _ budget: Budget,
        modelContext: ModelContext,
        rates: [String: Double],
        preferredCurrency: String
    ) {
        // Calculate spending for the ended period
        let spent = calculateSpending(for: budget, modelContext: modelContext, rates: rates, preferredCurrency: preferredCurrency)
        let unusedAmount = max(budget.effectiveLimit - spent, 0)
        
        // Log the rollover
        logRollover(budget: budget, spent: spent, unused: unusedAmount)
        
        // Perform the rollover
        budget.rolloverToNextPeriod(unusedAmount: unusedAmount)
        
        // Trigger notification if there was a rollover
        if budget.rolloverExcess && unusedAmount > 0 {
            notifyRollover(budget: budget, amount: unusedAmount)
        }
    }
    
    // MARK: - Spending Calculation
    
    nonisolated private static func calculateSpending(
        for budget: Budget,
        modelContext: ModelContext,
        rates: [String: Double],
        preferredCurrency: String
    ) -> Decimal {
        let periodRange = budget.periodDateRange
        
        // Fetch transactions for this budget's period
        let transactions = fetchTransactions(for: budget, in: periodRange, modelContext: modelContext)
        
        return transactions.reduce(Decimal.zero) { total, txn in
            total + convert(
                amount: txn.amount,
                from: txn.currencyCode,
                to: preferredCurrency,
                rates: rates
            )
        }
    }
    
    nonisolated private static func convert(amount: Decimal, from source: String, to target: String, rates: [String: Double]) -> Decimal {
        guard let sourceRate = rates[source], let targetRate = rates[target] else {
            if source == "USD" && target == "KHR" { return amount * 4000 }
            if source == "KHR" && target == "USD" { return amount / 4000 }
            if source == target { return amount }
            return amount
        }
        let amountUSD = amount / Decimal(sourceRate)
        return amountUSD * Decimal(targetRate)
    }
    
    nonisolated private static func fetchTransactions(for budget: Budget, in range: (start: Date, end: Date), modelContext: ModelContext) -> [Transaction] {
        let start = range.start
        let end = range.end
        
        let expenseType = TransactionType.expense
        
        let descriptor: FetchDescriptor<Transaction>
        if budget.isTotalBudget {
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { txn in
                    txn.type == expenseType &&
                    txn.date >= start && txn.date < end &&
                    txn.event == nil &&
                    txn.sourceWallet?.isArchived != true &&
                    !txn.excludeFromReports
                }
            )
        } else {
            // Category budget
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { txn in
                    txn.type == expenseType &&
                    txn.date >= start && txn.date < end &&
                    txn.event == nil &&
                    txn.sourceWallet?.isArchived != true &&
                    !txn.excludeFromReports
                }
            )
        }
        
        do {
            let allTransactions = try modelContext.fetch(descriptor)
            if budget.isTotalBudget {
                return allTransactions
            } else {
                let categoryIds = budget.trackedCategoryIds
                return allTransactions.filter { txn in
                    guard let txnCategoryId = txn.category?.id else { return false }
                    return categoryIds.contains(txnCategoryId)
                }
            }
        } catch {
            return []
        }
    }
    
    // MARK: - Data Fetching
    
    nonisolated private static func fetchAllBudgets(modelContext: ModelContext) -> [Budget] {
        let descriptor = FetchDescriptor<Budget>()
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            return []
        }
    }
    
    // MARK: - Notifications
    
    nonisolated private static func notifyRollover(budget: Budget, amount: Decimal) {
        Task {
            await scheduleRolloverNotification(budget: budget, amount: amount)
        }
    }
    
    nonisolated private static func scheduleRolloverNotification(budget: Budget, amount: Decimal) async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Budget Rolled Over"
        content.body = "Your \(budget.displayName) budget has \(amount.formattedAmount(for: budget.currencyCode)) carried over to the new period."
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "rollover_\(budget.id.uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            #if DEBUG
            print("[BudgetRollover] Failed to schedule rollover notification: \(error)")
            #endif
        }
    }
    
    // MARK: - Logging
    
    nonisolated private static func logRollover(budget: Budget, spent: Decimal, unused: Decimal) {
        #if DEBUG
        print("[BudgetRollover] Processing rollover for budget: \(budget.displayName)")
        #endif
    }
}

// MARK: - Import for UNUserNotificationCenter

import UserNotifications
