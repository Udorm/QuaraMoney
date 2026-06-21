import Foundation
import SwiftData

/// Models that carry Supabase sync metadata. All conformers already declare
/// `updatedAt` and `needsSync` (added in Phase 2), so the conformances are empty.
protocol SyncTrackable: AnyObject {
    var updatedAt: Date { get set }
    var needsSync: Bool { get set }
}

extension Wallet: SyncTrackable {}
extension Category: SyncTrackable {}
extension Event: SyncTrackable {}
extension EventMember: SyncTrackable {}
extension EventLedgerTransaction: SyncTrackable {}
extension EventLedgerParticipant: SyncTrackable {}
extension EventSettlementSnapshot: SyncTrackable {}
extension EventSettlementTransfer: SyncTrackable {}
extension EventWalletExportRecord: SyncTrackable {}
extension RecurringRule: SyncTrackable {}
extension Transaction: SyncTrackable {}
extension TransactionLocation: SyncTrackable {}
extension Budget: SyncTrackable {}
extension Debt: SyncTrackable {}
extension SavingsGoal: SyncTrackable {}

/// Stamps `updatedAt = now` and `needsSync = true` on locally inserted/edited
/// models so the sync engine's last-write-wins can detect changes.
///
/// Hooks `ModelContext.willSave` on the **main** context (where UI edits happen)
/// and stamps **synchronously** inside the notification (queue `nil`) so the
/// metadata is written as part of that same save. New objects inserted on any
/// context already default to `needsSync = true`, so background inserts are
/// covered without observing those contexts.
@MainActor
enum SyncMutationTracker {
    /// Set by the sync engine around its own writes (applying pulled rows, and
    /// clearing `needsSync` after a successful push) so those writes are not
    /// re-flagged as local changes — which would echo them back forever.
    static var isApplyingSyncChanges = false

    private static var started = false
    private static weak var observedContext: ModelContext?

    static func start(mainContext: ModelContext) {
        guard !started else { return }
        started = true
        observedContext = mainContext
        NotificationCenter.default.addObserver(
            forName: ModelContext.willSave,
            object: mainContext,
            queue: nil // synchronous: run inside the save, on the saving thread
        ) { _ in
            MainActor.assumeIsolated {
                stampPendingChanges()
            }
        }
    }

    private static func stampPendingChanges() {
        guard !isApplyingSyncChanges, let context = observedContext else { return }
        let now = Date()
        for case let model as SyncTrackable in context.insertedModelsArray {
            model.updatedAt = now
            model.needsSync = true
        }
        for case let model as SyncTrackable in context.changedModelsArray {
            model.updatedAt = now
            model.needsSync = true
        }
    }
}
