import Foundation
import SwiftData

/// Tunable weights for the suggestion scoring model.
/// Grouped here so they are easy to adjust and unit-test in isolation.
struct SuggestionWeights {
    /// Half-life of the recency decay, in days. A transaction this old counts half as much.
    var halfLifeDays: Double = 30
    /// Transactions older than this are ignored entirely (their decayed weight is negligible).
    var windowDays: Double = 365
    /// Multiplier when a past transaction shares the current weekday.
    var weekday: Double = 1.5
    /// Multiplier when a past transaction is within ±`hourWindow` hours of now.
    var hour: Double = 1.3
    /// How many hours on each side of "now" count as the same time-of-day.
    var hourWindow: Int = 2
    /// Multiplier for cross-field co-occurrence (wallet ↔ category paired in history).
    var pair: Double = 2.0
    /// Multiplier when a past transaction happened at the exact same place (Apple place ID).
    var locationPlace: Double = 2.5
    /// Multiplier when a past transaction happened on the same ~111m spatial grid cell.
    var locationNear: Double = 1.8

    /// Minimum top score required before a category may be highlighted as "suggested".
    var highlightMinSignal: Double = 1.0
    /// Minimum share of total score the top category must hold to be highlighted.
    var highlightShareThreshold: Double = 0.35

    nonisolated static let `default` = SuggestionWeights()
}

/// A lightweight, resolved location used purely for ranking — never written to a transaction.
/// `applePlaceID` is only present when the user manually picked a place; the background
/// current-location path supplies `spatialKey` only (no reverse-geocode).
struct SuggestionLocationContext: Equatable {
    let applePlaceID: String?
    let spatialKey: String?

    var hasSignal: Bool { applePlaceID != nil || spatialKey != nil }
}

struct ScoredWallet: Identifiable {
    let wallet: Wallet
    let score: Double
    let lastUsed: Date?
    var id: UUID { wallet.id }
}

struct ScoredCategory: Identifiable {
    let category: Category
    let score: Double
    let lastUsed: Date?
    let isHighlighted: Bool
    var id: UUID { category.id }
}

struct ScoredTag: Identifiable {
    /// Display spelling (most recently used casing wins).
    let tag: String
    let score: Double
    let lastUsed: Date?
    var id: String { tag.lowercased() }
}

/// Recency-weighted, contextual ranking for the wallet/category quick-pickers on Add Transaction.
///
/// Replaces the old all-time `transactions.count` sort. Each candidate is scored in a single
/// pass over its relevant transactions (no `.count`-in-comparator), then sorted on the
/// precomputed score. See the plan for the full scoring model.
enum TransactionSuggestionEngine {

    // MARK: - Public API

    @MainActor
    static func rankWallets(
        _ wallets: [Wallet],
        type: TransactionType,
        selectedCategory: Category?,
        location: SuggestionLocationContext?,
        now: Date = Date(),
        weights: SuggestionWeights = .default
    ) -> [ScoredWallet] {
        let scored = wallets.map { wallet -> ScoredWallet in
            let txns = relevantTransactions(for: wallet, type: type)
            let (score, lastUsed) = accumulate(
                txns,
                now: now,
                weights: weights,
                location: location,
                pairMatches: { selectedCategory != nil && $0.category?.id == selectedCategory?.id }
            )
            return ScoredWallet(wallet: wallet, score: score, lastUsed: lastUsed)
        }
        return scored.sorted { lhs, rhs in
            orderedBefore(
                lScore: lhs.score, lDate: lhs.lastUsed, lName: lhs.wallet.name,
                rScore: rhs.score, rDate: rhs.lastUsed, rName: rhs.wallet.name
            )
        }
    }

