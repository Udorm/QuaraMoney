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

struct SyncEventRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var title: String
    var start_date: Date
    var end_date: Date?
    var total_budget: Decimal?
    var cover_image_path: String?
    var notes: String?
    var icon: String
    var color_hex: String
    var location: String?
    var status: String
    var currency_code: String
    var ledger_revision: Int64
    var confirmed_settlement_revision: Int64?
    var ledger_mode: String
    var latitude: Double?
    var longitude: Double?
    var updated_at: Date
    var deleted_at: Date?
}

struct SyncDebtRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var person_name: String
    var total_amount: Decimal
    var currency_code: String
    var due_date: Date?
    var type: String
    var note: String?
    var date_created: Date
    var is_completed: Bool
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?
}

struct SyncSavingsGoalRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var name: String
    var goal_description: String?
    var target_amount: Decimal
    var current_amount: Decimal
    var currency_code: String
    var target_date: Date?
    var created_date: Date
    var updated_at: Date
    var icon_name: String
    var color_hex: String
    var is_completed: Bool
    var completed_date: Date?
    var auto_contribute_enabled: Bool
    var auto_contribute_amount: Decimal?
    var auto_contribute_period_raw: String?
    var priority: Int
    var linked_wallet_id: UUID?
    var deleted_at: Date?
}

struct SyncRecurringRuleRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var name: String
    var amount: Decimal
    var currency_code: String
    var frequency: String
    var start_date: Date
    var next_due_date: Date
    var is_active: Bool
    var wallet_id: UUID?
    var category_id: UUID?
    var updated_at: Date
    var deleted_at: Date?
}
