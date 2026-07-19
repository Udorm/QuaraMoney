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

// MARK: - Migration Plan

/// Migration plan that SwiftData uses to migrate between schema versions.
///
/// NOTE on the Supabase sync metadata (`syncUserID`, `updatedAt`, `deletedAt`,
/// `needsSync`), `Budget.categorySetDirty`, and explicit optional relationship
/// inverses (for example, `Category.multiCategoryBudgets`): these are
/// **additive, optional/defaulted**
/// properties, so they migrate automatically and non-destructively via
/// SwiftData's lightweight inference under the existing `SchemaV1` version —
/// the same way earlier fields (e.g. `Transaction.tags`, `storedRate`) were added.
///
/// A second `VersionedSchema` was intentionally NOT introduced: because both
/// versions would reference the same live model types they produce identical
/// checksums, which SwiftData rejects ("Duplicate version checksums detected").
/// The next **non-additive** change must add a real `SchemaV2` containing copied
/// (snapshot) model definitions plus an explicit `MigrationStage`.
enum QuaraMoneySchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
