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

nonisolated struct SyncWalletRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var name: String
    var currency_code: String
    var icon: String
    var color_hex: String
    var is_archived: Bool
    var created_at: Date
    var updated_at: Date
    @NullEncodable var deleted_at: Date?
}

nonisolated struct SyncCategoryRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var name: String
    @NullEncodable var icon: String?
    @NullEncodable var color_hex: String?
    var type: String
    var is_system: Bool
    var created_at: Date
    var updated_at: Date
    @NullEncodable var deleted_at: Date?
}

nonisolated struct SyncTransactionRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var type: String
    var date: Date
    @NullEncodable var note: String?
    var tags: [String]
    var exclude_from_reports: Bool
    var amount: Decimal
    var currency_code: String
    var exchange_rate: Decimal
    @NullEncodable var stored_rate: Decimal?
    @NullEncodable var photo_path: String?
    @NullEncodable var category_id: UUID?
    @NullEncodable var event_id: UUID?
    @NullEncodable var source_wallet_id: UUID?
    @NullEncodable var destination_wallet_id: UUID?
    @NullEncodable var recurring_rule_id: UUID?
    @NullEncodable var debt_id: UUID?
    @NullEncodable var savings_goal_id: UUID?
    var created_at: Date
    var updated_at: Date
    @NullEncodable var deleted_at: Date?
}

nonisolated struct SyncEventRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var title: String
    var start_date: Date
    @NullEncodable var end_date: Date?
    @NullEncodable var total_budget: Decimal?
    @NullEncodable var cover_image_path: String?
    @NullEncodable var notes: String?
    var icon: String
    var color_hex: String
    @NullEncodable var location: String?
    var status: String
    var currency_code: String
    var ledger_revision: Int64
    @NullEncodable var confirmed_settlement_revision: Int64?
    var ledger_mode: String
    @NullEncodable var latitude: Double?
    @NullEncodable var longitude: Double?
    var updated_at: Date
    @NullEncodable var deleted_at: Date?
}

nonisolated struct SyncDebtRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var person_name: String
    var total_amount: Decimal
    var currency_code: String
    @NullEncodable var due_date: Date?
    var type: String
    @NullEncodable var note: String?
    var date_created: Date
    var is_completed: Bool
    var created_at: Date
    var updated_at: Date
    @NullEncodable var deleted_at: Date?
}

nonisolated struct SyncSavingsGoalRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var name: String
    @NullEncodable var goal_description: String?
    var target_amount: Decimal
    var current_amount: Decimal
    var currency_code: String
    @NullEncodable var target_date: Date?
    var created_date: Date
    var updated_at: Date
    var icon_name: String
    var color_hex: String
    var is_completed: Bool
    @NullEncodable var completed_date: Date?
    var auto_contribute_enabled: Bool
    @NullEncodable var auto_contribute_amount: Decimal?
    @NullEncodable var auto_contribute_period_raw: String?
    var priority: Int
    @NullEncodable var linked_wallet_id: UUID?
    @NullEncodable var deleted_at: Date?
}

nonisolated struct SyncRecurringRuleRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    var name: String
    var amount: Decimal
    var currency_code: String
    var type: String
    var frequency: String
    var interval: Int = 1
    var start_date: Date
    var next_due_date: Date
    @NullEncodable var end_date: Date?
    var is_active: Bool
    var reminders_enabled: Bool
    @NullEncodable var wallet_id: UUID?
    @NullEncodable var category_id: UUID?
    var updated_at: Date
    @NullEncodable var deleted_at: Date?
}

nonisolated struct SyncEventMemberRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    @NullEncodable var event_id: UUID?
    var name: String
    @NullEncodable var avatar_path: String?
    @NullEncodable var avatar_icon: String?
    var color_hex: String
    var is_archived: Bool
    var is_local_user: Bool
    var is_budget_pool: Bool
    var sort_order: Int
    var created_at: Date
    var updated_at: Date
    @NullEncodable var deleted_at: Date?
}

nonisolated struct SyncEventLedgerTransactionRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    @NullEncodable var event_id: UUID?
    var kind: String
    var title: String
    var amount_minor: Int64
    var paid_source: String
    @NullEncodable var paid_by_member_id: UUID?
    var split_type: String
    var date: Date
    @NullEncodable var note: String?
    @NullEncodable var category_id: UUID?
    @NullEncodable var category_name: String?
    @NullEncodable var category_icon: String?
    @NullEncodable var category_color_hex: String?
    var is_split_all: Bool
    var is_deleted: Bool
    var created_at: Date
    var updated_at: Date
    @NullEncodable var deleted_at: Date?
}

nonisolated struct SyncEventLedgerParticipantRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    @NullEncodable var transaction_id: UUID?
    var member_id: UUID
    @NullEncodable var event_member_id: UUID?
    var order_index: Int
    var updated_at: Date
    @NullEncodable var deleted_at: Date?
}

nonisolated struct SyncEventSettlementSnapshotRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    @NullEncodable var event_id: UUID?
    var ledger_revision: Int64
    var created_at: Date
    var updated_at: Date
    @NullEncodable var deleted_at: Date?
}

nonisolated struct SyncEventSettlementTransferRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    @NullEncodable var snapshot_id: UUID?
    var from_member_id: UUID
    var to_member_id: UUID
    var amount_minor: Int64
    var sequence: Int
    var updated_at: Date
    @NullEncodable var deleted_at: Date?
}

nonisolated struct SyncEventWalletExportRecordRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    @NullEncodable var event_id: UUID?
    @NullEncodable var snapshot_id: UUID?
    var member_id: UUID
    var wallet_transaction_id: UUID
    var amount_minor: Int64
    var direction: String
    var export_type: String
    var created_at: Date
    var updated_at: Date
    @NullEncodable var deleted_at: Date?
}

nonisolated struct SyncTransactionLocationRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    @NullEncodable var transaction_id: UUID?
    @NullEncodable var display_name: String?
    @NullEncodable var full_address: String?
    @NullEncodable var short_address: String?
    var latitude: Double
    var longitude: Double
    @NullEncodable var horizontal_accuracy_meters: Double?
    var captured_at: Date
    var source_raw: String
    @NullEncodable var apple_place_id: String?
    @NullEncodable var alternate_apple_place_ids: String?
    @NullEncodable var point_of_interest_category_raw: String?
    @NullEncodable var locality: String?
    @NullEncodable var administrative_area: String?
    @NullEncodable var country_code: String?
    @NullEncodable var normalized_spatial_key: String?
    var updated_at: Date
    @NullEncodable var deleted_at: Date?
}

nonisolated struct SyncBudgetRow: Codable, Sendable {
    var id: UUID
    var user_id: UUID
    @NullEncodable var name: String?
    var amount_limit: Decimal
    var currency_code: String
    var period_type_raw: String
    var start_date: Date
    var created_at: Date
    var updated_at: Date
    @NullEncodable var custom_end_date: Date?
    var month: Int
    var year: Int
    var is_recurring: Bool
    var rollover_excess: Bool
    var rollover_amount: Decimal
    @NullEncodable var amount_type_data: String?
    var alert_at_50: Bool
    var alert_at_80: Bool
    var alert_at_100: Bool
    var alert_on_projected_overspend: Bool
    @NullEncodable var last_alert_triggered_date: Date?
    var last_alert_threshold: Int
    @NullEncodable var budget_category_type_raw: String?
    @NullEncodable var category_id: UUID?
    @NullEncodable var deleted_at: Date?
}

nonisolated struct SyncBudgetCategoryRow: Codable, Sendable {
    var budget_id: UUID
    var category_id: UUID
    var user_id: UUID
}

// MARK: - Server-authoritative timestamp write-back

/// A pushable row that carries the server's authoritative `updated_at`. After an
/// upsert returns the stored representation, the push writes this value back onto
/// the local model so local timestamps live in the same clock domain as the
/// server's (the DB trigger stamps `updated_at` on every insert and update). The
/// join table `SyncBudgetCategoryRow` has no timestamp and is excluded.
protocol SyncServerRow: Codable, Sendable {
    var id: UUID { get }
    var updated_at: Date { get }
}

extension SyncWalletRow: SyncServerRow {}
extension SyncCategoryRow: SyncServerRow {}
extension SyncTransactionRow: SyncServerRow {}
extension SyncEventRow: SyncServerRow {}
extension SyncDebtRow: SyncServerRow {}
extension SyncSavingsGoalRow: SyncServerRow {}
extension SyncRecurringRuleRow: SyncServerRow {}
extension SyncEventMemberRow: SyncServerRow {}
extension SyncEventLedgerTransactionRow: SyncServerRow {}
extension SyncEventLedgerParticipantRow: SyncServerRow {}
extension SyncEventSettlementSnapshotRow: SyncServerRow {}
extension SyncEventSettlementTransferRow: SyncServerRow {}
extension SyncEventWalletExportRecordRow: SyncServerRow {}
extension SyncTransactionLocationRow: SyncServerRow {}
extension SyncBudgetRow: SyncServerRow {}
