import XCTest
@testable import QuaraMoney

/// Covers the comparison point the Home summary hero reads.
///
/// The hero states "$X less than June by this day", which is only honest if
/// both series are read at the same offset into their period — comparing a
/// half-finished month against a complete one is what made the old card's
/// side-by-side totals misleading. That offset is date math against `Date()`,
/// so it gets tests rather than a visual check.
@MainActor
final class ExpenseTrendModelTests: XCTestCase {

    private let calendar = Calendar.current

    /// Builds a model over a whole month containing `date`, with no transactions —
    /// these tests are about the period arithmetic, not the spend aggregation.
    private func makeModel(
        monthContaining date: Date,
        previousPeriodCumulative: [Decimal] = []
    ) -> ExpenseTrendModel {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
        return ExpenseTrendModel(
            dailySections: [],
            startDate: start,
            endDate: end,
            previousPeriodCumulative: previousPeriodCumulative
        )
    }

    // MARK: - Ongoing period

    func testCurrentMonthComparesAtToday() {
        let today = Date()
        let model = makeModel(monthContaining: today)

        XCTAssertTrue(model.isPeriodOngoing, "Today's month is still running")

        // Day 1 of the month is index 0, so the index is today's day number - 1.
        let dayOfMonth = calendar.component(.day, from: today)
        XCTAssertEqual(model.comparisonIndex, dayOfMonth - 1)
    }

    // MARK: - Closed period

    func testClosedMonthComparesAtItsFinalDay() {
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: Date())!
        let model = makeModel(monthContaining: lastMonth)

        XCTAssertFalse(model.isPeriodOngoing, "A month that has ended is not ongoing")
        // Clamped to the last day, so a closed month is measured total-vs-total.
        XCTAssertEqual(model.comparisonIndex, model.daily.count - 1)
    }

    // MARK: - Future period

    func testFuturePeriodHasNoComparisonPoint() {
        let nextMonth = calendar.date(byAdding: .month, value: 2, to: Date())!
        let model = makeModel(monthContaining: nextMonth)

        XCTAssertFalse(model.isPeriodOngoing)
        XCTAssertNil(
            model.comparisonIndex,
            "A period that hasn't started has nothing to compare, and must not clamp to day 0"
        )
    }

    // MARK: - Series alignment

    func testPreviousSeriesIsTruncatedToThisPeriodsLength() {
        // A 40-entry previous series against a ~30-day month: `average` zips, so
        // it can never run past the current period's day count.
        let model = makeModel(
            monthContaining: Date(),
            previousPeriodCumulative: (1...40).map { Decimal($0 * 10) }
        )

        XCTAssertEqual(model.average.count, model.daily.count)
        XCTAssertLessThanOrEqual(model.average.count, 31)
    }

    func testEmptyPreviousSeriesProducesNoReferenceLine() {
        let model = makeModel(monthContaining: Date())
        XCTAssertTrue(model.average.isEmpty)
    }

    /// The hero divides by the previous period's value at `comparisonIndex`, and
    /// that array can be shorter than this period (June has 30 days, July 31).
    /// The view clamps; this pins the precondition that makes clamping correct.
    func testPreviousSeriesMayBeShorterThanCurrentPeriod() {
        let july = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!
        let model = makeModel(
            monthContaining: july,
            previousPeriodCumulative: (1...30).map { Decimal($0) }   // June
        )

        XCTAssertEqual(model.daily.count, 31)
        XCTAssertEqual(model.average.count, 30, "zip truncates to the shorter series")
    }
}
