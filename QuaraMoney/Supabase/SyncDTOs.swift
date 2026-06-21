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

struct SyncEventMemberRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var event_id: UUID?
    var name: String
    var avatar_path: String?
    var avatar_icon: String?
    var color_hex: String
    var is_archived: Bool
    var is_local_user: Bool
    var is_budget_pool: Bool
    var sort_order: Int
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?
}

struct SyncEventLedgerTransactionRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var event_id: UUID?
    var kind: String
    var title: String
    var amount_minor: Int64
    var paid_source: String
    var paid_by_member_id: UUID?
    var split_type: String
    var date: Date
    var note: String?
    var category_id: UUID?
    var category_name: String?
    var category_icon: String?
    var category_color_hex: String?
    var is_split_all: Bool
    var is_deleted: Bool
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?
}

struct SyncEventLedgerParticipantRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var transaction_id: UUID?
    var member_id: UUID
    var event_member_id: UUID?
    var order_index: Int
    var updated_at: Date
    var deleted_at: Date?
}

struct SyncEventSettlementSnapshotRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var event_id: UUID?
    var ledger_revision: Int64
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?
}

struct SyncEventSettlementTransferRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var snapshot_id: UUID?
    var from_member_id: UUID
    var to_member_id: UUID
    var amount_minor: Int64
    var sequence: Int
    var updated_at: Date
    var deleted_at: Date?
}

struct SyncEventWalletExportRecordRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var event_id: UUID?
    var snapshot_id: UUID?
    var member_id: UUID
    var wallet_transaction_id: UUID
    var amount_minor: Int64
    var direction: String
    var export_type: String
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?
}

struct SyncTransactionLocationRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var transaction_id: UUID?
    var display_name: String?
    var full_address: String?
    var short_address: String?
    var latitude: Double
    var longitude: Double
    var horizontal_accuracy_meters: Double?
    var captured_at: Date
    var source_raw: String
    var apple_place_id: String?
    var alternate_apple_place_ids: String?
    var point_of_interest_category_raw: String?
    var locality: String?
    var administrative_area: String?
    var country_code: String?
    var normalized_spatial_key: String?
    var updated_at: Date
    var deleted_at: Date?
}

struct SyncBudgetRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var name: String?
    var amount_limit: Decimal
    var currency_code: String
    var period_type_raw: String
    var start_date: Date
    var created_at: Date
    var updated_at: Date
    var custom_end_date: Date?
    var month: Int
    var year: Int
    var is_recurring: Bool
    var rollover_excess: Bool
    var rollover_amount: Decimal
    var amount_type_data: String?
    var alert_at_50: Bool
    var alert_at_80: Bool
    var alert_at_100: Bool
    var alert_on_projected_overspend: Bool
    var last_alert_triggered_date: Date?
    var last_alert_threshold: Int
    var budget_category_type_raw: String?
    var category_id: UUID?
    var deleted_at: Date?
}

struct SyncBudgetCategoryRow: Codable, Sendable {
    var budget_id: UUID
    var category_id: UUID
    var user_id: UUID
}
