import Foundation
import SwiftData

// MARK: - Decimal → Double helper for Swift Charts

extension Decimal {
    /// Lossy conversion to `Double` for plotting. Charts requires `Double`/`Plottable`;
    /// money math stays in `Decimal` everywhere else per project convention.
    var doubleValue: Double { Double(truncating: self as NSDecimalNumber) }
}

/// Background aggregator for the **Pro analytics dashboard**.
///
/// Mirrors `AnalysisDataProcessor`'s threading model: a `nonisolated static` entry point that
/// runs inside a detached `ModelContext` and returns a `Sendable` value type. All currency is
/// converted to the user's preferred currency at read time using per-call `rates`.
struct ProAnalyticsProcessor {

    // MARK: - Result Types

    struct Result: Sendable {
        // Current period totals
        let income: Decimal
        let expense: Decimal
        let transactionCount: Int

        // Previous comparable period totals (for period-over-period deltas)
        let prevIncome: Decimal
        let prevExpense: Decimal

        // Net worth across the (optionally filtered) wallets, "as of now"
        let netWorth: Decimal

        // Cash flow per time bucket (both income & expense, regardless of selected type)
        let flowBuckets: [FlowBucket]

        // Breakdown for the selected transaction type
        let categories: [CategorySlice]
        let merchants: [MerchantStat]
        let weekdayTotals: [WeekdayStat]
        let dailySpend: [DaySpend]

        // Highlights
        let avgDailySpend: Decimal
        /// Projected end-of-period total for the selected type, when the period contains "now".
        let projectedTotal: Decimal?

        var net: Decimal { income - expense }
        var prevNet: Decimal { prevIncome - prevExpense }

        static let empty = Result(
            income: 0, expense: 0, transactionCount: 0,
            prevIncome: 0, prevExpense: 0, netWorth: 0,
            flowBuckets: [], categories: [], merchants: [],
            weekdayTotals: [], dailySpend: [],
            avgDailySpend: 0, projectedTotal: nil
        )
    }

    struct FlowBucket: Identifiable, Sendable {
        var id: Date { date }
        let date: Date
        let income: Decimal
        let expense: Decimal
        var net: Decimal { income - expense }
    }

    struct CategorySlice: Identifiable, Sendable {
        let id: UUID
        let name: String
        let icon: String
        let colorHex: String
        let amount: Decimal
        let fraction: Double // 0...1 share of the selected-type total
    }

    struct MerchantStat: Identifiable, Sendable {
        let id: String
        let name: String
        let amount: Decimal
        let count: Int
    }

    struct WeekdayStat: Identifiable, Sendable {
        var id: Int { weekday }
        let weekday: Int // 1 = Sunday ... 7 = Saturday (Calendar.current)
        let total: Decimal
        let occurrences: Int // number of that weekday observed in the range
        var average: Decimal { occurrences > 0 ? total / Decimal(occurrences) : 0 }
    }

    struct DaySpend: Identifiable, Sendable {
        var id: Date { date }
        let date: Date
        let amount: Decimal
    }

    // MARK: - Processing

