import Foundation
import SwiftData

/// Helper to process Analysis data in background
struct AnalysisDataProcessor {
    
    // MARK: - Types
    
    struct AnalysisResult: Sendable {
        let totalIncome: Decimal
        let totalExpense: Decimal
        let savingsRate: Double
        let dailyStats: [DailyStatData]
        let categoryStats: [CategoryStatData]
    }
    
    struct DailyStatData: Identifiable, Sendable {
        var id: Date { date }
        let date: Date
        let income: Decimal
        let expense: Decimal
    }
    
    struct CategoryStatData: Identifiable, Sendable {
        let id: UUID
        let name: String
        let icon: String
        let colorHex: String
        let amount: Decimal
    }
    
    // MARK: - Processing
    
    nonisolated static func processTransactions(
        context: ModelContext,
        startDate: Date,
        endDate: Date,
        walletId: UUID?,
        grouping: TimeGrouping,
        transactionType: TransactionTypeFilter,
        rates: [String: Double],
        targetCurrency: String
    ) -> AnalysisResult {
        
        let descriptor = TransactionProcessor.makeDescriptor(
            startDate: startDate,
            endDate: endDate,
            walletId: walletId,
            sortDescending: false 
        )
        
        do {
            let transactions = try context.fetch(descriptor)
            
            var totalIncome: Decimal = 0
            var totalExpense: Decimal = 0
            
            var rawChartData: [Date: (income: Decimal, expense: Decimal)] = [:]
            var rawExpenseCategoryData: [UUID: (amount: Decimal, name: String, icon: String, color: String)] = [:]
            var rawIncomeCategoryData: [UUID: (amount: Decimal, name: String, icon: String, color: String)] = [:]
            
            let calendar = Calendar.current
            
            for txn in transactions {
                if txn.excludeFromReports { continue }
                
                // Convert Amount
                let amount = convert(amount: txn.amount, from: txn.currencyCode, to: targetCurrency, rates: rates)
                
                // Grouping Logic
                let chartDate: Date
                switch grouping {
                case .hour:
                    chartDate = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: txn.date)) ?? calendar.startOfDay(for: txn.date)
                case .day:
                    chartDate = calendar.startOfDay(for: txn.date)
                case .week:
                    let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: txn.date)
                    chartDate = calendar.date(from: components) ?? calendar.startOfDay(for: txn.date)
                case .month:
                    chartDate = calendar.date(from: calendar.dateComponents([.year, .month], from: txn.date)) ?? calendar.startOfDay(for: txn.date)
                case .year:
                    chartDate = calendar.date(from: calendar.dateComponents([.year], from: txn.date)) ?? calendar.startOfDay(for: txn.date)
                }
                
                if txn.type == .income {
                    totalIncome += amount
                    
                    var current = rawChartData[chartDate] ?? (0, 0)
                    current.income += amount
                    rawChartData[chartDate] = current
                    
                    if let cat = txn.category {
                        let existing = rawIncomeCategoryData[cat.id]?.amount ?? 0
                        rawIncomeCategoryData[cat.id] = (existing + amount, cat.name, cat.icon, cat.colorHex)
                    }
                    
                } else if txn.type == .expense {
                    totalExpense += amount
                    
                    var current = rawChartData[chartDate] ?? (0, 0)
                    current.expense += amount
                    rawChartData[chartDate] = current
                    
                    if let cat = txn.category {
                        let existing = rawExpenseCategoryData[cat.id]?.amount ?? 0
                        rawExpenseCategoryData[cat.id] = (existing + amount, cat.name, cat.icon, cat.colorHex)
                    }
                }
            }
            
            // Savings Rate
            let savingsRate: Double
            if totalIncome > 0 {
                let savings = totalIncome - totalExpense
                savingsRate = Double(truncating: savings as NSNumber) / Double(truncating: totalIncome as NSNumber)
            } else {
                savingsRate = 0
            }
            
            // Daily Stats
            let dailyStats = rawChartData.map { (date, values) in
                DailyStatData(date: date, income: values.income, expense: values.expense)
            }.sorted { $0.date < $1.date }
            
            // Category Stats
            let categorySource = transactionType == .expense ? rawExpenseCategoryData : rawIncomeCategoryData
            let categoryStats = categorySource.map { (id, data) in
                CategoryStatData(id: id, name: data.name, icon: data.icon, colorHex: data.color, amount: data.amount)
            }.sorted { $0.amount > $1.amount }
            
            return AnalysisResult(
                totalIncome: totalIncome,
                totalExpense: totalExpense,
                savingsRate: savingsRate,
                dailyStats: dailyStats,
                categoryStats: categoryStats
            )
            
        } catch {
            return AnalysisResult(totalIncome: 0, totalExpense: 0, savingsRate: 0, dailyStats: [], categoryStats: [])
        }
    }
    
    // Helper duplicate from TransactionProcessor to avoid dependency/MainActor issues if any
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
}
