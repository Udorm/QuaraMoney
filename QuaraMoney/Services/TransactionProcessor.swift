import Foundation
import SwiftData

/// Shared utility for processing transactions efficiently.
/// Consolidates duplicate logic from HomeViewModel, AnalysisViewModel, and TransactionListView.
struct TransactionProcessor {
    
    // MARK: - Daily Grouping
    
    /// Groups transactions by day and calculates daily flow (income - expense).
    /// Returns lightweight data with PersistentIdentifiers for background processing.
    nonisolated static func groupByDay(
        _ transactions: [Transaction],
        rates: [String: Double],
        targetCurrency: String
    ) -> [DailySectionData] {
        // Group by start of day
        let grouped = Dictionary(grouping: transactions) { txn -> Date in
            Calendar.current.startOfDay(for: txn.date)
        }
        
        let sortedKeys = grouped.keys.sorted(by: >)
        
        return sortedKeys.map { date in
            let txns = grouped[date] ?? []
            let dailyFlow = calculateDailyFlow(txns, rates: rates, targetCurrency: targetCurrency)
            let ids = txns.map { $0.persistentModelID }
            return DailySectionData(date: date, transactionIds: ids, dailyTotal: dailyFlow)
        }
    }
    
    /// Groups transactions by day and returns UI-ready sections with objects.
    /// Used by TransactionListView and other MainActor UI components.
    nonisolated static func groupByDayObjects(
        _ transactions: [Transaction],
        rates: [String: Double],
        targetCurrency: String
    ) -> [DailyTransactionSection] {
        // Group by start of day
        let grouped = Dictionary(grouping: transactions) { txn -> Date in
            Calendar.current.startOfDay(for: txn.date)
        }
        
        let sortedKeys = grouped.keys.sorted(by: >)
        
        return sortedKeys.map { date in
            let txns = grouped[date] ?? []
            let dailyFlow = calculateDailyFlow(txns, rates: rates, targetCurrency: targetCurrency)
            return DailyTransactionSection(date: date, transactions: txns, dailyTotal: dailyFlow)
        }
    }
    
    /// Calculates daily net flow (income positive, expense negative)
    nonisolated private static func calculateDailyFlow(_ transactions: [Transaction], rates: [String: Double], targetCurrency: String) -> Decimal {
        transactions.reduce(Decimal.zero) { result, txn in
            if txn.excludeFromReports { return result }
            
            let amount = convert(amount: txn.amount, from: txn.currencyCode, to: targetCurrency, rates: rates)
            
            switch txn.type {
            case .income: return result + amount
            case .expense: return result - amount
            case .transfer: return result  // Neutral for flow
            case .adjustment: return result + amount // Adjustments affect flow unless excluded
            }
        }
    }
    
    // MARK: - Summary Calculations
    
    /// Calculates income and expense totals from transactions.
    nonisolated static func calculateTotals(
        _ transactions: [Transaction],
        rates: [String: Double],
        targetCurrency: String
    ) -> (income: Decimal, expense: Decimal) {
        var income: Decimal = 0
        var expense: Decimal = 0
        
        for txn in transactions {
            if txn.excludeFromReports { continue }
            
            let amount = convert(amount: txn.amount, from: txn.currencyCode, to: targetCurrency, rates: rates)
            
            switch txn.type {
            case .income: income += amount
            case .expense: expense += amount
            case .transfer: break
            case .adjustment:
                if amount >= 0 {
                    income += amount
                } else {
                    expense += abs(amount)
                }
            }
        }
        
        return (income, expense)
    }
    
    /// Helper for currency conversion
    nonisolated private static func convert(amount: Decimal, from source: String, to target: String, rates: [String: Double]) -> Decimal {
        guard let sourceRate = rates[source], let targetRate = rates[target] else {
            // Fallback for KHR/USD typical case if rates missing
            if source == "USD" && target == "KHR" { return amount * 4000 }
            if source == "KHR" && target == "USD" { return amount / 4000 }
            if source == target { return amount }
            return amount
        }
        
        // Convert to Base (USD) then to Target
        let amountUSD = amount / Decimal(sourceRate)
        let amountTarget = amountUSD * Decimal(targetRate)
        return amountTarget
    }
    
    /// Creates a FetchDescriptor for transactions within a date range.
    nonisolated static func makeDescriptor(
        startDate: Date,
        endDate: Date,
        walletId: UUID? = nil,
        sortDescending: Bool = true,
        limit: Int? = nil,
        offset: Int = 0,
        excludeArchivedWallets: Bool = true
    ) -> FetchDescriptor<Transaction> {
        let start = startDate
        let end = endDate
        
        let sortDescriptors: [SortDescriptor<Transaction>] = sortDescending 
            ? [SortDescriptor(\.date, order: .reverse)] 
            : [SortDescriptor(\.date)]
        
        var descriptor: FetchDescriptor<Transaction>
        
        if let walletId = walletId {
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { txn in
                    txn.date >= start && txn.date < end &&
                    (txn.sourceWallet?.id == walletId || txn.destinationWallet?.id == walletId)
                },
                sortBy: sortDescriptors
            )
        } else if excludeArchivedWallets {
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { txn in
                    txn.date >= start && txn.date < end &&
                    txn.sourceWallet?.isArchived != true
                },
                sortBy: sortDescriptors
            )
        } else {
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { txn in
                    txn.date >= start && txn.date < end
                },
                sortBy: sortDescriptors
            )
        }
        
        if let limit = limit {
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
        }
        
        return descriptor
    }
    
    /// Fetches transactions and computes all derived data in a single pass.
    /// Runs on a background context and returns Sendable data.
    nonisolated static func fetchAndProcess(
        context: ModelContext,
        startDate: Date,
        endDate: Date,
        walletId: UUID? = nil,
        rates: [String: Double],
        targetCurrency: String,
        searchText: String? = nil
    ) -> ProcessedTransactionDataID {
        
        let descriptor = makeDescriptor(
            startDate: startDate,
            endDate: endDate,
            walletId: walletId
        )
        
        do {
            var transactions = try context.fetch(descriptor)
            
            // Apply search filter in-memory
            if let searchText = searchText?.trimmingCharacters(in: .whitespacesAndNewlines), !searchText.isEmpty {
                transactions = transactions.filter { txn in
                    let noteMatch = txn.note?.localizedCaseInsensitiveContains(searchText) ?? false
                    let categoryMatch = txn.category?.name.localizedCaseInsensitiveContains(searchText) ?? false
                    return noteMatch || categoryMatch
                }
            }
            
            let totals = calculateTotals(transactions, rates: rates, targetCurrency: targetCurrency)
            let sections = groupByDay(transactions, rates: rates, targetCurrency: targetCurrency)
            
            return ProcessedTransactionDataID(
                incomeTotal: totals.income,
                expenseTotal: totals.expense,
                dailySections: sections
            )
        } catch {
            return ProcessedTransactionDataID(
                incomeTotal: 0,
                expenseTotal: 0,
                dailySections: []
            )
        }
    }
}

// MARK: - Supporting Types

/// Lightweight daily section data for background transfer
struct DailySectionData: Sendable {
    let date: Date
    let transactionIds: [PersistentIdentifier]
    let dailyTotal: Decimal
}

/// Result of fetchAndProcess with IDs
struct ProcessedTransactionDataID: Sendable {
    let incomeTotal: Decimal
    let expenseTotal: Decimal
    let dailySections: [DailySectionData]
}

/// Helper struct for MainActor UI
struct DailyTransactionSection: Identifiable {
    var id: Date { date }
    let date: Date
    let transactions: [Transaction]
    let dailyTotal: Decimal
}
