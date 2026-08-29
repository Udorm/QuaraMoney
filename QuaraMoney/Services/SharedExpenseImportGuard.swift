import Foundation
import SwiftData

/// Heuristic duplicate detection for incoming shared expenses.
///
/// The payload carries no import receipt, and nothing is persisted to record
/// that a given MitraTrip expense has already been imported — so a re-opened
/// link would otherwise land a second copy silently. This flags likely repeats
/// so the staging screen can pre-exclude them.
///
/// The heuristic is deliberately conservative: two genuinely separate $3 coffees
/// bought on the same day are indistinguishable from one imported twice, so a
/// match is a *warning*, never an automatic rejection. The user always decides.
///
/// A persistent import receipt keyed on `(app, tripId, sourceId)` would be exact.
/// `SharedExpenseEntry.sourceId` already travels in the payload for that reason,
/// so the upgrade is purely additive whenever it's wanted.
enum SharedExpenseImportGuard {

    /// How far either side of the candidate date to look. Wide enough to absorb
    /// a timezone shift between the two devices, narrow enough that a genuine
    /// weekly repeat (same café, same order, next Monday) doesn't trip it.
    static let dateWindow: TimeInterval = 60 * 60 * 36

    /// One candidate line the staging screen may commit.
    struct Candidate {
        var amount: Decimal
        var currencyCode: String
        var date: Date
        /// Free text used as a secondary signal — trip name, expense title.
        var searchHint: String?
    }

    /// Returns the indices of `candidates` that look like they've been imported
    /// before, so the caller can pre-exclude exactly those rows.
    @MainActor
    static func likelyDuplicateIndices(
        among candidates: [Candidate],
        in context: ModelContext
    ) -> Set<Int> {
        guard !candidates.isEmpty else { return [] }

        // One fetch spanning every candidate's window, then matched in Swift:
        // #Predicate can't express the per-candidate amount/date pairing, and a
        // fetch per row would be N round trips for an import of up to 300.
        let dates = candidates.map(\.date)
        guard let earliest = dates.min(), let latest = dates.max() else { return [] }
        let lower = earliest.addingTimeInterval(-dateWindow)
        let upper = latest.addingTimeInterval(dateWindow)

        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { tx in
                tx.deletedAt == nil && tx.date >= lower && tx.date <= upper
            }
        )
        guard let existing = try? context.fetch(descriptor), !existing.isEmpty else { return [] }

        // Each existing transaction can absorb at most one candidate, so
        // importing two identical coffees only flags the first when only one
        // was imported before.
        var consumed = Set<PersistentIdentifier>()
        var flagged: Set<Int> = []

        for (index, candidate) in candidates.enumerated() {
            let match = existing.first { tx in
                guard !consumed.contains(tx.persistentModelID) else { return false }
                guard tx.type == .expense else { return false }
                guard tx.currencyCode.caseInsensitiveCompare(candidate.currencyCode) == .orderedSame else { return false }
                guard tx.amount == candidate.amount else { return false }
                return abs(tx.date.timeIntervalSince(candidate.date)) <= dateWindow
            }
            if let match {
                consumed.insert(match.persistentModelID)
                flagged.insert(index)
            }
        }
        return flagged
    }
}