    nonisolated static func process(
        context: ModelContext,
        startDate: Date,
        endDate: Date,
        prevStartDate: Date,
        prevEndDate: Date,
        filter: DashboardFilter,
        grouping: TimeGrouping,
        rates: [String: Double],
        targetCurrency: String,
        now: Date
    ) -> Result {
        let calendar = Calendar.current
        let selectedType: TransactionType = (filter.transactionType == .income) ? .income : .expense

        // Fetch the whole period (no wallet predicate — multi-wallet membership is filtered
        // in-memory below) ascending so daily series stay ordered.
        let descriptor = TransactionProcessor.makeDescriptor(
            startDate: startDate, endDate: endDate, walletId: nil, sortDescending: false
        )
        let prevDescriptor = TransactionProcessor.makeDescriptor(
            startDate: prevStartDate, endDate: prevEndDate, walletId: nil, sortDescending: false
        )

        let transactions = (try? context.fetch(descriptor)) ?? []
        let prevTransactions = (try? context.fetch(prevDescriptor)) ?? []

        var income: Decimal = 0
        var expense: Decimal = 0
        var count = 0

        var flow: [Date: (income: Decimal, expense: Decimal)] = [:]
        var categoryAgg: [UUID: (amount: Decimal, name: String, icon: String, color: String)] = [:]
        var merchantAgg: [String: (amount: Decimal, name: String, count: Int)] = [:]
        var weekdayAgg: [Int: Decimal] = [:]
        var dayAgg: [Date: Decimal] = [:]

        for txn in transactions {
            guard txn.type == .income || txn.type == .expense else { continue }

            let amount = convert(txn.amount, from: txn.currencyCode, to: targetCurrency, rates: rates)
            guard passesFilters(txn, convertedAmount: amount, filter: filter) else { continue }

            let bucketDate = bucketKey(for: txn.date, grouping: grouping, calendar: calendar)

            if txn.type == .income {
                income += amount
                var b = flow[bucketDate] ?? (0, 0); b.income += amount; flow[bucketDate] = b
            } else {
                expense += amount
                var b = flow[bucketDate] ?? (0, 0); b.expense += amount; flow[bucketDate] = b
            }
            count += 1

            // The breakdown sections (category / merchant / weekday / daily) reflect the
            // currently-selected transaction type so the whole dashboard is consistent.
            guard txn.type == selectedType else { continue }

            if let cat = txn.category {
                let prev = categoryAgg[cat.id]?.amount ?? 0
                categoryAgg[cat.id] = (prev + amount, cat.name, cat.icon, cat.colorHex)
            }

            if let loc = txn.location {
                let name = loc.displayName ?? loc.shortAddress ?? loc.locality ?? loc.fullAddress
                if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                    let key = name.lowercased()
                    let existing = merchantAgg[key]
                    merchantAgg[key] = (
                        (existing?.amount ?? 0) + amount,
                        existing?.name ?? name,
                        (existing?.count ?? 0) + 1
                    )
                }
            }

            let weekday = calendar.component(.weekday, from: txn.date)
            weekdayAgg[weekday, default: 0] += amount

            let day = calendar.startOfDay(for: txn.date)
            dayAgg[day, default: 0] += amount
        }

        // Previous-period totals (only need income/expense sums for deltas) — same filters applied.
        var prevIncome: Decimal = 0
        var prevExpense: Decimal = 0
        for txn in prevTransactions {
            guard txn.type == .income || txn.type == .expense else { continue }
            let amount = convert(txn.amount, from: txn.currencyCode, to: targetCurrency, rates: rates)
            guard passesFilters(txn, convertedAmount: amount, filter: filter) else { continue }
            if txn.type == .income { prevIncome += amount }
            else if txn.type == .expense { prevExpense += amount }
        }

        // Flow buckets, sorted ascending.
        let flowBuckets = flow
            .map { FlowBucket(date: $0.key, income: $0.value.income, expense: $0.value.expense) }
            .sorted { $0.date < $1.date }

        // Categories, sorted by amount desc, with share fraction.
        let selectedTotal = (selectedType == .income) ? income : expense
        let categories = categoryAgg
            .map { id, data -> CategorySlice in
                let fraction = selectedTotal > 0 ? (data.amount / selectedTotal).doubleValue : 0
                return CategorySlice(id: id, name: data.name, icon: data.icon, colorHex: data.color, amount: data.amount, fraction: fraction)
            }
            .sorted { $0.amount > $1.amount }

        // Merchants/places, top by amount.
        let merchants = merchantAgg
            .map { MerchantStat(id: $0.key, name: $0.value.name, amount: $0.value.amount, count: $0.value.count) }
            .sorted { $0.amount > $1.amount }

        // Weekday pattern — count weekday occurrences across the range for averages.
        let weekdayOccurrences = countWeekdayOccurrences(start: startDate, end: endDate, calendar: calendar)
        let weekdayTotals = (1...7).map { wd in
            WeekdayStat(weekday: wd, total: weekdayAgg[wd] ?? 0, occurrences: weekdayOccurrences[wd] ?? 0)
        }

        // Daily spend series for the heatmap.
        let dailySpend = dayAgg
            .map { DaySpend(date: $0.key, amount: $0.value) }
            .sorted { $0.date < $1.date }

        // Net worth across the relevant wallets.
        let netWorth = computeNetWorth(context: context, walletIds: filter.walletIds, rates: rates, targetCurrency: targetCurrency)

