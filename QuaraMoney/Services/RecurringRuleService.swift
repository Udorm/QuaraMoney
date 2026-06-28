import Foundation
import SwiftData

/// Drives recurring rules in **confirm-before-post** mode.
///
/// A rule no longer auto-creates transactions in the background. Instead it
/// advertises *due occurrences* (computed from `nextDueDate`, never
/// materialized) which the user reviews and either **posts** (creates a real
/// ledger transaction) or **skips** (advances the schedule without posting).
///
/// The only persisted schedule state is `RecurringRule.nextDueDate`, advanced
/// one period per user action. Posted transactions are independent ledger
/// entries — editing or deleting a rule never rewrites them (see Phase 1's
/// `.nullify` delete rule).
enum RecurringRuleService {

    // MARK: - Date math

    /// The next occurrence strictly after `current`.
    ///
    /// Monthly/yearly occurrences are **anchored to `startDate`** (computed as
    /// `startDate + n·period`) rather than stepped from the previous due date,
    /// so a rule whose start day is the 31st does not permanently drift to the
    /// 28th after passing through February. Daily/weekly step incrementally.
    static func nextOccurrence(after current: Date, startDate: Date, frequency: Frequency, interval: Int = 1) -> Date? {
        let step = max(1, interval)
        let cal = Calendar.current
        switch frequency {
        case .daily:
            return cal.date(byAdding: .day, value: step, to: current)
        case .weekly:
            return cal.date(byAdding: .weekOfYear, value: step, to: current)
        case .monthly:
            return anchoredNext(current: current, startDate: startDate, component: .month, step: step)
        case .yearly:
            return anchoredNext(current: current, startDate: startDate, component: .year, step: step)
        }
    }

    /// Anchored next occurrence: the smallest `startDate + n·component` that is
    /// strictly greater than `current`. The trailing `while` walks past any
    /// month-end clamping edge cases that could otherwise repeat a date and
    /// stall the schedule.
    private static func anchoredNext(current: Date, startDate: Date, component: Calendar.Component, step: Int = 1) -> Date? {
        let cal = Calendar.current
        let rawN = max(0, cal.dateComponents([component], from: startDate, to: current).value(for: component) ?? 0)
        // Round up to the next multiple of `step` that lands strictly after `current`.
        var n = ((rawN / step) + 1) * step
        var guardN = 0
        while let candidate = cal.date(byAdding: component, value: n, to: startDate),
              candidate <= current, guardN < 1200 {
            n += step
            guardN += 1
        }
        return cal.date(byAdding: component, value: n, to: startDate)
    }

    /// The first due date for a brand-new rule, or when resetting the schedule.
    /// If `startDate` is in the past, we advance to the first occurrence 
    /// **on or after today** — we never silently backfill historical occurrences 
    /// the user did not schedule, but we will surface a payment due today.
    static func firstDueDate(startDate: Date, frequency: Frequency, interval: Int = 1, asOf now: Date = Date()) -> Date {
        let todayStart = Calendar.current.startOfDay(for: now)
        var due = startDate
        var guardN = 0
        while due < todayStart, guardN < 10_000 {
            guard let next = nextOccurrence(after: due, startDate: startDate, frequency: frequency, interval: interval) else { break }
            due = next
            guardN += 1
        }
        return due
    }

    /// The due date a *resumed* rule should adopt: its current `nextDueDate` if
    /// still in the future, otherwise re-anchored forward to the next occurrence
    /// on/after today. Pausing means "skip the periods that elapse while paused",
    /// never "queue them up" — so resuming never resurfaces a backlog.
    static func resumedNextDueDate(for rule: RecurringRule, asOf now: Date = Date()) -> Date {
        let todayStart = Calendar.current.startOfDay(for: now)
        guard rule.nextDueDate < todayStart else { return rule.nextDueDate }
        return firstDueDate(startDate: rule.startDate, frequency: rule.frequency, interval: rule.interval, asOf: now)
    }

    // MARK: - Due detection (derived, never materialized)

    /// Whether the rule has an occurrence due today or earlier (and is active,
    /// not deleted, and not past its end date).
    static func isDue(_ rule: RecurringRule, asOf now: Date = Date()) -> Bool {
        guard rule.isActive, rule.deletedAt == nil else { return false }
        let cal = Calendar.current
        let tomorrowStart = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        guard rule.nextDueDate < tomorrowStart else { return false }      // due today or overdue
        if let end = rule.endDate, rule.nextDueDate > end { return false } // past end date
        return true
    }

    /// Active, non-deleted rules with at least one occurrence due now,
    /// soonest-due first. The end-date / day-boundary logic lives in `isDue`
    /// (in-memory) to sidestep SwiftData optional-Date predicate pitfalls.
    static func dueRules(asOf now: Date = Date(), in context: ModelContext) -> [RecurringRule] {
        let descriptor = FetchDescriptor<RecurringRule>(
            predicate: #Predicate { $0.isActive && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.nextDueDate)]
        )
        let rules = (try? context.fetch(descriptor)) ?? []
        return rules.filter { isDue($0, asOf: now) }
    }

    /// How many occurrences are currently due for a rule (≥ 1 when overdue
    /// across several periods). Used to drive "X due" / "Post all" affordances.
    static func pendingOccurrenceCount(for rule: RecurringRule, asOf now: Date = Date()) -> Int {
        guard rule.isActive, rule.deletedAt == nil else { return 0 }
        let cal = Calendar.current
        let tomorrowStart = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        var count = 0
        var due = rule.nextDueDate
        var guardN = 0
        while due < tomorrowStart, guardN < 1000 {
            if let end = rule.endDate, due > end { break }
            count += 1
            guard let next = nextOccurrence(after: due, startDate: rule.startDate, frequency: rule.frequency, interval: rule.interval) else { break }
            due = next
            guardN += 1
        }
        return count
    }