    @MainActor
    static func rankCategories(
        _ categories: [Category],
        type: TransactionType,
        selectedWallet: Wallet?,
        location: SuggestionLocationContext?,
        now: Date = Date(),
        weights: SuggestionWeights = .default
    ) -> [ScoredCategory] {
        let typed = categories.filter { $0.type == type }

        struct Raw { let category: Category; let score: Double; let lastUsed: Date? }
        let raw = typed.map { category -> Raw in
            let txns = (category.transactions ?? []).filter { $0.type == type && $0.deletedAt == nil }
            let (score, lastUsed) = accumulate(
                txns,
                now: now,
                weights: weights,
                location: location,
                pairMatches: { selectedWallet != nil && $0.sourceWallet?.id == selectedWallet?.id }
            )
            return Raw(category: category, score: score, lastUsed: lastUsed)
        }

        let sorted = raw.sorted { lhs, rhs in
            orderedBefore(
                lScore: lhs.score, lDate: lhs.lastUsed, lName: lhs.category.name,
                rScore: rhs.score, rDate: rhs.lastUsed, rName: rhs.category.name
            )
        }

        // Highlight only the dominant top suggestion (reorder + highlight; never auto-fill).
        let totalScore = sorted.reduce(0) { $0 + $1.score }
        let topScore = sorted.first?.score ?? 0
        let topShare = totalScore > 0 ? topScore / totalScore : 0
        let highlightTop = topScore >= weights.highlightMinSignal
            && topShare >= weights.highlightShareThreshold

        return sorted.enumerated().map { index, item in
            ScoredCategory(
                category: item.category,
                score: item.score,
                lastUsed: item.lastUsed,
                isHighlighted: index == 0 && highlightTop
            )
        }
    }

    /// Ranks note `#tags` seen in past transactions for the Add Transaction
    /// tag-suggestion chips. Unlike wallets/categories, tags have no model —
    /// candidates are discovered from the transactions themselves, so the
    /// caller supplies the source set (typically a recent date-range fetch).
    ///
    /// Each transaction's contextual weight (recency × weekday × hour ×
    /// wallet/category co-occurrence × location) is credited to every tag it
    /// carries; same scoring model as the other rankers.
    @MainActor
    static func rankTags(
        in transactions: [Transaction],
        type: TransactionType,
        selectedWallet: Wallet?,
        selectedCategory: Category?,
        location: SuggestionLocationContext?,
        now: Date = Date(),
        weights: SuggestionWeights = .default
    ) -> [ScoredTag] {
        struct Accum { var display: String; var score: Double; var lastUsed: Date? }
        var byKey: [String: Accum] = [:]

        for txn in transactions where txn.type == type {
            let ageDays = max(0, now.timeIntervalSince(txn.date) / 86_400)
            guard ageDays <= weights.windowDays else { continue }

            // Stored array is authoritative; fall back to parsing the note for
            // rows written by paths that predate (or bypass) tag extraction.
            let tags = txn.tags.isEmpty ? TransactionTagParser.tags(in: txn.note) : txn.tags
            guard !tags.isEmpty else { continue }

            var weight = pow(0.5, ageDays / weights.halfLifeDays)
            weight *= weekdayBoost(txn.date, now: now, weights: weights)
            weight *= hourBoost(txn.date, now: now, weights: weights)
            if let selectedCategory, txn.category?.id == selectedCategory.id { weight *= weights.pair }
            if let selectedWallet, txn.sourceWallet?.id == selectedWallet.id { weight *= weights.pair }
            weight *= locationBoost(txn, location: location, weights: weights)

            for tag in tags {
                let key = tag.lowercased()
                var acc = byKey[key] ?? Accum(display: tag, score: 0, lastUsed: nil)
                acc.score += weight
                if acc.lastUsed == nil || txn.date > acc.lastUsed! {
                    acc.lastUsed = txn.date
                    acc.display = tag
                }
                byKey[key] = acc
            }
        }

        return byKey.values
            .map { ScoredTag(tag: $0.display, score: $0.score, lastUsed: $0.lastUsed) }
            .sorted { lhs, rhs in
                orderedBefore(
                    lScore: lhs.score, lDate: lhs.lastUsed, lName: lhs.tag,
                    rScore: rhs.score, rDate: rhs.lastUsed, rName: rhs.tag
                )
            }
    }

