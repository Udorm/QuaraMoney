import XCTest
import SwiftData
@testable import QuaraMoney

/// Unit coverage for the network-independent data-integrity logic introduced by
/// the 3-phase sync hardening (commits 7d4904c / 77e56f0 / b2e025b):
///   • `SyncEngine.localChangeWins` — the last-write-wins / delete-LWW guard used
///     at every pull site.
///   • `SyncEngine.resolveRef` — foreign-key resolution that preserves an existing
///     link when the parent isn't present locally yet.
///   • `SyncEngine.writeBackServerTimestamps` — server-authoritative `updated_at`
///     write-back after a push.
///   • `SyncDeletionQueue` / `SyncImageDownloadQueue` — durable enqueue / dedupe /
///     remove / clear / Codable round-trip.
///
/// The two durable queues are process-global enums hardcoded (in production) to
/// `UserDefaults.standard`. To stay safe under XCTest's parallel execution this
/// suite injects a private `UserDefaults(suiteName:)` into each queue's `defaults`
/// for the duration of the test and restores `.standard` in tearDown, so it never
/// touches (and never races other classes on) the shared standard domain.
@MainActor
final class SyncEngineHardeningTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private var suiteName: String!
    private var suite: UserDefaults!
    private var savedDeletionDefaults: UserDefaults!
    private var savedImageDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        container = TestModelContainer.create()
        context = container.mainContext

        // A unique private domain per test instance — isolated from `.standard`.
        suiteName = "SyncEngineHardeningTests.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)

        savedDeletionDefaults = SyncDeletionQueue.defaults
        savedImageDefaults = SyncImageDownloadQueue.defaults
        SyncDeletionQueue.defaults = suite
        SyncImageDownloadQueue.defaults = suite
    }

    override func tearDown() {
        // Restore the production default first so no other class ever observes the
        // private suite, then tear the suite's persisted domain down.
        SyncDeletionQueue.defaults = savedDeletionDefaults
        SyncImageDownloadQueue.defaults = savedImageDefaults
        suite.removePersistentDomain(forName: suiteName)
        suite = nil
        suiteName = nil
        savedDeletionDefaults = nil
        savedImageDefaults = nil
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - localChangeWins (LWW / delete-LWW guard)

    func testLocalChangeWins_localNewerUnpushed_wins() {
        let remote = Date()
        let localNewer = remote.addingTimeInterval(60)
        XCTAssertTrue(SyncEngine.localChangeWins(localNeedsSync: true,
                                                 localUpdatedAt: localNewer,
                                                 remoteUpdatedAt: remote))
    }

    func testLocalChangeWins_localOlder_loses() {
        let remote = Date()
        let localOlder = remote.addingTimeInterval(-60)
        XCTAssertFalse(SyncEngine.localChangeWins(localNeedsSync: true,
                                                  localUpdatedAt: localOlder,
                                                  remoteUpdatedAt: remote))
    }

    func testLocalChangeWins_alreadySynced_alwaysLoses() {
        let remote = Date()
        let localNewer = remote.addingTimeInterval(60)
        // Even though local is newer, a row with no un-pushed change must yield to
        // the remote (otherwise an already-synced row could block a remote delete).
        XCTAssertFalse(SyncEngine.localChangeWins(localNeedsSync: false,
                                                  localUpdatedAt: localNewer,
                                                  remoteUpdatedAt: remote))
    }

    func testLocalChangeWins_equalTimestamps_loses() {
        // Strictly-greater comparison: a tie hands the row to the remote (server
        // wins), matching the inline `local.updatedAt > row.updated_at` semantics.
        let when = Date()
        XCTAssertFalse(SyncEngine.localChangeWins(localNeedsSync: true,
                                                  localUpdatedAt: when,
                                                  remoteUpdatedAt: when))
    }

    // MARK: - Budget category sync repair

    func testInvalidRemoteBudgetCategoryStatePreservesLocalSelectionAndQueuesRepair() throws {
        let category = Category(name: "Food", icon: "fork.knife", colorHex: "#000000", type: .expense)
        let julyBudget = Budget(amountLimit: 100)
        let augustBudget = Budget(amountLimit: 120)
        julyBudget.setTrackedCategories([category], targetKind: .categories)
        augustBudget.setTrackedCategories([category], targetKind: .categories)
        julyBudget.needsSync = false
        augustBudget.needsSync = false
        context.insert(category)
        context.insert(julyBudget)
        context.insert(augustBudget)
        try context.save()

        let repairTimestamp = Date(timeIntervalSince1970: 10_000)
        let shouldRepair = SyncEngine.applySyncedTrackedCategories(
            [],
            targetKind: .categories,
            to: julyBudget,
            repairTimestamp: repairTimestamp
        )

        XCTAssertTrue(shouldRepair)
        XCTAssertEqual(julyBudget.trackedCategoryIds, [category.id])
        XCTAssertEqual(augustBudget.trackedCategoryIds, [category.id])
        XCTAssertTrue(julyBudget.category === category)
        XCTAssertTrue(augustBudget.category === category)
        XCTAssertTrue(julyBudget.needsSync)
        XCTAssertFalse(augustBudget.needsSync)
        XCTAssertEqual(julyBudget.updatedAt, repairTimestamp)
    }

    func testExplicitRemoteTotalBudgetStillClearsLocalCategory() throws {
        let category = Category(name: "Food", icon: "fork.knife", colorHex: "#000000", type: .expense)
        let budget = Budget(amountLimit: 100)
        budget.setTrackedCategories([category], targetKind: .categories)
        budget.needsSync = false
        context.insert(category)
        context.insert(budget)
        try context.save()

        let shouldRepair = SyncEngine.applySyncedTrackedCategories(
            [],
            targetKind: .total,
            to: budget
        )

        XCTAssertFalse(shouldRepair)
        XCTAssertEqual(budget.targetKind, .total)
        XCTAssertTrue(budget.trackedCategoryIds.isEmpty)
        XCTAssertFalse(budget.needsSync)
    }

    // MARK: - resolveRef (FK resolution with link preservation)

    func testResolveRef_nonNilExistingID_resolvesToModel() throws {
        let wallet = Wallet(name: "Cash", currencyCode: "USD", icon: "banknote", colorHex: "#00FF00")
        context.insert(wallet)
        try context.save()

        let resolved = try SyncEngine.shared.resolveRef(Wallet.self, id: wallet.id, current: nil, in: context)
        XCTAssertIdentical(resolved, wallet)
    }

    func testResolveRef_nilID_clearsLink() throws {
        let current = Wallet(name: "Cash", currencyCode: "USD", icon: "banknote", colorHex: "#00FF00")
        context.insert(current)
        try context.save()

        // A nil id means the remote genuinely cleared the reference → drop the link
        // even when one currently exists.
        let resolved = try SyncEngine.shared.resolveRef(Wallet.self, id: nil, current: current, in: context)
        XCTAssertNil(resolved)
    }

    func testResolveRef_unresolvableNonNilID_preservesExistingLink() throws {
        let current = Wallet(name: "Cash", currencyCode: "USD", icon: "banknote", colorHex: "#00FF00")
        context.insert(current)
        try context.save()

        // A non-nil id that isn't present locally yet (e.g. parent's pull step
        // failed this cycle) must NOT sever the already-valid link — keep `current`.
        let missingID = UUID()
        let resolved = try SyncEngine.shared.resolveRef(Wallet.self, id: missingID, current: current, in: context)
        XCTAssertIdentical(resolved, current)
    }

    func testResolveRef_unresolvableNonNilID_withNoCurrent_returnsNil() throws {
        // No prior link to preserve → nothing to return.
        let resolved = try SyncEngine.shared.resolveRef(Wallet.self, id: UUID(), current: nil, in: context)
        XCTAssertNil(resolved)
    }

    // MARK: - writeBackServerTimestamps

    func testWriteBackServerTimestamps_mapsServerDatesOntoMatchingModels() {
        let walletA = Wallet(name: "A", currencyCode: "USD", icon: "a", colorHex: "#111111")
        let walletB = Wallet(name: "B", currencyCode: "KHR", icon: "b", colorHex: "#222222")
        let deviceClock = Date(timeIntervalSince1970: 1_000)
        walletA.updatedAt = deviceClock
        walletB.updatedAt = deviceClock

        let serverA = Date(timeIntervalSince1970: 2_000)
        let serverB = Date(timeIntervalSince1970: 3_000)
        let returned = [makeWalletRow(id: walletA.id, updatedAt: serverA),
                        makeWalletRow(id: walletB.id, updatedAt: serverB)]

        SyncEngine.shared.writeBackServerTimestamps(returned, to: [walletA, walletB])

        XCTAssertEqual(walletA.updatedAt, serverA)
        XCTAssertEqual(walletB.updatedAt, serverB)
    }

    func testWriteBackServerTimestamps_leavesUnreturnedModelsUntouched() {
        let walletA = Wallet(name: "A", currencyCode: "USD", icon: "a", colorHex: "#111111")
        let walletB = Wallet(name: "B", currencyCode: "KHR", icon: "b", colorHex: "#222222")
        let original = Date(timeIntervalSince1970: 1_000)
        walletA.updatedAt = original
        walletB.updatedAt = original

        // Server returned a row only for A; B's timestamp must be left as-is.
        let returned = [makeWalletRow(id: walletA.id, updatedAt: Date(timeIntervalSince1970: 5_000))]
        SyncEngine.shared.writeBackServerTimestamps(returned, to: [walletA, walletB])

        XCTAssertEqual(walletA.updatedAt, Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(walletB.updatedAt, original)
    }

    func testWriteBackServerTimestamps_emptyReturned_isNoOp() {
        let wallet = Wallet(name: "A", currencyCode: "USD", icon: "a", colorHex: "#111111")
        let original = Date(timeIntervalSince1970: 1_000)
        wallet.updatedAt = original

        SyncEngine.shared.writeBackServerTimestamps([SyncWalletRow](), to: [wallet])
        XCTAssertEqual(wallet.updatedAt, original)
    }

    private func makeWalletRow(id: UUID, updatedAt: Date) -> SyncWalletRow {
        SyncWalletRow(id: id, user_id: UUID(), name: "", currency_code: "USD",
                      icon: "", color_hex: "", is_archived: false,
                      created_at: Date(timeIntervalSince1970: 0), updated_at: updatedAt,
                      deleted_at: nil)
    }

    // MARK: - SyncDeletionQueue

    func testDeletionQueue_enqueueDedupesIdenticalEntries() {
        let id = UUID()
        SyncDeletionQueue.enqueue(table: "wallets", id: id)
        SyncDeletionQueue.enqueue(table: "wallets", id: id)
        XCTAssertEqual(SyncDeletionQueue.all().count, 1)
    }

    func testDeletionQueue_distinctEntriesCoexist() {
        let id = UUID()
        SyncDeletionQueue.enqueue(table: "wallets", id: id)
        SyncDeletionQueue.enqueue(table: "categories", id: id)   // same id, different table
        SyncDeletionQueue.enqueue(table: "wallets", id: UUID())  // same table, different id
        XCTAssertEqual(SyncDeletionQueue.all().count, 3)
    }

    func testDeletionQueue_removeDropsOnlyTheGivenEntry() {
        let keep = SyncDeletionQueue.Entry(table: "wallets", id: UUID())
        let drop = SyncDeletionQueue.Entry(table: "transactions", id: UUID())
        SyncDeletionQueue.enqueue(table: keep.table, id: keep.id)
        SyncDeletionQueue.enqueue(table: drop.table, id: drop.id)

        SyncDeletionQueue.remove(drop)

        XCTAssertEqual(SyncDeletionQueue.all(), [keep])
    }

    func testDeletionQueue_clearEmptiesQueue() {
        SyncDeletionQueue.enqueue(table: "wallets", id: UUID())
        SyncDeletionQueue.enqueue(table: "events", id: UUID())
        SyncDeletionQueue.clear()
        XCTAssertTrue(SyncDeletionQueue.all().isEmpty)
    }

    func testDeletionQueue_survivesEncodeDecodeRoundTrip() {
        let id = UUID()
        SyncDeletionQueue.enqueue(table: "transactions", id: id)

        // `all()` decodes from the injected store, so a non-empty round-trip proves
        // Codable persistence through UserDefaults.
        let reread = SyncDeletionQueue.all()
        XCTAssertEqual(reread, [SyncDeletionQueue.Entry(table: "transactions", id: id)])
    }

    func testDeletionQueue_isolatedFromStandardDomain() {
        // The injected suite must be empty independent of whatever `.standard`
        // holds; assert our reads only see what this test enqueued.
        XCTAssertTrue(SyncDeletionQueue.all().isEmpty)
        SyncDeletionQueue.enqueue(table: "wallets", id: UUID())
        XCTAssertEqual(SyncDeletionQueue.all().count, 1)
    }

    // MARK: - SyncImageDownloadQueue

    func testImageQueue_enqueueDedupesIdenticalEntries() {
        let entry = SyncImageDownloadQueue.Entry(kind: .transactionPhoto, id: UUID(), path: "a/b.jpg")
        SyncImageDownloadQueue.enqueue(entry)
        SyncImageDownloadQueue.enqueue(entry)
        XCTAssertEqual(SyncImageDownloadQueue.all().count, 1)
    }

    func testImageQueue_distinguishesByKindIDAndPath() {
        let id = UUID()
        SyncImageDownloadQueue.enqueue(.init(kind: .transactionPhoto, id: id, path: "p.jpg"))
        SyncImageDownloadQueue.enqueue(.init(kind: .eventCover, id: id, path: "p.jpg"))      // different kind
        SyncImageDownloadQueue.enqueue(.init(kind: .transactionPhoto, id: id, path: "q.jpg")) // different path
        XCTAssertEqual(SyncImageDownloadQueue.all().count, 3)
    }

    func testImageQueue_removeDropsOnlyTheGivenEntry() {
        let keep = SyncImageDownloadQueue.Entry(kind: .memberAvatar, id: UUID(), path: "keep.jpg")
        let drop = SyncImageDownloadQueue.Entry(kind: .eventCover, id: UUID(), path: "drop.jpg")
        SyncImageDownloadQueue.enqueue(keep)
        SyncImageDownloadQueue.enqueue(drop)

        SyncImageDownloadQueue.remove(drop)

        XCTAssertEqual(SyncImageDownloadQueue.all(), [keep])
    }

    func testImageQueue_clearEmptiesQueue() {
        SyncImageDownloadQueue.enqueue(.init(kind: .transactionPhoto, id: UUID(), path: "a.jpg"))
        SyncImageDownloadQueue.clear()
        XCTAssertTrue(SyncImageDownloadQueue.all().isEmpty)
    }

    func testImageQueue_survivesEncodeDecodeRoundTrip() {
        let entry = SyncImageDownloadQueue.Entry(kind: .eventCover, id: UUID(), path: "covers/x.png")
        SyncImageDownloadQueue.enqueue(entry)
        XCTAssertEqual(SyncImageDownloadQueue.all(), [entry])
    }
}
