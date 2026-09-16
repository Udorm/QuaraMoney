import Foundation
import SwiftData

/// One calendar month of recurring activity, as the Upcoming tab shows it:
/// what's due right now, what's still scheduled, and what was already posted.
///
/// The progress totals are derived from the very same occurrences and
/// transactions as those lists, so the card and the sections always add up.
struct RecurringMonthSummary {
    struct Totals: Equatable {
        var expense: Decimal = 0
        var income: Decimal = 0

        mutating func add(_ amount: Decimal, as type: TransactionType) {
            if type == .expense {
                expense += amount
            } else if type == .income {
                income += amount
            }
        }
    }

    /// A rule with at least one occurrence due today or earlier.
    struct DueItem: Identifiable {
        let rule: RecurringRule
        let pendingCount: Int
        var id: PersistentIdentifier { rule.persistentModelID }
    }

    /// A still-scheduled occurrence of a rule after today.
    struct Occurrence: Identifiable {
        let rule: RecurringRule
        let date: Date
        var id: String { "\(rule.id.uuidString)|\(date.timeIntervalSinceReferenceDate)" }
    }

    let monthStart: Date
    let isCurrentMonth: Bool
    /// Only populated for the current month — due items are about *now*.
    let due: [DueItem]
    let upcoming: [Occurrence]
    let paid: [Transaction]
    let paidTotals: Totals
    /// Paid plus every unposted occurrence dated inside the month (including
    /// this month's overdue ones; arrears from earlier months are excluded).
    let expectedTotals: Totals
    let upcomingTotals: Totals

    var dueOccurrenceCount: Int { due.reduce(0) { $0 + $1.pendingCount } }

    /// - Parameters:
    ///   - rules: Non-deleted rules. Paused ones never contribute.
    ///   - transactions: Candidates; only non-deleted, recurring ones dated in
    ///     the month count as paid.
    static func build(
        rules: [RecurringRule],
        transactions: [Transaction],
        monthStart: Date,
        now: Date = Date(),
        rates: [String: Double],
        currency: String,
        calendar: Calendar = .current
    ) -> RecurringMonthSummary {
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let month = monthStart..<monthEnd
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now

        func converted(_ amount: Decimal, from code: String) -> Decimal {
            CurrencyManager.convert(amount: amount, from: code, to: currency, rates: rates)
        }

        var expected = Totals()
        var upcomingTotals = Totals()
        var upcoming: [Occurrence] = []
        for rule in rules where rule.deletedAt == nil && rule.isActive {
            let value = converted(rule.amount, from: rule.currencyCode)
            for date in RecurringRuleService.dueDates(for: rule, in: month) {
                expected.add(value, as: rule.type)
                // Today and earlier belong to the Due section, which lists the rule itself.
                guard date >= tomorrowStart else { continue }
                upcoming.append(Occurrence(rule: rule, date: date))
                upcomingTotals.add(value, as: rule.type)
            }
        }
        upcoming.sort { ($0.date, $0.rule.name) < ($1.date, $1.rule.name) }

        let paid = transactions
            .filter { $0.deletedAt == nil && $0.recurringRule != nil && month.contains($0.date) }
            .sorted { $0.date < $1.date }
        var paidTotals = Totals()
        for txn in paid {
            paidTotals.add(converted(txn.amount, from: txn.currencyCode), as: txn.type)
        }
        expected.expense += paidTotals.expense
        expected.income += paidTotals.income

        let isCurrentMonth = month.contains(now)
        let due: [DueItem] = isCurrentMonth
            ? rules
                .filter { RecurringRuleService.isDue($0, asOf: now) }
                .sorted { $0.nextDueDate < $1.nextDueDate }
                .map { DueItem(rule: $0, pendingCount: RecurringRuleService.pendingOccurrenceCount(for: $0, asOf: now)) }
            : []

        return RecurringMonthSummary(
            monthStart: monthStart,
            isCurrentMonth: isCurrentMonth,
            due: due,
            upcoming: upcoming,
            paid: paid,
            paidTotals: paidTotals,
            expectedTotals: expected,
            upcomingTotals: upcomingTotals
        )
    }
}