    // MARK: - Scoring

    /// Sums the contextual weight of each transaction and tracks the most recent date.
    private static func accumulate(
        _ transactions: [Transaction],
        now: Date,
        weights: SuggestionWeights,
        location: SuggestionLocationContext?,
        pairMatches: (Transaction) -> Bool
    ) -> (score: Double, lastUsed: Date?) {
        var total = 0.0
        var lastUsed: Date?

        for txn in transactions {
            let ageDays = max(0, now.timeIntervalSince(txn.date) / 86_400)
            guard ageDays <= weights.windowDays else { continue }

            if lastUsed == nil || txn.date > lastUsed! {
                lastUsed = txn.date
            }

            var weight = pow(0.5, ageDays / weights.halfLifeDays)
            weight *= weekdayBoost(txn.date, now: now, weights: weights)
            weight *= hourBoost(txn.date, now: now, weights: weights)
            if pairMatches(txn) { weight *= weights.pair }
            weight *= locationBoost(txn, location: location, weights: weights)

            total += weight
        }

        return (total, lastUsed)
    }

    private static func weekdayBoost(_ date: Date, now: Date, weights: SuggestionWeights) -> Double {
        let cal = Calendar.current
        return cal.component(.weekday, from: date) == cal.component(.weekday, from: now)
            ? weights.weekday : 1.0
    }

    private static func hourBoost(_ date: Date, now: Date, weights: SuggestionWeights) -> Double {
        let cal = Calendar.current
        let h1 = cal.component(.hour, from: date)
        let h2 = cal.component(.hour, from: now)
        let raw = abs(h1 - h2)
        let circular = min(raw, 24 - raw) // wrap around midnight
        return circular <= weights.hourWindow ? weights.hour : 1.0
    }

    private static func locationBoost(
        _ txn: Transaction,
        location: SuggestionLocationContext?,
        weights: SuggestionWeights
    ) -> Double {
        guard let location, location.hasSignal, let txnLocation = txn.location else { return 1.0 }

        if let placeID = location.applePlaceID, !placeID.isEmpty,
           txnLocation.applePlaceID == placeID {
            return weights.locationPlace
        }
        if let key = location.spatialKey, !key.isEmpty,
           txnLocation.normalizedSpatialKey == key {
            return weights.locationNear
        }
        return 1.0
    }

    // MARK: - Helpers

    /// Transactions where this wallet participates, narrowed by the entry type.
    /// `sourceWallet` holds both expense and income, so filtering by type is what makes
    /// wallet ranking type-aware. Transfers consider both source and destination sides.
    private static func relevantTransactions(for wallet: Wallet, type: TransactionType) -> [Transaction] {
        switch type {
        case .expense, .income:
            return (wallet.outgoingTransactions ?? []).filter { $0.type == type && $0.deletedAt == nil }
        case .transfer:
            let outgoing = (wallet.outgoingTransactions ?? []).filter { $0.type == .transfer && $0.deletedAt == nil }
            let incoming = (wallet.incomingTransactions ?? []).filter { $0.deletedAt == nil }
            // Dedup by id defensively (a wallet is never both source and dest of one transfer).
            var seen = Set<UUID>()
            return (outgoing + incoming).filter { seen.insert($0.id).inserted }
        case .adjustment:
            return (wallet.outgoingTransactions ?? []).filter { $0.type == .adjustment && $0.deletedAt == nil }
        }
    }

    /// Sort order: score desc, then most-recently-used desc, then name asc.
    private static func orderedBefore(
        lScore: Double, lDate: Date?, lName: String,
        rScore: Double, rDate: Date?, rName: String
    ) -> Bool {
        if lScore != rScore { return lScore > rScore }
        switch (lDate, rDate) {
        case let (l?, r?) where l != r: return l > r
        case (.some, .none): return true
        case (.none, .some): return false
        default: break
        }
        return lName.localizedCaseInsensitiveCompare(rName) == .orderedAscending
    }
}
