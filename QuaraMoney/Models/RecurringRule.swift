import SwiftData
import Foundation

@Model
final class RecurringRule {
    var id: UUID

    // MARK: - Sync metadata (Supabase migration)
    var syncUserID: UUID?
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var needsSync: Bool = true

    var name: String // e.g., "Netflix Subscription"
    var amount: Decimal
    var currencyCode: String

    /// Whether each generated transaction is income or expense. Only `.income`
    /// and `.expense` are valid — transfers/adjustments are not recurring.
    /// Defaulted to `.expense` so legacy rows migrate lightweight.
    var type: TransactionType = TransactionType.expense

    var frequency: Frequency
    /// How many frequency-units between occurrences. `1` = every period (the
    /// default), `2` = every other period, etc. Combined with `frequency` this
    /// gives patterns like "every 2 weeks" or "every 6 months".
    var interval: Int = 1
    var startDate: Date
    var nextDueDate: Date

    /// Optional last day the rule may generate an occurrence. `nil` = runs
    /// forever until paused or deleted. An occurrence is generated only while
    /// `nextDueDate <= endDate` (or `endDate == nil`).
    var endDate: Date?

    /// When false the rule is paused: no occurrences are generated and no
    /// due-date reminders fire. Existing posted transactions are unaffected.
    var isActive: Bool = true

    /// Whether to schedule a local notification on each `nextDueDate`.
    var remindersEnabled: Bool = true

    // Relationships
    var wallet: Wallet?
    var category: Category?
    // `.nullify` (not `.cascade`): deleting a rule must NOT delete the
    // historical transactions it generated — those are real ledger entries.
    // The transactions simply lose their back-link to the deleted rule.
    //
    // The explicit `inverse:` is load-bearing: without it SwiftData treats this
    // and `Transaction.recurringRule` as two independent relationships with
    // separate backing stores. The posting path only ever sets the to-one side
    // (`txn.recurringRule = rule`), so this array would otherwise stay empty and
    // the rule-detail screen would show no (or only incidentally-linked)
    // transactions. Declaring the inverse makes both sides share the single
    // `Transaction.recurringRule` foreign key.
    @Relationship(deleteRule: .nullify, inverse: \Transaction.recurringRule) var generatedTransactions: [Transaction]?

    init(name: String, amount: Decimal, currencyCode: String, frequency: Frequency, interval: Int = 1, startDate: Date, type: TransactionType = .expense) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.currencyCode = currencyCode
        self.type = type
        self.frequency = frequency
        self.interval = interval
        self.startDate = startDate
        self.nextDueDate = startDate
    }
}
