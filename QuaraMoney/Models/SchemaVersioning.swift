import SwiftData
import Foundation

// MARK: - Schema Versioning

/// V1 schema snapshot — captures the current model state as the baseline version.
/// All future schema changes should add a new VersionedSchema and corresponding MigrationStage.
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
            Budget.self,
            Debt.self,
            SavingsGoal.self
        ]
    }
}

// MARK: - Migration Plan

/// Migration plan that SwiftData uses to migrate between schema versions.
/// Add new MigrationStages here as the schema evolves.
enum QuaraMoneySchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // No migrations yet — V1 is the baseline.
        // Future example:
        // .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
        []
    }
}
