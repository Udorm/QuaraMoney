import XCTest
import SwiftData
import SwiftUI
import UIKit
@testable import QuaraMoney

// `import SwiftUI` brings in SwiftUI.Transaction, which collides with the app's
// @Model Transaction. Pin the bare name to the app's type for this test file.
private typealias Transaction = QuaraMoney.Transaction

@MainActor
final class RecurringRuleServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        container = TestModelContainer.create()
        context = container.mainContext
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func day(of date: Date) -> Int { Calendar.current.component(.day, from: date) }

    @discardableResult
    private func makeWallet(currency: String = "USD") -> Wallet {
        let wallet = Wallet(name: "Test", currencyCode: currency, icon: "wallet.pass", colorHex: "#000000")
        context.insert(wallet)
        return wallet
    }

    @discardableResult
    private func makeRule(amount: Decimal = 10,
                          currency: String = "USD",
                          type: TransactionType = .expense,
                          frequency: Frequency = .monthly,
                          interval: Int = 1,
                          start: Date,
                          nextDue: Date? = nil,
                          end: Date? = nil,
                          wallet: Wallet? = nil) -> RecurringRule {
        let rule = RecurringRule(name: "Netflix", amount: amount, currencyCode: currency,
                                 frequency: frequency, interval: interval, startDate: start, type: type)
        rule.nextDueDate = nextDue ?? start
        rule.endDate = end
        rule.wallet = wallet
        context.insert(rule)
        return rule
    }

    private func allTransactions() -> [Transaction] {
        (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
    }

    // MARK: - Date math

    func testNextOccurrencePerFrequency() {
        let start = date(2026, 6, 15)
        XCTAssertEqual(RecurringRuleService.nextOccurrence(after: start, startDate: start, frequency: .daily),
                       date(2026, 6, 16))
        XCTAssertEqual(RecurringRuleService.nextOccurrence(after: start, startDate: start, frequency: .weekly),
                       date(2026, 6, 22))
        XCTAssertEqual(RecurringRuleService.nextOccurrence(after: start, startDate: start, frequency: .monthly),
                       date(2026, 7, 15))
        XCTAssertEqual(RecurringRuleService.nextOccurrence(after: start, startDate: start, frequency: .yearly),
                       date(2027, 6, 15))
    }

    func testNextOccurrenceEveryTwoWeeks() {
        let start = date(2026, 6, 15)
        XCTAssertEqual(RecurringRuleService.nextOccurrence(after: start, startDate: start, frequency: .weekly, interval: 2),
                       date(2026, 6, 29))
    }

    func testNextOccurrenceEveryThreeMonths() {
        let start = date(2026, 6, 15)
        XCTAssertEqual(RecurringRuleService.nextOccurrence(after: start, startDate: start, frequency: .monthly, interval: 3),
                       date(2026, 9, 15))
    }

    func testNextOccurrenceEverySixMonths() {
        let start = date(2026, 6, 15)
        XCTAssertEqual(RecurringRuleService.nextOccurrence(after: start, startDate: start, frequency: .monthly, interval: 6),
                       date(2026, 12, 15))
    }

    func testMonthEndAnchoringWithInterval() {
        let start = date(2026, 1, 31)
        // Next occurrence with interval = 2 months (March 31st)
        let occ2 = RecurringRuleService.nextOccurrence(after: start, startDate: start, frequency: .monthly, interval: 2)!
        XCTAssertEqual(occ2, date(2026, 3, 31))
        
        // Next occurrence with interval = 2 months from occ2 (May 31st)
        let occ3 = RecurringRuleService.nextOccurrence(after: occ2, startDate: start, frequency: .monthly, interval: 2)!
        XCTAssertEqual(occ3, date(2026, 5, 31))
    }

    func testPostAdvancesByInterval() {
        let wallet = makeWallet()
        let due = date(2026, 6, 1)
        // Repeat every 2 months
        let rule = makeRule(amount: 15, frequency: .monthly, interval: 2, start: due, nextDue: due, wallet: wallet)

        let txn = RecurringRuleService.post(rule: rule, in: context)
        XCTAssertNotNil(txn)
        XCTAssertEqual(rule.nextDueDate, date(2026, 8, 1), "Schedule advances by 2 months")
    }

    /// A rule anchored on the 31st must not permanently drift to the 28th after
    /// passing through February.
    func testMonthEndAnchoringNoDrift() {
        let start = date(2026, 1, 31)
        let occ2 = RecurringRuleService.nextOccurrence(after: start, startDate: start, frequency: .monthly)!
        XCTAssertEqual(day(of: occ2), 28, "Feb 2026 clamps to the 28th")

        let occ3 = RecurringRuleService.nextOccurrence(after: occ2, startDate: start, frequency: .monthly)!
        XCTAssertEqual(day(of: occ3), 31, "March must return to the anchored 31st, not stay at 28")
        XCTAssertEqual(Calendar.current.component(.month, from: occ3), 3)
    }

    func testFirstDueDateClampsPastStartForward() {
        let now = Date()
        let start = Calendar.current.date(byAdding: .month, value: -3, to: now)!
        let firstDue = RecurringRuleService.firstDueDate(startDate: start, frequency: .monthly, asOf: now)

        let todayStart = Calendar.current.startOfDay(for: now)
        XCTAssertGreaterThanOrEqual(firstDue, todayStart, "Past start dates must not backfill")
        // Anchored to the original start day-of-month.
        XCTAssertEqual(day(of: firstDue), day(of: start))
    }

    func testFirstDueDateKeepsFutureStart() {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: 10, to: now)!
        let firstDue = RecurringRuleService.firstDueDate(startDate: start, frequency: .monthly, asOf: now)
        XCTAssertEqual(firstDue, start, "A future start date is the first due date unchanged")
    }

    // MARK: - Due detection

    func testIsDueRespectsActiveState() {
        let rule = makeRule(start: date(2026, 6, 1), nextDue: date(2026, 6, 1))
        XCTAssertTrue(RecurringRuleService.isDue(rule))
        rule.isActive = false
        XCTAssertFalse(RecurringRuleService.isDue(rule), "Paused rules are never due")
    }

    func testIsDueRespectsEndDate() {
        let today = Date()
        let rule = makeRule(start: today, nextDue: today,
                            end: Calendar.current.date(byAdding: .day, value: -1, to: today))
        XCTAssertFalse(RecurringRuleService.isDue(rule), "Occurrence past the end date is not due")
        XCTAssertEqual(RecurringRuleService.pendingOccurrenceCount(for: rule), 0)
    }

    func testNotDueWhenNextDueInFuture() {
        let future = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        let rule = makeRule(start: future, nextDue: future)
        XCTAssertFalse(RecurringRuleService.isDue(rule))
    }

    // MARK: - Post / skip

    func testPostCreatesTransactionAndAdvances() {
        let wallet = makeWallet()
        let due = date(2026, 6, 1)
        let rule = makeRule(amount: 9.99, type: .expense, frequency: .monthly,
                            start: due, nextDue: due, wallet: wallet)

        let txn = RecurringRuleService.post(rule: rule, in: context)

        XCTAssertNotNil(txn)
        let txns = allTransactions()
        XCTAssertEqual(txns.count, 1)
        let t = txns[0]
        XCTAssertEqual(t.type, .expense)
        XCTAssertEqual(t.amount, 9.99)
        XCTAssertEqual(t.currencyCode, "USD")
        XCTAssertEqual(t.sourceWallet?.id, wallet.id)
        XCTAssertEqual(t.recurringRule?.id, rule.id)
        XCTAssertEqual(t.storedRate, 1)
        XCTAssertEqual(t.date, due)
        XCTAssertEqual(rule.nextDueDate, date(2026, 7, 1), "Schedule advances one period")
        XCTAssertTrue(rule.needsSync)
    }

    func testPostUsesRuleTypeForIncome() {
        let wallet = makeWallet()
        let rule = makeRule(type: .income, start: date(2026, 6, 1), nextDue: date(2026, 6, 1), wallet: wallet)
        RecurringRuleService.post(rule: rule, in: context)
        XCTAssertEqual(allTransactions().first?.type, .income)
    }

    func testPostHonorsAmountAndDateOverrides() {
        let wallet = makeWallet()
        let rule = makeRule(amount: 10, start: date(2026, 6, 1), nextDue: date(2026, 6, 1), wallet: wallet)
        let overrideDate = date(2026, 6, 3)
        RecurringRuleService.post(rule: rule, amount: 42, date: overrideDate, in: context)
        let txn = allTransactions().first
        XCTAssertEqual(txn?.amount, 42)
        XCTAssertEqual(txn?.date, overrideDate)
        XCTAssertEqual(rule.amount, 10, "Per-occurrence override does not mutate the rule")
    }

    func testSkipAdvancesWithoutTransaction() {
        let wallet = makeWallet()
        let due = date(2026, 6, 1)
        let rule = makeRule(start: due, nextDue: due, wallet: wallet)

        RecurringRuleService.skip(rule: rule, in: context)

        XCTAssertEqual(allTransactions().count, 0, "Skip creates no transaction")
        XCTAssertEqual(rule.nextDueDate, date(2026, 7, 1))
    }

    /// Lifecycle: posting an occurrence advances the schedule but never
    /// deactivates or completes the rule — it keeps running into the next period.
    func testPostKeepsRuleActiveAndAdvances() {
        let wallet = makeWallet()
        let due = date(2026, 6, 1)
        let rule = makeRule(frequency: .monthly, start: due, nextDue: due, wallet: wallet)

        RecurringRuleService.post(rule: rule, in: context)

        XCTAssertTrue(rule.isActive, "Posting never pauses the rule")
        XCTAssertNil(rule.deletedAt, "Posting never deletes the rule")
        XCTAssertEqual(rule.nextDueDate, date(2026, 7, 1), "Advances exactly one period")
    }

    /// Lifecycle: a skip followed by a post advances two periods and yields a
    /// single transaction dated at the (post-skip) due date.
    func testSkipThenPostAdvancesTwoPeriods() {
        let wallet = makeWallet()
        let due = date(2026, 6, 1)
        let rule = makeRule(amount: 12, frequency: .monthly, start: due, nextDue: due, wallet: wallet)

        RecurringRuleService.skip(rule: rule, in: context)        // June skipped → July
        RecurringRuleService.post(rule: rule, in: context)        // July posted → August

        let txns = allTransactions()
        XCTAssertEqual(txns.count, 1, "Only the posted period creates a transaction")
        XCTAssertEqual(txns.first?.date, date(2026, 7, 1), "Posted at the surviving (post-skip) due date")
        XCTAssertEqual(rule.nextDueDate, date(2026, 8, 1), "Two periods advanced overall")
    }

    /// Lifecycle: weekly rules advance by exactly one week per post (regression
    /// guard for "next payment date not reflecting the weekly cadence").
    func testWeeklyPostAdvancesByOneWeek() {
        let wallet = makeWallet()
        let due = date(2026, 6, 1)
        let rule = makeRule(frequency: .weekly, start: due, nextDue: due, wallet: wallet)

        RecurringRuleService.post(rule: rule, in: context)

        XCTAssertEqual(rule.nextDueDate, date(2026, 6, 8), "Weekly advances +7 days, not a month")
    }

    /// Exercises the compound `isActive && deletedAt == nil` FetchDescriptor
    /// predicate at runtime (the review inbox used this shape in a @Query and
    /// hung). If this returns quickly the predicate is fine; a hang/throw points
    /// at SwiftData predicate handling.
    func testDueRulesFetchPredicateExecutes() {
        let wallet = makeWallet()
        _ = makeRule(start: date(2026, 6, 1), nextDue: date(2026, 6, 1), wallet: wallet)               // due
        let paused = makeRule(start: date(2026, 6, 1), nextDue: date(2026, 6, 1), wallet: wallet)
        paused.isActive = false
        let future = makeRule(start: date(2099, 1, 1), nextDue: date(2099, 1, 1), wallet: wallet)        // not due
        _ = future
        try? context.save()

        let due = RecurringRuleService.dueRules(asOf: date(2026, 6, 15), in: context)
        XCTAssertEqual(due.count, 1, "Only the active, due rule is returned")
    }

    /// Hosts the Upcoming tab (the review inbox) in a real window with one due
    /// rule and pumps the runloop. If the view enters an infinite SwiftUI update
    /// loop the runloop pump never settles and this times out — reproducing the
    /// reported freeze.
    func testUpcomingTabRendersWithoutHanging() {
        let wallet = makeWallet()
        _ = makeRule(start: date(2026, 6, 1), nextDue: date(2026, 6, 1), wallet: wallet)
        try? context.save()

        let host = UIHostingController(rootView:
            NavigationStack { RecurringRuleListView(initialTab: .upcoming) }.modelContainer(container)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let settled = expectation(description: "runloop settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { settled.fulfill() }
        wait(for: [settled], timeout: 12)
    }

    // MARK: - Resume (skip-forward, no backfill)

    func testResumedNextDueDateSkipsForwardWhenPast() {
        let start = Calendar.current.date(byAdding: .month, value: -5, to: Date())!
        let pastDue = Calendar.current.date(byAdding: .month, value: -2, to: Date())!
        let rule = makeRule(frequency: .monthly, start: start, nextDue: pastDue)

        let resumed = RecurringRuleService.resumedNextDueDate(for: rule)

        let todayStart = Calendar.current.startOfDay(for: Date())
        XCTAssertGreaterThanOrEqual(resumed, todayStart, "Resume must not resurface a past-due backlog")
        XCTAssertEqual(day(of: resumed), day(of: start), "Re-anchored to the original day-of-month")
    }

    func testResumedNextDueDateKeepsFutureDate() {
        let future = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
        let rule = makeRule(start: future, nextDue: future)
        XCTAssertEqual(RecurringRuleService.resumedNextDueDate(for: rule), future,
                       "A still-future due date is untouched on resume")
    }

    func testPostAllDueStopsAtEndDate() {
        let wallet = makeWallet()
        let start = Calendar.current.date(byAdding: .month, value: -2, to: Date())!
        // End date equals the first occurrence: only that one occurrence is allowed.
        let rule = makeRule(frequency: .monthly, start: start, nextDue: start, end: start, wallet: wallet)

        let posted = RecurringRuleService.postAllDue(rule: rule, in: context)

        XCTAssertEqual(posted?.count, 1, "Only occurrences on/before the end date post")
        XCTAssertEqual(allTransactions().count, 1)
    }

    func testPostAllDueCatchesUpMultiplePeriods() {
        let wallet = makeWallet()
        let start = Calendar.current.date(byAdding: .month, value: -2, to: Date())!
        let rule = makeRule(frequency: .monthly, start: start, nextDue: start, wallet: wallet)

        let posted = RecurringRuleService.postAllDue(rule: rule, in: context)
        let count = posted?.count ?? 0

        XCTAssertGreaterThanOrEqual(count, 2, "Two-plus months overdue should post each missed period")
        XCTAssertEqual(allTransactions().count, count)
        XCTAssertFalse(RecurringRuleService.isDue(rule), "Caught up — no longer due")
    }

    // MARK: - Delete preserves history (.nullify)

    /// The core guarantee of the Phase 1 `.cascade` → `.nullify` change: deleting
    /// a rule must NOT destroy the ledger transactions it generated. (The inverse
    /// back-reference is not asserted — SwiftData clears the FK lazily, and the
    /// production delete path is a soft-delete that never triggers the rule.)
    func testHardDeleteRulePreservesGeneratedTransactions() {
        let wallet = makeWallet()
        let rule = makeRule(amount: 9.99, start: date(2026, 6, 1), nextDue: date(2026, 6, 1), wallet: wallet)
        RecurringRuleService.post(rule: rule, in: context)
        XCTAssertEqual(allTransactions().count, 1)

        context.delete(rule)
        try? context.save()

        let txns = allTransactions()
        XCTAssertEqual(txns.count, 1, "Deleting a rule must NOT delete its ledger history")
        XCTAssertEqual(txns[0].amount, 9.99, "The surviving transaction is intact")
        XCTAssertEqual(txns[0].type, .expense)
    }

    // MARK: - Multi-currency rate capture

    func testMultiCurrencyStoredRate() {
        CurrencyManager.shared.rates = ["USD": 1.0, "KHR": 4000.0]
        let khrWallet = makeWallet(currency: "KHR")
        let rule = makeRule(amount: 5, currency: "USD", start: date(2026, 6, 1),
                            nextDue: date(2026, 6, 1), wallet: khrWallet)

        RecurringRuleService.post(rule: rule, in: context)

        let txn = allTransactions().first
        XCTAssertEqual(txn?.amount, 5, "Amount stays in the rule's own currency")
        XCTAssertEqual(txn?.currencyCode, "USD")
        XCTAssertEqual(txn?.storedRate, 4000, "storedRate = walletRate / txnRate (4000 / 1)")
        XCTAssertEqual(txn?.exchangeRate, 4000)
    }

    // MARK: - Undo (post/skip are reversible)

    /// Undoing a post tombstones the created transaction and restores the
    /// schedule to where it stood before posting.
    func testUndoPostTombstonesTransactionAndRestoresSchedule() {
        let wallet = makeWallet()
        let due = date(2026, 6, 1)
        let rule = makeRule(amount: 9.99, frequency: .monthly, start: due, nextDue: due, wallet: wallet)

        let mutation = RecurringRuleService.post(rule: rule, in: context)
        XCTAssertNotNil(mutation)
        XCTAssertEqual(rule.nextDueDate, date(2026, 7, 1), "Posting advanced one period")
        XCTAssertEqual(allTransactions().filter { $0.deletedAt == nil }.count, 1)

        RecurringRuleService.undo(mutation!, in: context)

        XCTAssertEqual(rule.nextDueDate, due, "Undo restores the pre-post due date")
        let live = allTransactions().filter { $0.deletedAt == nil }
        XCTAssertEqual(live.count, 0, "The posted transaction is soft-deleted on undo")
        let tombstoned = allTransactions().first { $0.deletedAt != nil }
        XCTAssertNotNil(tombstoned, "It is tombstoned (not hard-deleted) so the deletion can sync")
        XCTAssertTrue(tombstoned?.needsSync ?? false)
        XCTAssertTrue(RecurringRuleService.isDue(rule), "The occurrence is due again after undo")
    }

    /// Undoing a skip rewinds the schedule by exactly one period and creates no
    /// ledger side effects.
    func testUndoSkipRestoresSchedule() {
        let wallet = makeWallet()
        let due = date(2026, 6, 1)
        let rule = makeRule(frequency: .monthly, start: due, nextDue: due, wallet: wallet)

        let mutation = RecurringRuleService.skip(rule: rule, in: context)
        XCTAssertEqual(rule.nextDueDate, date(2026, 7, 1), "Skip advanced one period")

        RecurringRuleService.undo(mutation!, in: context)

        XCTAssertEqual(rule.nextDueDate, due, "Undo restores the skipped occurrence's due date")
        XCTAssertEqual(allTransactions().count, 0, "Undoing a skip touches no transactions")
    }

    /// Undoing a Post-All catch-up tombstones every transaction it created and
    /// restores the schedule to the start of the caught-up run.
    func testUndoPostAllDueRestoresAllOccurrences() {
        let wallet = makeWallet()
        let start = Calendar.current.date(byAdding: .month, value: -2, to: Date())!
        let rule = makeRule(frequency: .monthly, start: start, nextDue: start, wallet: wallet)

        let mutation = RecurringRuleService.postAllDue(rule: rule, in: context)
        let postedCount = mutation?.count ?? 0
        XCTAssertGreaterThanOrEqual(postedCount, 2)
        XCTAssertEqual(allTransactions().filter { $0.deletedAt == nil }.count, postedCount)

        RecurringRuleService.undo(mutation!, in: context)

        XCTAssertEqual(rule.nextDueDate, start, "Undo rewinds to the first caught-up occurrence")
        XCTAssertEqual(allTransactions().filter { $0.deletedAt == nil }.count, 0,
                       "Every transaction created by Post-All is soft-deleted")
        XCTAssertTrue(RecurringRuleService.isDue(rule), "The rule is due again after undo")
    }

    /// The undo token resolves the rule by `PersistentIdentifier`, so it stays
    /// valid even though it does not hold a direct model reference.
    func testUndoResolvesRuleByIdentifier() {
        let wallet = makeWallet()
        let due = date(2026, 6, 1)
        let rule = makeRule(frequency: .monthly, start: due, nextDue: due, wallet: wallet)
        let mutation = RecurringRuleService.skip(rule: rule, in: context)!

        XCTAssertEqual(mutation.ruleID, rule.persistentModelID)
        XCTAssertEqual(mutation.previousNextDueDate, due)
        RecurringRuleService.undo(mutation, in: context)
        XCTAssertEqual(rule.nextDueDate, due)
    }

    // MARK: - Monthly equivalent

    private func roundedToCents(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }

    func testMonthlyEquivalentPerFrequency() {
        XCTAssertEqual(RecurringRuleService.monthlyEquivalent(amount: 15, frequency: .monthly), 15)
        XCTAssertEqual(RecurringRuleService.monthlyEquivalent(amount: 240, frequency: .yearly), 20)
        XCTAssertEqual(roundedToCents(RecurringRuleService.monthlyEquivalent(amount: 10, frequency: .weekly)),
                       Decimal(string: "43.33")!, "Weekly × 52 ÷ 12")
        XCTAssertEqual(roundedToCents(RecurringRuleService.monthlyEquivalent(amount: 1, frequency: .daily)),
                       Decimal(string: "30.42")!, "Daily × 365 ÷ 12")
    }

    func testMonthlyEquivalentHonorsInterval() {
        XCTAssertEqual(RecurringRuleService.monthlyEquivalent(amount: 30, frequency: .monthly, interval: 3), 10)
        XCTAssertEqual(roundedToCents(RecurringRuleService.monthlyEquivalent(amount: 10, frequency: .weekly, interval: 2)),
                       Decimal(string: "21.67")!)
    }

    // MARK: - Projection

    func testDueDatesStartAtNextDueDate() {
        let rule = makeRule(frequency: .weekly, start: date(2026, 9, 5), nextDue: date(2026, 9, 12))
        let dates = RecurringRuleService.dueDates(for: rule, in: date(2026, 9, 1)..<date(2026, 10, 1))
        XCTAssertEqual(dates, [date(2026, 9, 12), date(2026, 9, 19), date(2026, 9, 26)],
                       "Periods before nextDueDate were posted or skipped and never reappear")
    }

    func testDueDatesSkipEarlierDatesAndStopAtEndDate() {
        let rule = makeRule(frequency: .weekly, start: date(2026, 9, 5), nextDue: date(2026, 9, 12), end: date(2026, 10, 10))
        let october = RecurringRuleService.dueDates(for: rule, in: date(2026, 10, 1)..<date(2026, 11, 1))
        XCTAssertEqual(october, [date(2026, 10, 3), date(2026, 10, 10)])
    }

    func testHasEnded() {
        let rule = makeRule(start: date(2026, 6, 1), nextDue: date(2026, 7, 1), end: date(2026, 6, 30))
        XCTAssertTrue(RecurringRuleService.hasEnded(rule))
        rule.endDate = nil
        XCTAssertFalse(RecurringRuleService.hasEnded(rule))
    }

    // MARK: - Month summary (Upcoming tab)

    /// The Upcoming tab's card must add up to its sections: expected = paid +
    /// due + upcoming for the month.
    func testMonthSummaryTotalsReconcileWithSections() {
        let wallet = makeWallet()
        let now = date(2026, 9, 15)
        let rates = ["USD": 1.0, "KHR": 4000.0]

        // Weekly: Sep 5 posted, Sep 12 overdue, Sep 19 + 26 still upcoming.
        let gym = makeRule(amount: 10, frequency: .weekly, start: date(2026, 9, 5), nextDue: date(2026, 9, 5), wallet: wallet)
        RecurringRuleService.post(rule: gym, in: context)
        // A riel bill later this month, converted into USD totals.
        _ = makeRule(amount: 180_000, currency: "KHR", start: date(2026, 9, 25), nextDue: date(2026, 9, 25), wallet: wallet)
        _ = makeRule(amount: 1200, type: .income, start: date(2026, 9, 30), nextDue: date(2026, 9, 30), wallet: wallet)
        let paused = makeRule(amount: 25, start: date(2026, 9, 20), nextDue: date(2026, 9, 20), wallet: wallet)
        paused.isActive = false

        let rules = (try? context.fetch(FetchDescriptor<RecurringRule>())) ?? []
        let summary = RecurringMonthSummary.build(rules: rules, transactions: allTransactions(),
                                                  monthStart: date(2026, 9, 1), now: now,
                                                  rates: rates, currency: "USD")

        XCTAssertTrue(summary.isCurrentMonth)
        XCTAssertEqual(summary.due.map(\.rule.id), [gym.id])
        XCTAssertEqual(summary.dueOccurrenceCount, 1)
        XCTAssertEqual(summary.upcoming.map(\.date),
                       [date(2026, 9, 19), date(2026, 9, 25), date(2026, 9, 26), date(2026, 9, 30)],
                       "Paused rules and today-or-earlier occurrences are not upcoming")
        XCTAssertEqual(summary.paid.count, 1)
        XCTAssertEqual(summary.paidTotals, .init(expense: 10, income: 0))
        XCTAssertEqual(summary.upcomingTotals, .init(expense: 65, income: 1200))
        XCTAssertEqual(summary.expectedTotals, .init(expense: 85, income: 1200),
                       "Paid 10 + overdue 10 + upcoming 65")
    }

    func testMonthSummaryFutureMonthHasNoDueItems() {
        let wallet = makeWallet()
        let gym = makeRule(amount: 10, frequency: .weekly, start: date(2026, 9, 5), nextDue: date(2026, 9, 12), wallet: wallet)

        let summary = RecurringMonthSummary.build(rules: [gym], transactions: [],
                                                  monthStart: date(2026, 10, 1), now: date(2026, 9, 15),
                                                  rates: ["USD": 1.0], currency: "USD")

        XCTAssertFalse(summary.isCurrentMonth)
        XCTAssertTrue(summary.due.isEmpty, "Due items only belong to the current month")
        XCTAssertEqual(summary.upcoming.count, 5, "Oct 3, 10, 17, 24 and 31")
        XCTAssertEqual(summary.expectedTotals.expense, 50)
    }
}
