import Foundation
import SwiftData

/// Service for handling budget period transitions and rollovers
@MainActor
class BudgetRolloverService {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Period Checking
    
    /// Check all budgets and process any that have ended their period
    func checkAndProcessBudgetRollovers() {
        let budgets = fetchAllBudgets()
        
        for budget in budgets {
            if shouldProcessRollover(for: budget) {
                processBudgetRollover(budget)
            }
        }
        
        // Save changes
        try? modelContext.save()
    }
    
    /// Check if a budget needs rollover processing
    private func shouldProcessRollover(for budget: Budget) -> Bool {
        // Only process recurring budgets that have ended
        guard budget.isRecurring && budget.isPeriodEnded else {
            return false
        }
        
        return true
    }
    
    // MARK: - Rollover Processing
    
    /// Process rollover for a single budget
    func processBudgetRollover(_ budget: Budget) {
        // Calculate spending for the ended period
        let spent = calculateSpending(for: budget)
        let unusedAmount = max(budget.effectiveLimit - spent, 0)
        
        // Log the rollover (for debugging/analytics)
        logRollover(budget: budget, spent: spent, unused: unusedAmount)
        
        // Perform the rollover
        budget.rolloverToNextPeriod(unusedAmount: unusedAmount)
        
        // Trigger notification if there was a rollover
        if budget.rolloverExcess && unusedAmount > 0 {
            notifyRollover(budget: budget, amount: unusedAmount)
        }
    }
    
    // MARK: - Spending Calculation
    
    private func calculateSpending(for budget: Budget) -> Decimal {
        let periodRange = budget.periodDateRange
        let preferredCurrency = CurrencyManager.shared.preferredCurrencyCode
        
        // Fetch transactions for this budget's period
        let transactions = fetchTransactions(for: budget, in: periodRange)
        
        return transactions.reduce(Decimal.zero) { total, txn in
            total + CurrencyManager.shared.convert(
                amount: txn.amount,
                from: txn.currencyCode,
                to: preferredCurrency
            )
        }
    }
    
    private func fetchTransactions(for budget: Budget, in range: (start: Date, end: Date)) -> [Transaction] {
        let start = range.start
        let end = range.end
        
        let descriptor: FetchDescriptor<Transaction>
        
        let expenseType = TransactionType.expense
        
        if budget.isTotalBudget {
            // Total budget - all expenses
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { txn in
                    txn.type == expenseType &&
                    txn.date >= start && txn.date < end
                }
            )
        } else if let categoryId = budget.category?.id {
            // Single category budget
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { txn in
                    txn.type == expenseType &&
                    txn.date >= start && txn.date < end &&
                    txn.category?.id == categoryId
                }
            )
        } else if let group = budget.categoryGroup {
            // Category group budget - fetch all and filter
            let baseDescriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { txn in
                    txn.type == expenseType &&
                    txn.date >= start && txn.date < end
                }
            )
            
            do {
                let allTransactions = try modelContext.fetch(baseDescriptor)
                return allTransactions.filter { txn in
                    guard let categoryId = txn.category?.id else { return false }
                    return group.categoryIds.contains(categoryId)
                }
            } catch {
                return []
            }
        } else {
            return []
        }
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            return []
        }
    }
    
    // MARK: - Data Fetching
    
    private func fetchAllBudgets() -> [Budget] {
        let descriptor = FetchDescriptor<Budget>()
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            return []
        }
    }
    
    // MARK: - Notifications
    
    private func notifyRollover(budget: Budget, amount: Decimal) {
        let notification = BudgetNotification(
            budgetId: budget.id,
            budgetName: budget.displayName,
            alertType: .info50, // Using info type for rollover
            progress: 0,
            timestamp: Date()
        )
        
        // Add to notification service (custom notification for rollover)
        Task {
            await scheduleRolloverNotification(budget: budget, amount: amount)
        }
    }
    
    private func scheduleRolloverNotification(budget: Budget, amount: Decimal) async {
        let center = UNUserNotificationCenter.current()
        
        let content = UNMutableNotificationContent()
        content.title = "Budget Rolled Over"
        content.body = "Your \(budget.displayName) budget has \(amount.formatted(.currency(code: budget.currencyCode))) carried over to the new period."
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "rollover_\(budget.id.uuidString)",
            content: content,
            trigger: nil
        )
        
        try? await center.add(request)
    }
    
    // MARK: - Logging
    
    private func logRollover(budget: Budget, spent: Decimal, unused: Decimal) {
        #if DEBUG
        print("""
        [BudgetRollover] Processing rollover for budget: \(budget.displayName)
          - Period: \(budget.periodDisplayString)
          - Limit: \(budget.effectiveLimit)
          - Spent: \(spent)
          - Unused: \(unused)
          - Rollover enabled: \(budget.rolloverExcess)
        """)
        #endif
    }
    
    // MARK: - Manual Rollover
    
    /// Manually trigger rollover for a specific budget (useful for testing or admin)
    func manualRollover(for budget: Budget) {
        guard budget.isRecurring else { return }
        
        processBudgetRollover(budget)
        try? modelContext.save()
    }
    
    /// Reset rollover amount for a budget
    func resetRollover(for budget: Budget) {
        budget.rolloverAmount = 0
        try? modelContext.save()
    }
    
    // MARK: - Batch Operations
    
    /// Process all pending rollovers
    func processAllPendingRollovers() -> Int {
        let budgets = fetchAllBudgets()
        var processedCount = 0
        
        for budget in budgets {
            if shouldProcessRollover(for: budget) {
                processBudgetRollover(budget)
                processedCount += 1
            }
        }
        
        try? modelContext.save()
        return processedCount
    }
    
    /// Get budgets that are due for rollover
    func getBudgetsDueForRollover() -> [Budget] {
        let budgets = fetchAllBudgets()
        return budgets.filter { shouldProcessRollover(for: $0) }
    }
}

// MARK: - Import for UNUserNotificationCenter

import UserNotifications
