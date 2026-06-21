import Foundation

// Codable row types mirroring the Supabase tables (snake_case column names used
// directly as property names to avoid CodingKeys boilerplate).
//
// Money is kept as `Decimal`: supabase-swift's JSONEncoder emits the exact
// decimal value, and for the single-value amounts this app stores the round-trip
// is lossless at realistic magnitudes. (Accumulation still uses Decimal locally.)
// Dates round-trip as ISO8601 via supabase-swift's encoder/decoder.
//
// Phase 3c slice: core entities only (wallets, categories, transactions). The
// remaining 12 entities follow in subsequent increments.

struct SyncWalletRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var name: String
    var currency_code: String
    var icon: String
    var color_hex: String
    var is_archived: Bool
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?
}

struct SyncCategoryRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var name: String
    var icon: String?
    var color_hex: String?
    var type: String
    var is_system: Bool
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?
}

struct SyncTransactionRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var type: String
    var date: Date
    var note: String?
    var tags: [String]
    var exclude_from_reports: Bool
    var amount: Decimal
    var currency_code: String
    var exchange_rate: Decimal
    var stored_rate: Decimal?
    var photo_path: String?
    var category_id: UUID?
    var event_id: UUID?
    var source_wallet_id: UUID?
    var destination_wallet_id: UUID?
    var recurring_rule_id: UUID?
    var debt_id: UUID?
    var savings_goal_id: UUID?
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?
}
