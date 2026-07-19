import Foundation
import SwiftData

/// Injectable save seam shared by Plan forms and list swipe deletion.
/// Model changes are applied only inside `perform`; any failed save restores the
/// captured pre-edit state before returning the error, and update notifications
/// are emitted only after a successful commit.
@MainActor
struct PlanMutationExecutor {
    var saveContext: (ModelContext) throws -> Void
    var postUpdate: () -> Void

    init(
        saveContext: @escaping (ModelContext) throws -> Void = { try $0.save() },
        postUpdate: @escaping () -> Void = {
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
        }
    ) {
        self.saveContext = saveContext
        self.postUpdate = postUpdate
    }

    func perform(
        in context: ModelContext,
        apply: () -> Void,
        rollback: () -> Void
    ) throws {
        apply()
        do {
            try saveContext(context)
            postUpdate()
        } catch {
            rollback()
            throw error
        }
    }

    func softDelete(_ model: any SyncTrackable, in context: ModelContext) throws {
        let previous = PlanTombstoneSnapshot(model: model)
        try perform(
            in: context,
            apply: { SoftDeleteService.delete(model) },
            rollback: { previous.restore(on: model) }
        )
    }
}

@MainActor
private struct PlanTombstoneSnapshot {
    let deletedAt: Date?
    let updatedAt: Date
    let needsSync: Bool

    init(model: any SyncTrackable) {
        deletedAt = model.deletedAt
        updatedAt = model.updatedAt
        needsSync = model.needsSync
    }

    func restore(on model: any SyncTrackable) {
        model.deletedAt = deletedAt
        model.updatedAt = updatedAt
        model.needsSync = needsSync
    }
}

nonisolated enum PlanCurrencyChangeDecision: Sendable, Equatable {
    case convert
    case keepNumber
    case cancel
}

nonisolated enum PlanCurrencyChangeResolver {
    static func convertedAmount(
        _ amount: Decimal,
        from source: String,
        to target: String,
        rates: [String: Double]
    ) -> Decimal? {
        CurrencyManager.convertOrNil(amount: amount, from: source, to: target, rates: rates)
    }

    static func resolve(
        amount: Decimal,
        from source: String,
        to target: String,
        rates: [String: Double],
        decision: PlanCurrencyChangeDecision
    ) -> Decimal? {
        switch decision {
        case .convert:
            return convertedAmount(amount, from: source, to: target, rates: rates)
        case .keepNumber:
            return amount
        case .cancel:
            return nil
        }
    }
}
