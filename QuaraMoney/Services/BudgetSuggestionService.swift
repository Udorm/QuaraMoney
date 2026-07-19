import Foundation
import SwiftData

nonisolated struct BudgetSuggestion: Sendable, Equatable {
    let suggestedAmount: Decimal?
    let averageSpending: Decimal
    let bucketAmounts: [Decimal]
    let transactionCount: Int
    let confidence: SuggestionConfidence
    let periodType: BudgetPeriodType
    let excludedForMissingRate: Int

    var hasData: Bool { suggestedAmount != nil }
}

nonisolated enum SuggestionConfidence: String, Sendable, Equatable {
    case high, medium, low, noData

    nonisolated func downgraded() -> SuggestionConfidence {
        switch self {
        case .high: return .medium
        case .medium, .low: return .low
        case .noData: return .noData
        }
    }
}

/// Three-completed-period budget suggestions computed on a private ModelContext.
@MainActor
final class BudgetSuggestionEngine {
    private let container: ModelContainer

    init(modelContext: ModelContext) { container = modelContext.container }
    init(container: ModelContainer) { self.container = container }

    func suggestion(
        targetKind: BudgetTargetKind,
        categoryIDs: Set<UUID>,
        periodType: BudgetPeriodType,
        currencyCode: String,
        rates: [String: Double],
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> BudgetSuggestion? {
        guard periodType != .custom else { return nil }
        let container = container
        return await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            return Self.compute(context: context, targetKind: targetKind,
                                categoryIDs: categoryIDs, periodType: periodType,
                                currencyCode: currencyCode, rates: rates,
                                now: now, calendar: calendar)
        }.value
    }

    nonisolated static func compute(
        context: ModelContext,
        targetKind: BudgetTargetKind,
        categoryIDs: Set<UUID>,
        periodType: BudgetPeriodType,
        currencyCode: String,
        rates: [String: Double],
        now: Date,
        calendar: Calendar
    ) -> BudgetSuggestion? {
        guard periodType != .custom else { return nil }
        let currentStart = periodType.currentPeriodRange(containing: now, calendar: calendar).start
        var ranges: [(start: Date, end: Date)] = []
        var cursor = currentStart
        for _ in 0..<3 {
            let priorDate = calendar.date(byAdding: .second, value: -1, to: cursor) ?? cursor
            let range = periodType.currentPeriodRange(containing: priorDate, calendar: calendar)
            ranges.append(range)
            cursor = range.start
        }
        ranges.reverse()
        guard let earliest = ranges.first?.start else { return nil }

        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.deletedAt == nil && $0.event == nil &&
                !$0.excludeFromReports && $0.date >= earliest && $0.date < currentStart }
        )
        let transactions = (try? context.fetch(descriptor)) ?? []
        var buckets = Array(repeating: Decimal.zero, count: 3)
        var count = 0
        var missingRateCount = 0

        for transaction in transactions where transaction.type == .expense {
            if targetKind == .categories {
                guard let categoryID = transaction.category?.id, categoryIDs.contains(categoryID) else { continue }
            }
            guard let bucket = ranges.firstIndex(where: { transaction.date >= $0.start && transaction.date < $0.end }) else { continue }
            guard let amount = converted(transaction.amount, from: transaction.currencyCode,
                                         to: currencyCode, rates: rates) else {
                missingRateCount += 1
                continue
            }
            buckets[bucket] += amount
            count += 1
        }

        let average = buckets.reduce(Decimal.zero, +) / Decimal(3)
        guard average > 0 else {
            return BudgetSuggestion(suggestedAmount: nil, averageSpending: 0,
                                    bucketAmounts: buckets, transactionCount: count,
                                    confidence: .noData, periodType: periodType,
                                    excludedForMissingRate: missingRateCount)
        }
        let mean = NSDecimalNumber(decimal: average).doubleValue
        let variance = buckets.reduce(0.0) { result, amount in
            let delta = NSDecimalNumber(decimal: amount).doubleValue - mean
            return result + delta * delta
        } / 3
        let coefficient = mean > 0 ? sqrt(variance) / mean : 1
        var confidence: SuggestionConfidence
        if count >= 9 && coefficient < 0.25 { confidence = .high }
        else if count >= 4 && coefficient < 0.6 { confidence = .medium }
        else { confidence = .low }
        if missingRateCount > 0 { confidence = confidence.downgraded() }
        return BudgetSuggestion(suggestedAmount: average * Decimal(string: "1.10")!,
                                averageSpending: average, bucketAmounts: buckets,
                                transactionCount: count, confidence: confidence,
                                periodType: periodType, excludedForMissingRate: missingRateCount)
    }

    nonisolated private static func converted(_ amount: Decimal, from source: String,
                                              to target: String, rates: [String: Double]) -> Decimal? {
        guard source != target else { return amount }
        guard let sourceRate = rates[source], let targetRate = rates[target], sourceRate > 0, targetRate > 0 else { return nil }
        return amount / Decimal(sourceRate) * Decimal(targetRate)
    }
}
