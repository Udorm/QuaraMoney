import Foundation
import SwiftData

/// Single source of truth for every app-defined category (fresh-install defaults
/// and the system categories features depend on), keyed by a language-independent
/// `canonicalKey`.
///
/// Why keys instead of names: category identity used to be `(localized name,
/// type)`, which duplicated categories whenever the two sides of a comparison
/// were produced in different languages (English lookup vs Khmer seed), after a
/// language switch, or when two devices independently created the same default
/// with different random UUIDs. Every creation/lookup path now goes through the
/// catalog key, and the sync layer merges same-key duplicates
/// (`dedupeCanonicalCategories`), so duplication is structurally impossible
/// rather than procedurally avoided.
///
/// All helpers are `nonisolated` and take a `ModelContext`, so they can run on
/// the launch seeding task's background context as well as the main context.
/// IMPORTANT: mutations made here happen off the main context, where
/// `SyncMutationTracker` does not observe saves — so every mutation stamps
/// `needsSync`/`updatedAt` explicitly.
nonisolated enum CategoryCatalog {

    // MARK: - Definitions

    struct Definition: Sendable {
        /// Stable, language-independent identity. Never rename a shipped key.
        let key: String
        /// Localizable.strings key for the display name (also used to match
        /// pre-key categories by their English or Khmer name).
        let l10nKey: String
        let icon: String
        let colorHex: String
        let type: TransactionType
        /// Created as / promoted to a system category (undeletable feature deps
        /// and the "must-have" set).
        let isSystem: Bool
        /// Included in the fresh-install seed set. System debt categories are
        /// not seeded up-front; they're created on demand by DebtService.
        let seedOnFreshInstall: Bool
        /// Re-created at every launch on never-signed-in devices if missing
        /// (the legacy "must-have"/ensure set). Once a device is account-owned,
        /// categories are cloud-authoritative and nothing is auto-created.
        let ensureOnLaunch: Bool
    }

    /// The store's current UI language code, resolved WITHOUT touching the
    /// `@MainActor` `LanguageManager` so seeding/maintenance can run on their
    /// background context. Mirrors `LanguageManager.updateBundle()`'s selection.
    private static var currentLanguageCode: String {
        switch UserDefaults.standard.string(forKey: "selectedLanguage") {
        case "en": return "en"
        case "km": return "km"
        default: // "system" or unset
            return Locale.preferredLanguages.first?.starts(with: "km") == true ? "km" : "en"
        }
    }

    /// A definition's display name in the store's current language. Equivalent to
    /// the old `Definition.localizedName` (`l10nKey.localized`) but resolved
    /// nonisolated via the shipped `.lproj` bundles (see `name(of:in:)`).
    private static func currentLocalizedName(for def: Definition) -> String {
        name(of: def.l10nKey, in: currentLanguageCode)
            ?? name(of: def.l10nKey, in: "en")
            ?? def.l10nKey
    }

    static let all: [Definition] = [
        // Income
        .init(key: "salary", l10nKey: "category.salary", icon: "dollarsign.circle", colorHex: "#4CAF50", type: .income, isSystem: true, seedOnFreshInstall: true, ensureOnLaunch: true),
        .init(key: "investments", l10nKey: "category.investments", icon: "chart.line.uptrend.xyaxis", colorHex: "#2196F3", type: .income, isSystem: true, seedOnFreshInstall: true, ensureOnLaunch: true),
        .init(key: "income_others", l10nKey: "category.others", icon: "gift", colorHex: "#FFC107", type: .income, isSystem: true, seedOnFreshInstall: true, ensureOnLaunch: true),
        .init(key: "debt_loans_income", l10nKey: "category.debtAndLoans", icon: "banknote", colorHex: "#795548", type: .income, isSystem: false, seedOnFreshInstall: true, ensureOnLaunch: true),

        // Expense
        .init(key: "food_drink", l10nKey: "category.foodAndDrink", icon: "fork.knife", colorHex: "#FF5722", type: .expense, isSystem: true, seedOnFreshInstall: true, ensureOnLaunch: true),
        .init(key: "housing", l10nKey: "category.housing", icon: "house", colorHex: "#795548", type: .expense, isSystem: true, seedOnFreshInstall: true, ensureOnLaunch: true),
        .init(key: "transportation", l10nKey: "category.transportation", icon: "car", colorHex: "#03A9F4", type: .expense, isSystem: true, seedOnFreshInstall: true, ensureOnLaunch: true),
        .init(key: "personal_lifestyle", l10nKey: "category.personalLifestyle", icon: "tshirt", colorHex: "#E91E63", type: .expense, isSystem: false, seedOnFreshInstall: true, ensureOnLaunch: false),
        .init(key: "health", l10nKey: "category.health", icon: "heart", colorHex: "#F44336", type: .expense, isSystem: true, seedOnFreshInstall: true, ensureOnLaunch: true),
        .init(key: "education", l10nKey: "category.education", icon: "book", colorHex: "#9C27B0", type: .expense, isSystem: false, seedOnFreshInstall: true, ensureOnLaunch: false),
        .init(key: "tech", l10nKey: "category.tech", icon: "laptopcomputer", colorHex: "#607D8B", type: .expense, isSystem: false, seedOnFreshInstall: true, ensureOnLaunch: false),
        .init(key: "leisure", l10nKey: "category.leisure", icon: "gamecontroller", colorHex: "#673AB7", type: .expense, isSystem: false, seedOnFreshInstall: true, ensureOnLaunch: false),
        .init(key: "subscriptions", l10nKey: "category.subscriptions", icon: "arrow.triangle.2.circlepath", colorHex: "#3F51B5", type: .expense, isSystem: false, seedOnFreshInstall: true, ensureOnLaunch: false),
        .init(key: "financial", l10nKey: "category.financial", icon: "building.columns", colorHex: "#009688", type: .expense, isSystem: true, seedOnFreshInstall: true, ensureOnLaunch: true),
        .init(key: "debt_loans_expense", l10nKey: "category.debtAndLoans", icon: "banknote", colorHex: "#795548", type: .expense, isSystem: true, seedOnFreshInstall: true, ensureOnLaunch: true),
        .init(key: "trip", l10nKey: "category.trip", icon: "airplane", colorHex: "#FF9800", type: .expense, isSystem: true, seedOnFreshInstall: true, ensureOnLaunch: true),
        .init(key: "saving", l10nKey: "category.saving", icon: "banknote.fill", colorHex: "#4CAF50", type: .expense, isSystem: true, seedOnFreshInstall: true, ensureOnLaunch: true),
        .init(key: "gifts_donations", l10nKey: "category.giftsAndDonations", icon: "gift.fill", colorHex: "#E91E63", type: .expense, isSystem: false, seedOnFreshInstall: true, ensureOnLaunch: true),

        // Bills
        .init(key: "electricity_bill", l10nKey: "category.electricityBill", icon: "bolt", colorHex: "#FFEB3B", type: .expense, isSystem: true, seedOnFreshInstall: true, ensureOnLaunch: true),
        .init(key: "water_bill", l10nKey: "category.waterBill", icon: "drop", colorHex: "#2196F3", type: .expense, isSystem: true, seedOnFreshInstall: true, ensureOnLaunch: true),
        .init(key: "internet_bill", l10nKey: "category.internetBill", icon: "wifi", colorHex: "#00BCD4", type: .expense, isSystem: true, seedOnFreshInstall: true, ensureOnLaunch: true),

        // Debt & Loan system categories (created on demand by DebtService, and
        // ensured at launch on never-signed-in devices).
        .init(key: "sys_debt", l10nKey: "debt.systemCategory.debt", icon: "arrow.up.right", colorHex: "#FF3B30", type: .expense, isSystem: true, seedOnFreshInstall: false, ensureOnLaunch: true),
        .init(key: "sys_debt_collection", l10nKey: "debt.systemCategory.debtCollection", icon: "tray.and.arrow.down.fill", colorHex: "#34C759", type: .income, isSystem: true, seedOnFreshInstall: false, ensureOnLaunch: true),
        .init(key: "sys_loan", l10nKey: "debt.systemCategory.loan", icon: "arrow.down.left", colorHex: "#34C759", type: .income, isSystem: true, seedOnFreshInstall: false, ensureOnLaunch: true),
        .init(key: "sys_loan_repayment", l10nKey: "debt.systemCategory.loanRepayment", icon: "tray.and.arrow.up.fill", colorHex: "#007AFF", type: .expense, isSystem: true, seedOnFreshInstall: false, ensureOnLaunch: true),
    ]

    static func definition(forKey key: String) -> Definition? {
        all.first { $0.key == key }
    }

    /// The category's display name in the store's current UI language. App-defined
    /// categories (those carrying a `canonicalKey`) re-localize live, so a device
    /// switching language immediately sees built-in category names update;
    /// user-created categories fall back to their stored `name`. The stored `name`
    /// stays the raw seed/user string (used for search, export and sync); this is
    /// the presentation value — read it via `Category.displayName` everywhere UI
    /// shows a category name.
    static func localizedName(for category: Category) -> String {
        guard let key = category.canonicalKey, let def = definition(forKey: key) else {
            return category.name
        }
        return currentLocalizedName(for: def)
    }

    // MARK: - Localized-name matching (for pre-key rows)

    /// Languages the app ships. Matching consults every one of them so a category
    /// seeded under a Khmer name is recognized on a device now running English
    /// (and vice versa).
    private static let shippedLanguages = ["en", "km"]

    /// Resolves an l10n key in a specific shipped language, independent of the
    /// current app language.
    private static func name(of l10nKey: String, in language: String) -> String? {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        let value = bundle.localizedString(forKey: l10nKey, value: l10nKey, table: nil)
        return value == l10nKey ? nil : value
    }

    /// Every name a definition is (or ever was) displayed under: all shipped
    /// languages plus the current runtime language, plus the raw English literal
    /// fallback that legacy code paths hardcoded.
    private static func knownNames(for def: Definition) -> Set<String> {
        var names = Set(shippedLanguages.compactMap { name(of: def.l10nKey, in: $0) })
        names.insert(currentLocalizedName(for: def))
        // Legacy: DebtService hardcoded the English system-category names.
        switch def.key {
        case "sys_debt": names.insert("Debt")
        case "sys_debt_collection": names.insert("Debt Collection")
        case "sys_loan": names.insert("Loan")
        case "sys_loan_repayment": names.insert("Loan Repayment")
        default: break
        }
        return names
    }

    /// Matches an existing (pre-key) category to its catalog definition by any
    /// shipped-language name + type.
    static func matchDefinition(name: String, type: TransactionType) -> Definition? {
        all.first { $0.type == type && knownNames(for: $0).contains(name) }
    }

    // MARK: - Fetch / create by key

    /// Fetches the live category for a catalog key, creating it (with the current
    /// language's display name) when absent. The single entry point features use
    /// to resolve an app-defined category (DebtService, seeding, ensure passes).
    @discardableResult
    static func fetchOrCreate(key: String, in context: ModelContext) throws -> Category {
        guard let def = definition(forKey: key) else {
            throw CategoryCatalogError.unknownKey(key)
        }
        if let existing = try fetch(key: key, type: def.type, in: context) {
            if def.isSystem && !existing.isSystem {
                existing.isSystem = true
                stampLocalEdit(existing)
            }
            return existing
        }
        // Adopt a pre-key category that matches by any shipped-language name.
        if let adopted = try adoptByName(def, in: context) {
            return adopted
        }
        let category = Category(name: currentLocalizedName(for: def), icon: def.icon,
                                colorHex: def.colorHex, type: def.type,
                                isSystem: def.isSystem, canonicalKey: def.key)
        context.insert(category)
        return category
    }

    private static func fetch(key: String, type: TransactionType, in context: ModelContext) throws -> Category? {
        // Enum values can't be captured in a #Predicate (unsupportedPredicate) —
        // filter by key/tombstone in the store, match `type` in Swift.
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.canonicalKey == key && $0.deletedAt == nil }
        )
        return try context.fetch(descriptor).first { $0.type == type }
    }

    /// Finds a live keyless category whose name matches the definition in any
    /// shipped language and stamps the key onto it.
    private static func adoptByName(_ def: Definition, in context: ModelContext) throws -> Category? {
        let names = knownNames(for: def)
        let keyless = try context.fetch(FetchDescriptor<Category>(
            predicate: #Predicate { $0.canonicalKey == nil && $0.deletedAt == nil }
        ))
        guard let match = keyless.first(where: { $0.type == def.type && names.contains($0.name) }) else {
            return nil
        }
        match.canonicalKey = def.key
        if def.isSystem && !match.isSystem { match.isSystem = true }
        stampLocalEdit(match)
        return match
    }

    // MARK: - Seeding & maintenance (launch)

    /// Seeds the fresh-install default set. Only runs when the store has no live
    /// categories at all (same guard as the legacy seeding).
    static func seedDefaultsIfEmpty(in context: ModelContext) throws {
        let existing = try context.fetchCount(FetchDescriptor<Category>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))
        guard existing == 0 else { return }
        for def in all where def.seedOnFreshInstall {
            let category = Category(name: currentLocalizedName(for: def), icon: def.icon,
                                    colorHex: def.colorHex, type: def.type,
                                    isSystem: def.isSystem, canonicalKey: def.key)
            context.insert(category)
        }
    }

    /// One-shot idempotent maintenance pass:
    ///  1. Stamps `canonicalKey` on pre-key categories that match a definition by
    ///     any shipped-language name (so existing installs and old cloud rows gain
    ///     keys and start deduplicating).
    ///  2. Merges live duplicates that share `(canonicalKey, type)` — see
    ///     `dedupeCanonicalCategories`.
    /// Cheap when there's nothing to do; safe to run every launch and after pulls.
    ///
    /// `owner` is the account that currently owns this device's store
    /// (`SyncEngine.localOwnerUUID`); rows synced under a DIFFERENT account are
    /// untouchable here — they are the sync engine's foreign-row cleanup's job.
    static func stampAndDedupe(in context: ModelContext, owner: UUID?) throws {
        try stampCanonicalKeys(in: context, owner: owner)
        try dedupeCanonicalCategories(in: context, owner: owner)
    }

    /// True when a row was synced under some account other than `owner` — a
    /// leftover from a previous sign-in on this device. Such rows must never be
    /// stamped, merged, or chosen as a merge winner: tombstoning the current
    /// account's real category in favor of another account's leftover is exactly
    /// the mass-deletion incident of 2026-07-02.
    private static func isForeign(_ category: Category, owner: UUID?) -> Bool {
        guard let rowOwner = category.syncUserID else { return false }
        return rowOwner != owner
    }

    /// Pass 1 of `stampAndDedupe`. When several keyless categories match the same
    /// definition (e.g. an English and a Khmer copy from the pre-key era), each
    /// gets the key — the dedupe pass then merges them deterministically.
    static func stampCanonicalKeys(in context: ModelContext, owner: UUID?) throws {
        let keyless = try context.fetch(FetchDescriptor<Category>(
            predicate: #Predicate { $0.canonicalKey == nil && $0.deletedAt == nil }
        ))
        guard !keyless.isEmpty else { return }
        for category in keyless where !isForeign(category, owner: owner) {
            guard let def = matchDefinition(name: category.name, type: category.type) else { continue }
            category.canonicalKey = def.key
            if def.isSystem && !category.isSystem { category.isSystem = true }
            stampLocalEdit(category)
        }
    }

    /// Merges live categories that share `(canonicalKey, type)` into one winner:
    /// re-points transactions, budgets, and recurring rules, then soft-deletes the
    /// losers (tombstones sync, so every device converges).
    ///
    /// Winner selection is deterministic across devices so two devices deduping
    /// independently pick the same survivor:
    ///  1. a row confirmed in the current account's cloud (owned + already
    ///     round-tripped, `needsSync == false`) beats everything,
    ///  2. then a row merely owned by the account (pushed-pending),
    ///  3. then unowned local-only rows,
    ///  4. ties broken by oldest `createdAt`, then smallest id.
    /// Rows owned by a DIFFERENT account are excluded entirely (see `isForeign`).
    static func dedupeCanonicalCategories(in context: ModelContext, owner: UUID?) throws {
        let keyed = try context.fetch(FetchDescriptor<Category>(
            predicate: #Predicate { $0.canonicalKey != nil && $0.deletedAt == nil }
        ))
        let eligible = keyed.filter { !isForeign($0, owner: owner) }
        func rank(_ c: Category) -> Int {
            guard let rowOwner = c.syncUserID, rowOwner == owner else { return 2 }
            return c.needsSync ? 1 : 0
        }
        let groups = Dictionary(grouping: eligible) { GroupKey(key: $0.canonicalKey ?? "", type: $0.type) }
        for (_, members) in groups where members.count > 1 {
            let winner = members.min { a, b in
                let ra = rank(a), rb = rank(b)
                if ra != rb { return ra < rb }
                if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
                return a.id.uuidString < b.id.uuidString
            }!
            for loser in members where loser !== winner {
                merge(loser: loser, into: winner, context: context)
            }
        }
    }

    private struct GroupKey: Hashable {
        let key: String
        let type: TransactionType
    }

    private static func merge(loser: Category, into winner: Category, context: ModelContext) {
        for t in loser.transactions ?? [] {
            t.category = winner
            stampLocalEdit(t)
        }
        for r in loser.recurringRules ?? [] {
            r.category = winner
            stampLocalEdit(r)
        }
        // Budgets: single-category link plus the multi-category join set.
        // These are separate SwiftData inverses; sharing a category between
        // multiple budgets must never reassign another budget's join set.
        for b in loser.budgets ?? [] {
            b.category = winner
            stampLocalEdit(b)
        }
        if let budgets = try? context.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.deletedAt == nil })) {
            for b in budgets {
                guard var cats = b.categories, let idx = cats.firstIndex(where: { $0 === loser }) else { continue }
                cats.remove(at: idx)
                if !cats.contains(where: { $0 === winner }) { cats.append(winner) }
                b.categories = cats
                stampLocalEdit(b)
            }
        }
        loser.deletedAt = Date()
        stampLocalEdit(loser)
    }

    /// Marks a model changed for sync. Explicit because catalog mutations can run
    /// on background contexts where `SyncMutationTracker` doesn't observe saves.
    private static func stampLocalEdit(_ model: some SyncTrackable & AnyObject) {
        model.updatedAt = Date()
        model.needsSync = true
    }

    enum CategoryCatalogError: LocalizedError {
        case unknownKey(String)
        var errorDescription: String? {
            if case let .unknownKey(key) = self { return "Unknown category catalog key: \(key)" }
            return nil
        }
    }
}