        // Average daily spend over elapsed days within the period.
        let elapsedEnd = min(endDate, now)
        let totalDays = max(1, daysBetween(startDate, endDate, calendar: calendar))
        let elapsedDays = max(1, min(totalDays, daysBetween(startDate, elapsedEnd, calendar: calendar)))
        let avgDailySpend = selectedTotal / Decimal(elapsedDays)

        // Projection: only meaningful when the period is currently in progress.
        var projectedTotal: Decimal? = nil
        if now >= startDate && now < endDate && elapsedDays < totalDays {
            projectedTotal = avgDailySpend * Decimal(totalDays)
        }

        return Result(
            income: income,
            expense: expense,
            transactionCount: count,
            prevIncome: prevIncome,
            prevExpense: prevExpense,
            netWorth: netWorth,
            flowBuckets: flowBuckets,
            categories: categories,
            merchants: merchants,
            weekdayTotals: weekdayTotals,
            dailySpend: dailySpend,
            avgDailySpend: avgDailySpend,
            projectedTotal: projectedTotal
        )
    }

    // MARK: - Helpers

    nonisolated private static func bucketKey(for date: Date, grouping: TimeGrouping, calendar: Calendar) -> Date {
        switch grouping {
        case .hour:
            return calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: date)) ?? calendar.startOfDay(for: date)
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
        case .month:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
        case .year:
            return calendar.date(from: calendar.dateComponents([.year], from: date)) ?? calendar.startOfDay(for: date)
        }
    }

    nonisolated private static func daysBetween(_ start: Date, _ end: Date, calendar: Calendar) -> Int {
        let s = calendar.startOfDay(for: start)
        let e = calendar.startOfDay(for: end)
        return (calendar.dateComponents([.day], from: s, to: e).day ?? 0)
    }

    nonisolated private static func countWeekdayOccurrences(start: Date, end: Date, calendar: Calendar) -> [Int: Int] {
        var result: [Int: Int] = [:]
        var cursor = calendar.startOfDay(for: start)
        let limit = end
        var guardCounter = 0
        while cursor < limit && guardCounter < 4000 { // guardCounter caps multi-year ranges safely
            let wd = calendar.component(.weekday, from: cursor)
            result[wd, default: 0] += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            guardCounter += 1
        }
        return result
    }

    nonisolated private static func computeNetWorth(context: ModelContext, walletIds: Set<UUID>, rates: [String: Double], targetCurrency: String) -> Decimal {
        do {
            let wallets = try context.fetch(FetchDescriptor<Wallet>())
            let relevant = walletIds.isEmpty
                ? wallets.filter { !$0.isArchived }
                : wallets.filter { walletIds.contains($0.id) }
            return relevant.reduce(Decimal.zero) { total, wallet in
                total + convert(wallet.balance, from: wallet.currencyCode, to: targetCurrency, rates: rates)
            }
        } catch {
            return 0
        }
    }

    /// Applies the dashboard's wallet / category / amount / exclusion constraints to a single
    /// transaction. The transaction type is intentionally *not* checked here so income and
    /// expense totals (and the cash-flow chart) can both be tallied in one pass.
    nonisolated private static func passesFilters(_ txn: Transaction, convertedAmount: Decimal, filter: DashboardFilter) -> Bool {
        if txn.excludeFromReports && !filter.includeExcluded { return false }

        if !filter.walletIds.isEmpty {
            let sourceMatch = txn.sourceWallet.map { filter.walletIds.contains($0.id) } ?? false
            let destMatch = txn.destinationWallet.map { filter.walletIds.contains($0.id) } ?? false
            if !sourceMatch && !destMatch { return false }
        }

        if !filter.categoryIds.isEmpty {
            guard let categoryId = txn.category?.id, filter.categoryIds.contains(categoryId) else { return false }
        }

        if let minAmount = filter.minAmount, convertedAmount < minAmount { return false }
        if let maxAmount = filter.maxAmount, convertedAmount > maxAmount { return false }

        return true
    }

    nonisolated private static func convert(_ amount: Decimal, from source: String, to target: String, rates: [String: Double]) -> Decimal {
        CurrencyManager.convert(amount: amount, from: source, to: target, rates: rates)
    }
}
