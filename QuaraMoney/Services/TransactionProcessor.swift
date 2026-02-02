import Foundation
import SwiftData

/// Shared utility for processing transactions efficiently.
/// Consolidates duplicate logic from HomeViewModel, AnalysisViewModel, and TransactionListView.
@MainActor
struct TransactionProcessor {
    
    // MARK: - Daily Grouping
    
    /// Groups transactions by day and calculates daily flow (income - expense).
    /// This replaces duplicate logic in HomeViewModel, AnalysisViewModel, and TransactionListView.
    static func groupByDay(
        _ transactions: [Transaction],
        currency: String? = nil
    ) -> [DailyTransactionSection] {
        let targetCurrency = currency ?? CurrencyManager.shared.preferredCurrencyCode
        
        // Group by start of day
        let grouped = Dictionary(grouping: transactions) { txn -> Date in
            Calendar.current.startOfDay(for: txn.date)
        }
        
        let sortedKeys = grouped.keys.sorted(by: >)
        
        return sortedKeys.map { date in
            let txns = grouped[date] ?? []
            let dailyFlow = calculateDailyFlow(txns, currency: targetCurrency)
            return DailyTransactionSection(date: date, transactions: txns, dailyTotal: dailyFlow)
        }
    }
    
    /// Calculates daily net flow (income positive, expense negative)
    private static func calculateDailyFlow(_ transactions: [Transaction], currency: String) -> Decimal {
        transactions.reduce(Decimal.zero) { result, txn in
            let amount = CurrencyManager.shared.convert(
                amount: txn.amount,
                from: txn.currencyCode,
                to: currency
            )
            
            switch txn.type {
            case .income: return result + amount
            case .expense: return result - amount
            case .transfer: return result  // Neutral for flow
            }
        }
    }
    
    // MARK: - Summary Calculations
    
    /// Calculates income and expense totals from transactions.
    /// Replaces duplicate logic in HomeViewModel.fetchSummary() and AnalysisViewModel.
    static func calculateTotals(
        _ transactions: [Transaction],
        currency: String? = nil
    ) -> (income: Decimal, expense: Decimal) {
        let targetCurrency = currency ?? CurrencyManager.shared.preferredCurrencyCode
        var income: Decimal = 0
        var expense: Decimal = 0
        
        for txn in transactions {
            let amount = CurrencyManager.shared.convert(
                amount: txn.amount,
                from: txn.currencyCode,
                to: targetCurrency
            )
            
            switch txn.type {
            case .income: income += amount
            case .expense: expense += amount
            case .transfer: break
            }
        }
        
        return (income, expense)
    }
    
    /// Creates a FetchDescriptor for transactions within a date range.
    /// Consolidates duplicate predicate building from multiple ViewModels.
    static func makeDescriptor(
        startDate: Date,
        endDate: Date,
        walletId: UUID? = nil,
        sortDescending: Bool = true,
        limit: Int? = nil,
        offset: Int = 0
    ) -> FetchDescriptor<Transaction> {
        let start = startDate
        let end = endDate
        
        var descriptor: FetchDescriptor<Transaction>
        
        if let walletId = walletId {
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { txn in
                    txn.date >= start && txn.date < end &&
                    (txn.sourceWallet?.id == walletId || txn.destinationWallet?.id == walletId)
                },
                sortBy: sortDescending ? [SortDescriptor(\.date, order: .reverse)] : [SortDescriptor(\.date)]
            )
        } else {
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { txn in
                    txn.date >= start && txn.date < end
                },
                sortBy: sortDescending ? [SortDescriptor(\.date, order: .reverse)] : [SortDescriptor(\.date)]
            )
        }
        
        // Apply pagination if specified
        if let limit = limit {
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
        }
        
        return descriptor
    }
    
    /// Fetches transactions and computes all derived data in a single pass.
    /// Eliminates duplicate fetches for summary + daily sections.
    static func fetchAndProcess(
        context: ModelContext,
        startDate: Date,
        endDate: Date,
        walletId: UUID? = nil,
        currency: String? = nil
    ) -> ProcessedTransactionData {
        let targetCurrency = currency ?? CurrencyManager.shared.preferredCurrencyCode
        
        let descriptor = makeDescriptor(
            startDate: startDate,
            endDate: endDate,
            walletId: walletId
        )
        
        do {
            let transactions = try context.fetch(descriptor)
            let totals = calculateTotals(transactions, currency: targetCurrency)
            let sections = groupByDay(transactions, currency: targetCurrency)
            
            return ProcessedTransactionData(
                transactions: transactions,
                incomeTotal: totals.income,
                expenseTotal: totals.expense,
                dailySections: sections
            )
        } catch {
            print("TransactionProcessor fetch error: \(error)")
            return ProcessedTransactionData(
                transactions: [],
                incomeTotal: 0,
                expenseTotal: 0,
                dailySections: []
            )
        }
    }
    
    // MARK: - Pagination Support
    
    /// Default page size for paginated fetches
    static let defaultPageSize = 50
    
    /// Fetches a page of transactions for infinite scroll implementation.
    /// Returns transactions and a flag indicating if more data is available.
    static func fetchPaginated(
        context: ModelContext,
        startDate: Date,
        endDate: Date,
        walletId: UUID? = nil,
        page: Int = 0,
        pageSize: Int = defaultPageSize
    ) -> (transactions: [Transaction], hasMore: Bool) {
        let descriptor = makeDescriptor(
            startDate: startDate,
            endDate: endDate,
            walletId: walletId,
            limit: pageSize + 1,  // Fetch one extra to check if more exist
            offset: page * pageSize
        )
        
        do {
            var transactions = try context.fetch(descriptor)
            let hasMore = transactions.count > pageSize
            
            // Remove the extra item we fetched for checking
            if hasMore {
                transactions.removeLast()
            }
            
            return (transactions, hasMore)
        } catch {
            print("TransactionProcessor paginated fetch error: \(error)")
            return ([], false)
        }
    }
}

// MARK: - Supporting Types

/// Result of fetchAndProcess - contains all computed data from a single fetch
struct ProcessedTransactionData {
    let transactions: [Transaction]
    let incomeTotal: Decimal
    let expenseTotal: Decimal
    let dailySections: [DailyTransactionSection]
}

