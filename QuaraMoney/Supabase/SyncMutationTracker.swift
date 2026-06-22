import Foundation
import SwiftData
import CoreData

/// Models that carry Supabase sync metadata. All conformers already declare
/// `updatedAt` and `needsSync` (added in Phase 2), so the conformances are empty.
protocol SyncTrackable: AnyObject {
    var id: UUID { get }
    var updatedAt: Date { get set }
    var needsSync: Bool { get set }
    var deletedAt: Date? { get set }
}

extension SyncTrackable {
    /// Soft-deletes the model: it remains a row (a tombstone) so the deletion can
    /// sync as an ordinary field change. Reads must filter `deletedAt == nil`.
    func markSoftDeleted(_ date: Date = Date()) {
        deletedAt = date
        updatedAt = date
        needsSync = true
    }

    var isSoftDeleted: Bool { deletedAt != nil }
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
        
        // Observe SwiftData saves to stamp insertions/updates
        NotificationCenter.default.addObserver(
            forName: ModelContext.willSave,
            object: mainContext,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                stampPendingChanges()
            }
        }
        
        // Observe Core Data saves to safely capture deletions without property-access crashes on invalidated models
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextWillSave,
            object: nil,
            queue: nil
        ) { notification in
            MainActor.assumeIsolated {
                handleCoreDataWillSave(notification)
            }
        }
    }

    private static func handleCoreDataWillSave(_ notification: Notification) {
        guard !isApplyingSyncChanges,
              let moc = notification.object as? NSManagedObjectContext else { return }
        
        #if DEBUG
        print("Core Data willSave: \(moc.deletedObjects.count) deleted objects")
        #endif
        
        for obj in moc.deletedObjects {
            guard let entityName = obj.entity.name,
                  let table = SyncTableRegistry.tableName(forEntityName: entityName) else { continue }
            guard obj.entity.attributesByName.keys.contains("id") else { continue }
            if let id = obj.value(forKey: "id") as? UUID {
                #if DEBUG
                print("Core Data willSave tracking deletion: \(table) - \(id)")
                #endif
                SyncDeletionQueue.enqueue(table: table, id: id)
            }
        }
    }

    private static func stampPendingChanges() {
        guard !isApplyingSyncChanges, let context = observedContext else { return }
        let now = Date()
        
        let deletedIdentifiers = Set(context.deletedModelsArray.map { $0.persistentModelID })
        
        for model in context.insertedModelsArray {
            guard let trackable = model as? SyncTrackable else { continue }
            guard !deletedIdentifiers.contains(model.persistentModelID) else { continue }
            trackable.updatedAt = now
            trackable.needsSync = true
        }
        for model in context.changedModelsArray {
            guard let trackable = model as? SyncTrackable else { continue }
            guard !deletedIdentifiers.contains(model.persistentModelID) else { continue }
            trackable.updatedAt = now
            trackable.needsSync = true
        }
    }
}
