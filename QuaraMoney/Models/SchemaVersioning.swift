import SwiftData
import Foundation

// MARK: - Schema Versioning

/// V1 schema snapshot — the launch baseline (no `.unique` constraints, image
/// blobs in external storage, `Transaction.date` indexed).
/// All future schema changes must add a new VersionedSchema (with copied model
/// definitions) and a corresponding MigrationStage in the plan below.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Wallet.self,
            Category.self,
            Event.self,
            EventMember.self,
            EventLedgerTransaction.self,
            EventLedgerParticipant.self,
            EventSettlementSnapshot.self,
            EventSettlementTransfer.self,
            EventWalletExportRecord.self,
            RecurringRule.self,
            Transaction.self,
            TransactionLocation.self,
            Budget.self,
            Debt.self,
            SavingsGoal.self
        ]
    }
}

/// V2 schema — adds Supabase sync metadata to every model:
/// `syncUserID`, `updatedAt` (where missing), `deletedAt` (soft-delete tombstone),
/// and `needsSync` (local outbox flag). All additions are optional or defaulted,
/// so V1 → V2 is a **lightweight, non-destructive** migration (no data loss).
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        // Same model set as V1; the types now carry sync metadata.
        SchemaV1.models
    }
}

// MARK: - Migration Plan

/// Migration plan that SwiftData uses to migrate between schema versions.
/// Add new MigrationStages here as the schema evolves.
enum QuaraMoneySchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        // V1 → V2: purely additive (sync metadata). Lightweight = SwiftData adds
        // the new columns with their defaults; existing rows are preserved.
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
        ]
    }
}
