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
        targetCurrency: String,
        sortAscending: Bool = false
    ) -> [DailySectionData] {
        // Group by start of day
        let grouped = Dictionary(grouping: transactions) { txn -> Date in
            Calendar.current.startOfDay(for: txn.date)
        }
        
        let sortedKeys = grouped.keys.sorted(by: { sortAscending ? $0 < $1 : $0 > $1 })
        
        return sortedKeys.map { date in
            let txns = grouped[date] ?? []
            let sortedTxns = txns.sorted { t1, t2 in
                sortAscending ? t1.date < t2.date : t1.date > t2.date
            }
            let dailyFlow = calculateDailyFlow(sortedTxns, rates: rates, targetCurrency: targetCurrency)
            let ids = sortedTxns.map { $0.persistentModelID }
            return DailySectionData(date: date, transactionIds: ids, dailyTotal: dailyFlow)
        }
    }
    
    /// Groups transactions by day and returns UI-ready sections with objects.
    /// Used by TransactionListView and other MainActor UI components.
    nonisolated static func groupByDayObjects(
        _ transactions: [Transaction],
        rates: [String: Double],
        targetCurrency: String,
        sortAscending: Bool = false
    ) -> [DailyTransactionSection] {
        // Group by start of day
        let grouped = Dictionary(grouping: transactions) { txn -> Date in
            Calendar.current.startOfDay(for: txn.date)
        }
        
        let sortedKeys = grouped.keys.sorted(by: { sortAscending ? $0 < $1 : $0 > $1 })
        
        return sortedKeys.map { date in
            let txns = grouped[date] ?? []
            let sortedTxns = txns.sorted { t1, t2 in
                sortAscending ? t1.date < t2.date : t1.date > t2.date
            }
            let dailyFlow = calculateDailyFlow(sortedTxns, rates: rates, targetCurrency: targetCurrency)
            return DailyTransactionSection(date: date, transactions: sortedTxns, dailyTotal: dailyFlow)
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
    
    /// Calculates the sum of a list of transactions in `targetCurrency`, excluding any that are marked with `excludeFromReports`.
    nonisolated static func calculateTotal(
        _ transactions: [Transaction],
        rates: [String: Double],
        targetCurrency: String,
        typeFilter: TransactionType? = nil
    ) -> Decimal {
        if let typeFilter = typeFilter {
            let totals = calculateTotals(transactions, rates: rates, targetCurrency: targetCurrency)
            switch typeFilter {
            case .income:
                return totals.income
            case .expense:
                return totals.expense
            case .transfer:
                return transactions.reduce(Decimal.zero) { sum, txn in
                    guard !txn.excludeFromReports, txn.type == .transfer else { return sum }
                    let amount = convert(amount: txn.amount, from: txn.currencyCode, to: targetCurrency, rates: rates)
                    return sum + amount
                }
            case .adjustment:
                return transactions.reduce(Decimal.zero) { sum, txn in
                    guard !txn.excludeFromReports, txn.type == .adjustment else { return sum }
                    let amount = convert(amount: txn.amount, from: txn.currencyCode, to: targetCurrency, rates: rates)
                    return sum + amount
                }
            }
        }
        
        return transactions.reduce(Decimal.zero) { sum, txn in
            guard !txn.excludeFromReports else { return sum }
            let amount = convert(amount: txn.amount, from: txn.currencyCode, to: targetCurrency, rates: rates)
            return sum + amount
        }
    }
    
    /// Helper for currency conversion
    nonisolated private static func convert(amount: Decimal, from source: String, to target: String, rates: [String: Double]) -> Decimal {
        CurrencyManager.convert(amount: amount, from: source, to: target, rates: rates)
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
                    txn.event == nil &&
                    (txn.sourceWallet?.id == walletId || txn.destinationWallet?.id == walletId)
                },
                sortBy: sortDescriptors
            )
        } else if excludeArchivedWallets {
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { txn in
                    txn.date >= start && txn.date < end &&
                    txn.event == nil &&
                    txn.sourceWallet?.isArchived != true
                },
                sortBy: sortDescriptors
            )
        } else {
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { txn in
                    txn.date >= start && txn.date < end &&
                    txn.event == nil
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
    /// Pass `walletIds` for multi-wallet filtering; empty set means all wallets.
    nonisolated static func fetchAndProcess(
        context: ModelContext,
        startDate: Date,
        endDate: Date,
        walletId: UUID? = nil,
        walletIds: Set<UUID> = [],
        rates: [String: Double],
        targetCurrency: String,
        searchText: String? = nil,
        sortOption: TransactionSortOption = .newestFirst,
        calculateReferenceLine: Bool = false
    ) -> ProcessedTransactionDataID {
        // Resolve effective wallet filter: walletIds takes precedence over legacy walletId.
        let effectiveWalletIds: Set<UUID>
        if !walletIds.isEmpty {
            effectiveWalletIds = walletIds
        } else if let id = walletId {
            effectiveWalletIds = [id]
        } else {
            effectiveWalletIds = []
        }

        // For the predicate, use a single ID when possible (efficient index scan).
        let descriptorWalletId: UUID? = effectiveWalletIds.count == 1 ? effectiveWalletIds.first : nil

        let sortDescending = sortOption != .oldestFirst
        let descriptor = makeDescriptor(
            startDate: startDate,
            endDate: endDate,
            walletId: descriptorWalletId,
            sortDescending: sortDescending
        )

        do {
            var transactions = try context.fetch(descriptor)

            // Multi-wallet post-filter: when more than one wallet is selected, the predicate
            // fetches all wallets (descriptorWalletId is nil), so we filter in memory.
            if effectiveWalletIds.count > 1 {
                transactions = transactions.filter {
                    effectiveWalletIds.contains($0.sourceWallet?.id ?? UUID()) ||
                    effectiveWalletIds.contains($0.destinationWallet?.id ?? UUID())
                }
            }

            // Apply search filter in-memory
            if let searchText = searchText?.trimmingCharacters(in: .whitespacesAndNewlines), !searchText.isEmpty {
                transactions = transactions.filter { txn in
                    let noteMatch = txn.note?.localizedCaseInsensitiveContains(searchText) ?? false
                    let categoryMatch = txn.category?.name.localizedCaseInsensitiveContains(searchText) ?? false
                    return noteMatch || categoryMatch
                }
            }

            // Perform in-memory sorting
            switch sortOption {
            case .newestFirst:
                transactions.sort { $0.date > $1.date }
            case .oldestFirst:
                transactions.sort { $0.date < $1.date }
            case .highestAmount:
                transactions.sort { t1, t2 in
                    let a1 = convert(amount: t1.amount, from: t1.currencyCode, to: targetCurrency, rates: rates)
                    let a2 = convert(amount: t2.amount, from: t2.currencyCode, to: targetCurrency, rates: rates)
                    if a1 == a2 {
                        return t1.date > t2.date
                    }
                    return a1 > a2
                }
            case .lowestAmount:
                transactions.sort { t1, t2 in
                    let a1 = convert(amount: t1.amount, from: t1.currencyCode, to: targetCurrency, rates: rates)
                    let a2 = convert(amount: t2.amount, from: t2.currencyCode, to: targetCurrency, rates: rates)
                    if a1 == a2 {
                        return t1.date > t2.date
                    }
                    return a1 < a2
                }
            }

            let totals = calculateTotals(transactions, rates: rates, targetCurrency: targetCurrency)
            let sections = groupByDay(transactions, rates: rates, targetCurrency: targetCurrency, sortAscending: sortOption == .oldestFirst)
            let sortedIds = transactions.map { $0.persistentModelID }

            let referenceLine: [Decimal]
            if calculateReferenceLine {
                referenceLine = calculatePreviousPeriodCumulative(
                    context: context,
                    startDate: startDate,
                    endDate: endDate,
                    walletIds: effectiveWalletIds,
                    rates: rates,
                    targetCurrency: targetCurrency
                )
            } else {
                referenceLine = []
            }

            return ProcessedTransactionDataID(
                incomeTotal: totals.income,
                expenseTotal: totals.expense,
                dailySections: sections,
                sortedTransactionIds: sortedIds,
                previousPeriodCumulative: referenceLine
            )
        } catch {
            return ProcessedTransactionDataID(
                incomeTotal: 0,
                expenseTotal: 0,
                dailySections: [],
                sortedTransactionIds: [],
                previousPeriodCumulative: []
            )
        }
    }
    
    /// Calculates the day-by-day cumulative expense of the previous period (same range shifted back by 1 month).
    nonisolated static func calculatePreviousPeriodCumulative(
        context: ModelContext,
        startDate: Date,
        endDate: Date,
        walletId: UUID? = nil,
        walletIds: Set<UUID> = [],
        rates: [String: Double],
        targetCurrency: String
    ) -> [Decimal] {
        // Resolve effective filter (walletIds takes precedence).
        let effectiveWalletIds: Set<UUID>
        if !walletIds.isEmpty {
            effectiveWalletIds = walletIds
        } else if let id = walletId {
            effectiveWalletIds = [id]
        } else {
            effectiveWalletIds = []
        }

        let calendar = Calendar.current

        // Shift the selected range back by exactly 1 month
        guard let refStartDate = calendar.date(byAdding: .month, value: -1, to: startDate),
              let refEndDate = calendar.date(byAdding: .month, value: -1, to: endDate) else {
            return []
        }

        let descriptorWalletId: UUID? = effectiveWalletIds.count == 1 ? effectiveWalletIds.first : nil
        let descriptor = makeDescriptor(
            startDate: refStartDate,
            endDate: refEndDate,
            walletId: descriptorWalletId,
            sortDescending: false, // Chronological
            excludeArchivedWallets: true
        )

        do {
            var transactions = try context.fetch(descriptor)

            if effectiveWalletIds.count > 1 {
                transactions = transactions.filter {
                    effectiveWalletIds.contains($0.sourceWallet?.id ?? UUID()) ||
                    effectiveWalletIds.contains($0.destinationWallet?.id ?? UUID())
                }
            }
            
            let expenseTransactions = transactions.filter { txn in
                !txn.excludeFromReports && (txn.type == .expense || (txn.type == .adjustment && txn.amount < 0))
            }
            
            let refStartDay = calendar.startOfDay(for: refStartDate)
            let refEndDay = calendar.startOfDay(for: refEndDate)
            let components = calendar.dateComponents([.day], from: refStartDay, to: refEndDay)
            let daysInRefPeriod = max(1, (components.day ?? 0) + 1)
            
            var dailyExpenses = [Decimal](repeating: 0, count: daysInRefPeriod)
            
            for txn in expenseTransactions {
                let txnDayStart = calendar.startOfDay(for: txn.date)
                let dayOffset = calendar.dateComponents([.day], from: refStartDay, to: txnDayStart).day ?? 0
                let idx = max(0, min(daysInRefPeriod - 1, dayOffset))
                let converted = CurrencyManager.convert(amount: txn.amount, from: txn.currencyCode, to: targetCurrency, rates: rates)
                dailyExpenses[idx] += abs(converted)
            }
            
            var cumulative: [Decimal] = []
            var runningTotal: Decimal = 0
            for amt in dailyExpenses {
                runningTotal += amt
                cumulative.append(runningTotal)
            }
            
            // Align to current period length day-by-day
            let startDay = calendar.startOfDay(for: startDate)
            let endDay = calendar.startOfDay(for: endDate)
            let currentComponents = calendar.dateComponents([.day], from: startDay, to: endDay)
            let daysInCurrentPeriod = max(1, (currentComponents.day ?? 0) + 1)
            
            var referenceLine: [Decimal] = []
            for d in 0..<daysInCurrentPeriod {
                if cumulative.isEmpty {
                    referenceLine.append(0)
                } else {
                    let idx = min(d, cumulative.count - 1)
                    referenceLine.append(cumulative[idx])
                }
            }
            
            return referenceLine
        } catch {
            #if DEBUG
            print("Error fetching previous period data: \(error)")
            #endif
            return []
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
    let sortedTransactionIds: [PersistentIdentifier]
    let previousPeriodCumulative: [Decimal]
}

/// Helper struct for MainActor UI
struct DailyTransactionSection: Identifiable {
    var id: Date { date }
    let date: Date
    let transactions: [Transaction]
    let dailyTotal: Decimal
}