    // MARK: - Mutations (MainActor: touch CurrencyManager, balance cache, NotificationCenter)

    /// Post a single due occurrence: create the ledger transaction and advance
    /// the schedule by one period. `amount`/`date` override the rule defaults
    /// for this one occurrence (the rule itself is unchanged). Returns the
    /// created transaction, or `nil` if the rule has no wallet or the save fails.
    @MainActor
    @discardableResult
    static func post(rule: RecurringRule, amount: Decimal? = nil, date: Date? = nil, in context: ModelContext) -> Transaction? {
        guard let wallet = rule.wallet else { return nil }
        let txn = makeTransaction(for: rule, wallet: wallet,
                                  amount: amount ?? rule.amount,
                                  date: date ?? rule.nextDueDate,
                                  in: context)
        advanceNextDueDate(rule)
        touchForSync(rule)
        guard commit(context, invalidating: wallet) else { return nil }
        Task { await RecurringNotificationService.reschedule(for: rule) }
        return txn
    }

    /// Skip the next due occurrence without creating a transaction; advances
    /// the schedule by one period.
    @MainActor
    static func skip(rule: RecurringRule, in context: ModelContext) {
        advanceNextDueDate(rule)
        touchForSync(rule)
        if commit(context, invalidating: nil) {
            Task { await RecurringNotificationService.reschedule(for: rule) }
        }
    }

    /// Post every occurrence currently due for a rule (using the rule's default
    /// amount for each), with a single save. Returns the count posted.
    @MainActor
    @discardableResult
    static func postAllDue(rule: RecurringRule, asOf now: Date = Date(), in context: ModelContext) -> Int {
        guard let wallet = rule.wallet else { return 0 }
        var posted = 0
        var guardN = 0
        while isDue(rule, asOf: now), guardN < 1000 {
            _ = makeTransaction(for: rule, wallet: wallet, amount: rule.amount, date: rule.nextDueDate, in: context)
            advanceNextDueDate(rule)
            posted += 1
            guardN += 1
        }
        guard posted > 0 else { return 0 }
        touchForSync(rule)
        guard commit(context, invalidating: wallet) else { return 0 }
        Task { await RecurringNotificationService.reschedule(for: rule) }
        return posted
    }

    /// Skip every occurrence currently due for a rule, with a single save.
    @MainActor
    static func skipAllDue(rule: RecurringRule, asOf now: Date = Date(), in context: ModelContext) {
        var skipped = 0
        var guardN = 0
        while isDue(rule, asOf: now), guardN < 1000 {
            advanceNextDueDate(rule)
            skipped += 1
            guardN += 1
        }
        guard skipped > 0 else { return }
        touchForSync(rule)
        if commit(context, invalidating: nil) {
            Task { await RecurringNotificationService.reschedule(for: rule) }
        }
    }

    // MARK: - Private helpers

    /// Builds and inserts a transaction mirroring the canonical save path in
    /// `AddTransactionViewModel` (authoritative `storedRate`, parsed tags,
    /// wallet/category/rule links). Does **not** save — callers batch the save.
    @MainActor
    private static func makeTransaction(for rule: RecurringRule, wallet: Wallet, amount: Decimal, date: Date, in context: ModelContext) -> Transaction {
        let rate = walletExchangeRate(from: rule.currencyCode, to: wallet.currencyCode)
        let txn = Transaction(amount: amount, currencyCode: rule.currencyCode, date: date, type: rule.type, exchangeRate: rate)
        let note = L10n.Recurring.generatedNote(rule.name)
        txn.note = note
        txn.tags = TransactionTagParser.tags(in: note)
        txn.sourceWallet = wallet
        txn.category = rule.category
        txn.recurringRule = rule
        // Record the authoritative rate so this transaction's contribution to
        // wallet balances is deterministic and never recomputed at live rates.
        txn.storedRate = rate
        txn.updatedAt = Date()
        context.insert(txn)
        return txn
    }

    /// Rate convention matches `AddTransactionViewModel`: wallet currency units
    /// per 1 unit of the rule's currency (`walletRate / txnRate`).
    @MainActor
    private static func walletExchangeRate(from ruleCurrency: String, to walletCurrency: String) -> Decimal {
        guard ruleCurrency != walletCurrency else { return 1.0 }
        let manager = CurrencyManager.shared
        if let txnRate = manager.rates[ruleCurrency], let walletRate = manager.rates[walletCurrency], txnRate != 0 {
            return Decimal(walletRate / txnRate)
        }
        return 1.0
    }

    private static func advanceNextDueDate(_ rule: RecurringRule) {
        if let next = nextOccurrence(after: rule.nextDueDate, startDate: rule.startDate, frequency: rule.frequency, interval: rule.interval) {
            rule.nextDueDate = next
        }
    }

    private static func touchForSync(_ rule: RecurringRule) {
        rule.updatedAt = Date()
        rule.needsSync = true
    }

    /// Saves and broadcasts a data-update so live `@Query` views refresh; on a
    /// successful save also invalidates the affected wallet's balance cache.
    @MainActor
    private static func commit(_ context: ModelContext, invalidating wallet: Wallet?) -> Bool {
        do {
            try context.save()
            wallet?.invalidateBalanceCache()
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            return true
        } catch {
            #if DEBUG
            print("RecurringRuleService.commit failed: \(error)")
            #endif
            return false
        }
    }
}
