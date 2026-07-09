import SwiftData
import Foundation

@Model
final class Category {
    var id: UUID

    // MARK: - Sync metadata (Supabase migration)
    var syncUserID: UUID?
    var deletedAt: Date?
    var needsSync: Bool = true

    var name: String
    var icon: String
    var colorHex: String
    var type: TransactionType // .income or .expense only
    
    var isSystem: Bool = false

    /// Language-independent identity for app-defined (default/system) categories,
    /// e.g. `"salary"`, `"sys_debt"`. `nil` for user-created categories. Two
    /// devices that independently create the same default produce rows with the
    /// same key, so sync can merge them instead of duplicating (the cloud enforces
    /// a partial unique index on `(user_id, canonical_key, type)`). Definitions
    /// live in `CategoryCatalog`. Additive optional property — migrates via
    /// SwiftData lightweight inference under SchemaV1 (see SchemaVersioning.swift).
    var canonicalKey: String?

    // Timestamps (for future sync readiness)
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Relationships
    @Relationship(deleteRule: .deny) var transactions: [Transaction]?
    @Relationship(deleteRule: .cascade) var budgets: [Budget]?
    @Relationship(deleteRule: .nullify) var recurringRules: [RecurringRule]?

    init(name: String, icon: String, colorHex: String, type: TransactionType, isSystem: Bool = false, canonicalKey: String? = nil) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.type = type
        self.isSystem = isSystem
        self.canonicalKey = canonicalKey
    }
}

extension Category {
    /// Live, current-language display name for a category (see
    /// `CategoryCatalog.localizedName(for:)`). App-defined categories re-localize
    /// on language switch via their `canonicalKey`; user-created ones fall back to
    /// the stored `name`. Use this for ALL UI; the stored `name` remains the raw
    /// seed/user string used for search, export and sync.
    var displayName: String {
        CategoryCatalog.localizedName(for: self)
    }
}
