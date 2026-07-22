import XCTest
import SwiftData
@testable import QuaraMoney

@MainActor
private final class SyncTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

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

    override func tearDown() async throws {
        SyncRealtime.shared.resetForTesting()
        await SyncEngine.shared.resetCoordinatorForTesting()
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
        try await super.tearDown()
    }

    private func waitUntil(
        _ message: String = "Timed out waiting for coordinator state",
        _ predicate: @MainActor () -> Bool
    ) async {
        for _ in 0..<10_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail(message)
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
        julyBudget.categorySetDirty = false
        augustBudget.categorySetDirty = false
        context.insert(category)
        context.insert(julyBudget)
        context.insert(augustBudget)
        try context.save()

        let repairTimestamp = Date(timeIntervalSince1970: 10_000)
        let result = SyncEngine.applySyncedTrackedCategories(
            cloudCategoryIDs: [],
            resolvedCategoriesByID: [:],
            targetKind: .categories,
            to: julyBudget,
            repairTimestamp: repairTimestamp
        )

        XCTAssertEqual(result.action, .emptyRepaired)
        XCTAssertEqual(julyBudget.trackedCategoryIds, [category.id])
        XCTAssertEqual(augustBudget.trackedCategoryIds, [category.id])
        XCTAssertNil(julyBudget.category)
        XCTAssertNil(augustBudget.category)
        XCTAssertEqual(julyBudget.categories?.map(\.id), [category.id])
        XCTAssertEqual(augustBudget.categories?.map(\.id), [category.id])
        XCTAssertTrue(julyBudget.categorySetDirty)
        XCTAssertTrue(julyBudget.needsSync)
        XCTAssertFalse(augustBudget.needsSync)
        XCTAssertEqual(julyBudget.updatedAt, repairTimestamp)
    }

    func testExplicitRemoteTotalBudgetStillClearsLocalCategory() throws {
        let category = Category(name: "Food", icon: "fork.knife", colorHex: "#000000", type: .expense)
        let budget = Budget(amountLimit: 100)
        budget.setTrackedCategories([category], targetKind: .categories)
        budget.needsSync = false
        budget.categorySetDirty = false
        context.insert(category)
        context.insert(budget)
        try context.save()

        let result = SyncEngine.applySyncedTrackedCategories(
            cloudCategoryIDs: [],
            resolvedCategoriesByID: [:],
            targetKind: .total,
            to: budget
        )

        XCTAssertEqual(result.action, .totalCleared)
        XCTAssertEqual(budget.targetKind, .total)
        XCTAssertTrue(budget.trackedCategoryIds.isEmpty)
        XCTAssertFalse(budget.categorySetDirty)
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

    // MARK: - Single-flight coordinator

    func testCoordinatorIsSingleFlightAndLatchesIdentitylessMidRunTrigger() async {
        let engine = SyncEngine.shared
        let gate = SyncTestGate()
        var runs = 0
        var activeRuns = 0
        var maximumActiveRuns = 0
        engine.configureSyncContext(context)
        engine.setTestHooks(runner: {
            runs += 1
            activeRuns += 1
            maximumActiveRuns = max(maximumActiveRuns, activeRuns)
            if runs == 1 { await gate.wait() }
            activeRuns -= 1
            return .success
        })

        engine.enqueueSync(reason: .foreground)
        await waitUntil { runs == 1 }
        engine.enqueueSync(reason: .localSave)
        engine.enqueueSync(reason: .localSave)
        gate.open()
        await engine.waitForCoordinatorIdleForTesting()

        XCTAssertEqual(runs, 2)
        XCTAssertEqual(maximumActiveRuns, 1)
    }

    func testAwaitableTicketResolvesOnlyAfterItsRunCompletes() async {
        let engine = SyncEngine.shared
        let gate = SyncTestGate()
        var runs = 0
        var resolved = false
        engine.configureSyncContext(context)
        engine.setTestHooks(runner: {
            runs += 1
            await gate.wait()
            return .success
        })

        let waiter = Task { @MainActor in
            let outcome = await engine.requestSyncAndWait(reason: .manualRefresh)
            resolved = true
            return outcome
        }
        await waitUntil { runs == 1 }
        XCTAssertFalse(resolved)
        gate.open()
        let outcome = await waiter.value
        guard case .success = outcome else { return XCTFail("Expected successful ticket") }
        XCTAssertTrue(resolved)
        XCTAssertEqual(engine.pendingTicketCountForTesting, 0)
    }

    func testMaintenanceFollowUpEnqueuesWithoutDeadlock() async {
        let engine = SyncEngine.shared
        var runs = 0
        engine.configureSyncContext(context)
        engine.setTestHooks(runner: {
            runs += 1
            if runs == 1 { engine.enqueueSync(reason: .maintenance) }
            return .success
        })

        engine.enqueueSync(reason: .foreground)
        await engine.waitForCoordinatorIdleForTesting()
        XCTAssertEqual(runs, 2)
    }

    func testGenerationClearTerminatesTicketAndDoesNotRearmOldRun() async {
        let engine = SyncEngine.shared
        let gate = SyncTestGate()
        var runs = 0
        engine.configureSyncContext(context)
        engine.setTestHooks(runner: {
            runs += 1
            await gate.wait()
            return .success
        })
        let waiter = Task { @MainActor in
            await engine.requestSyncAndWait(reason: .manualRefresh)
        }
        await waitUntil { runs == 1 }

        engine.stopSyncLifecycle()
        let outcome = await waiter.value
        guard case .cancelled = outcome else { return XCTFail("Generation clear must cancel tickets") }
        XCTAssertEqual(engine.pendingTicketCountForTesting, 0)
        gate.open()
        await engine.waitForCoordinatorIdleForTesting()
        XCTAssertEqual(runs, 1)
    }

    func testSameGenerationCancellationUsesBoundedBackoffAndStops() async {
        let engine = SyncEngine.shared
        engine.configureSyncContext(context)
        engine.setTestHooks(runner: { .cancelled })

        engine.enqueueSync(reason: .foreground)
        await engine.waitForCoordinatorIdleForTesting()

        XCTAssertEqual(engine.coordinatorRunCount, 4)
        XCTAssertNil(engine.lastError)
    }

    func testMaintenancePreResponseEchoIsReclassifiedAndSuppressed() async {
        let engine = SyncEngine.shared
        let id = UUID()
        let timestamp = Date(timeIntervalSince1970: 1234.123456)
        let identity = SyncEngine.EventIdentity(table: "budgets", id: id, updatedAt: timestamp)
        var runs = 0
        engine.configureSyncContext(context)
        engine.setTestHooks(runner: {
            runs += 1
            if runs == 1 {
                XCTAssertTrue(engine.receiveRealtimeEvent(identity))
                engine.registerFingerprintForTesting(table: "budgets", id: id, updatedAt: timestamp)
            }
            return .success
        })

        engine.enqueueSync(reason: .foreground)
        await engine.waitForCoordinatorIdleForTesting()
        XCTAssertEqual(runs, 1)
    }

    func testFingerprintMatchIsCanonicalIdempotentAndExpires() {
        let engine = SyncEngine.shared
        var clock = Date(timeIntervalSince1970: 10_000)
        let id = UUID()
        engine.setTestHooks(now: { clock })
        engine.registerFingerprintForTesting(
            table: "wallets",
            id: id,
            updatedAt: Date(timeIntervalSince1970: 1_234.1234564)
        )

        // Both values round to the same canonical microsecond.
        let replayTimestamp = Date(timeIntervalSince1970: 1_234.12345639)
        XCTAssertTrue(engine.isOwnEcho(table: "wallets", id: id, updatedAt: replayTimestamp))
        XCTAssertTrue(engine.isOwnEcho(table: "wallets", id: id, updatedAt: replayTimestamp))
        clock = clock.addingTimeInterval(61)
        XCTAssertFalse(engine.isOwnEcho(table: "wallets", id: id, updatedAt: replayTimestamp))
    }

    func testGenuineRemoteIdentityStillSchedulesOneRun() async {
        let engine = SyncEngine.shared
        var runs = 0
        engine.configureSyncContext(context)
        engine.setTestHooks(runner: {
            runs += 1
            return .success
        })
        let identity = SyncEngine.EventIdentity(table: "wallets", id: UUID(), updatedAt: Date())

        XCTAssertTrue(engine.receiveRealtimeEvent(identity))
        await engine.waitForCoordinatorIdleForTesting()
        XCTAssertEqual(runs, 1)
    }

    func testRealtimeInjectedOwnEchoDoesNotSchedule() async {
        let engine = SyncEngine.shared
        let realtime = SyncRealtime.shared
        let id = UUID()
        let timestamp = Date(timeIntervalSince1970: 2_000.123456)
        var runs = 0
        engine.configureSyncContext(context)
        engine.setTestHooks(runner: {
            runs += 1
            return .success
        })
        engine.registerFingerprintForTesting(table: "wallets", id: id, updatedAt: timestamp)
        realtime.setDebounceDelayForTesting(.milliseconds(5))

        realtime.injectPayloadForTesting(
            identity: .init(table: "wallets", id: id, updatedAt: timestamp),
            context: context
        )
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(runs, 0)
    }

    func testRealtimeInjectedGenuineIdentitySchedulesAfterDebounce() async {
        let engine = SyncEngine.shared
        let realtime = SyncRealtime.shared
        var runs = 0
        engine.configureSyncContext(context)
        engine.setTestHooks(runner: {
            runs += 1
            return .success
        })
        realtime.setDebounceDelayForTesting(.milliseconds(5))

        realtime.injectPayloadForTesting(
            identity: .init(table: "wallets", id: UUID(), updatedAt: Date()),
            context: context
        )
        try? await Task.sleep(for: .milliseconds(20))
        await engine.waitForCoordinatorIdleForTesting()

        XCTAssertEqual(runs, 1)
    }

    func testRealtimeInjectedUnfingerprintablePayloadStillSchedules() async {
        let engine = SyncEngine.shared
        let realtime = SyncRealtime.shared
        var runs = 0
        engine.configureSyncContext(context)
        engine.setTestHooks(runner: {
            runs += 1
            return .success
        })
        realtime.setDebounceDelayForTesting(.milliseconds(5))

        realtime.injectPayloadForTesting(identity: nil, context: context)
        try? await Task.sleep(for: .milliseconds(20))
        await engine.waitForCoordinatorIdleForTesting()

        XCTAssertEqual(runs, 1)
    }

    func testCancellationIsNotReclassifiedAsImageDownloadFailure() {
        XCTAssertFalse(SyncEngine.shouldQueueImageFailureForTesting(CancellationError()))
        XCTAssertFalse(SyncEngine.shouldQueueImageFailureForTesting(URLError(.cancelled)))
        XCTAssertTrue(SyncEngine.shouldQueueImageFailureForTesting(URLError(.notConnectedToInternet)))
    }

    // MARK: - Sign-out and account-transition safety

    func testFlushAbsorbsLocalSaveDebounceAndRunsUntilClean() async {
        let engine = SyncEngine.shared
        var pending = true
        var runs = 0
        engine.configureSyncContext(context)
        engine.installPendingLocalSaveDebounceForTesting()
        engine.setTestHooks(
            runner: {
                runs += 1
                pending = false
                return .success
            },
            pendingChanges: { pending }
        )

        let result = await engine.flushBeforeSignOut()
        guard case .success = result else { return XCTFail("Expected clean sign-out barrier") }
        XCTAssertEqual(runs, 1)
        XCTAssertFalse(engine.hasPendingLocalSaveDebounceForTesting)
        XCTAssertFalse(pending)
    }

    func testEditArrivingDuringInflightSyncIsFlushedBeforeBarrierReturns() async {
        let engine = SyncEngine.shared
        let gate = SyncTestGate()
        var pending = false
        var runs = 0
        engine.configureSyncContext(context)
        engine.setTestHooks(
            runner: {
                runs += 1
                if runs == 1 { await gate.wait() }
                if runs == 2 { pending = false }
                return .success
            },
            pendingChanges: { pending }
        )
        engine.enqueueSync(reason: .foreground)
        await waitUntil { runs == 1 }
        pending = true
        engine.installPendingLocalSaveDebounceForTesting()
        let barrier = Task { @MainActor in await engine.flushBeforeSignOut() }
        gate.open()

        let result = await barrier.value
        guard case .success = result else { return XCTFail("Barrier failed") }
        XCTAssertEqual(runs, 2)
        XCTAssertFalse(pending)
    }

    func testTerminalFlushFailureBlocksAuthenticationSignOutAndWipe() async {
        let engine = SyncEngine.shared
        var authenticationCalls = 0
        var wipeCalls = 0
        engine.configureSyncContext(context)
        engine.setTestHooks(
            runner: { .failed(.init(message: "offline")) },
            pendingChanges: { true }
        )

        do {
            try await SupabaseAuthManager.performProtectedSignOut(
                flush: { await engine.flushBeforeSignOut() },
                authenticationSignOut: { authenticationCalls += 1 },
                canWipe: { _ in true },
                wipe: { _ in wipeCalls += 1; return true }
            )
            XCTFail("Expected sign-out refusal")
        } catch {}

        XCTAssertEqual(authenticationCalls, 0)
        XCTAssertEqual(wipeCalls, 0)
    }

    func testPostAuthenticationMutationCheckBlocksWipe() async {
        var authenticationCalls = 0
        var wipeCalls = 0
        do {
            try await SupabaseAuthManager.performProtectedSignOut(
                flush: { .success(7) },
                authenticationSignOut: { authenticationCalls += 1 },
                canWipe: { _ in false },
                wipe: { _ in wipeCalls += 1; return true }
            )
            XCTFail("Expected TOCTOU refusal")
        } catch {}
        XCTAssertEqual(authenticationCalls, 1)
        XCTAssertEqual(wipeCalls, 0)
    }

    func testFinalWipeRecheckCanStillRefuseLateMutation() async {
        var authenticationCalls = 0
        var wipeCalls = 0
        do {
            try await SupabaseAuthManager.performProtectedSignOut(
                flush: { .success(9) },
                authenticationSignOut: { authenticationCalls += 1 },
                canWipe: { _ in true },
                wipe: { _ in wipeCalls += 1; return false }
            )
            XCTFail("Expected final wipe refusal")
        } catch {}
        XCTAssertEqual(authenticationCalls, 1)
        XCTAssertEqual(wipeCalls, 1)
    }

    func testMutationRevisionAdvancesWhenLocalSaveIsStamped() {
        SyncMutationTracker.resetMutationRevisionForTesting()
        let wallet = Wallet(name: "Cash", currencyCode: "USD", icon: "banknote", colorHex: "#000000")
        context.insert(wallet)

        SyncMutationTracker.stampPendingChangesForTesting(in: context)

        XCTAssertEqual(SyncMutationTracker.localMutationRevision, 1)
        XCTAssertTrue(wallet.needsSync)
    }

    func testAccountSwitchBackstopRefusesPreviousOwnerDirtyRows() {
        let previous = UUID()
        let current = UUID()
        XCTAssertFalse(SyncEngine.accountSwitchMayWipe(
            previousOwner: previous,
            currentOwner: current,
            hasPendingChanges: true
        ))
        XCTAssertTrue(SyncEngine.accountSwitchMayWipe(
            previousOwner: previous,
            currentOwner: current,
            hasPendingChanges: false
        ))
    }

    // MARK: - Two-outcome pull apply

    func testByteIdenticalWalletMetadataCorrectionPersistsWithoutVisibleChange() throws {
        let engine = SyncEngine.shared
        let owner = UUID()
        let timestamp = Date(timeIntervalSince1970: 12_345)
        let wallet = Wallet(name: "Cash", currencyCode: "USD", icon: "banknote", colorHex: "#123456")
        wallet.updatedAt = timestamp
        wallet.needsSync = true
        context.insert(wallet)
        try engine.withSyncWriteGuard { try context.save() }
        engine.resetDidApplyRemoteChangesForTesting()
        let row = SyncWalletRow(
            id: wallet.id, user_id: owner, name: wallet.name,
            currency_code: wallet.currencyCode, icon: wallet.icon,
            color_hex: wallet.colorHex, is_archived: wallet.isArchived,
            created_at: wallet.createdAt, updated_at: timestamp, deleted_at: nil
        )

        try engine.applyWalletRows([row], context: context)

        XCTAssertFalse(wallet.needsSync)
        XCTAssertEqual(wallet.syncUserID, owner)
        XCTAssertFalse(engine.didApplyRemoteChangesForTesting)
        XCTAssertFalse(context.hasChanges)
    }

    func testLWWRejectedWalletDoesNotClaimVisibleRemoteChange() throws {
        let engine = SyncEngine.shared
        let remoteTimestamp = Date(timeIntervalSince1970: 10_000)
        let wallet = Wallet(name: "Local", currencyCode: "USD", icon: "banknote", colorHex: "#123456")
        wallet.updatedAt = remoteTimestamp.addingTimeInterval(10)
        wallet.needsSync = true
        context.insert(wallet)
        try engine.withSyncWriteGuard { try context.save() }
        engine.resetDidApplyRemoteChangesForTesting()
        let row = SyncWalletRow(
            id: wallet.id, user_id: UUID(), name: "Remote",
            currency_code: wallet.currencyCode, icon: wallet.icon,
            color_hex: wallet.colorHex, is_archived: wallet.isArchived,
            created_at: wallet.createdAt, updated_at: remoteTimestamp, deleted_at: nil
        )

        try engine.applyWalletRows([row], context: context)

        XCTAssertEqual(wallet.name, "Local")
        XCTAssertTrue(wallet.needsSync)
        XCTAssertFalse(engine.didApplyRemoteChangesForTesting)
    }

    func testVisibleWalletChangeSetsRemoteApplySignal() throws {
        let engine = SyncEngine.shared
        let localTimestamp = Date(timeIntervalSince1970: 10_000)
        let wallet = Wallet(name: "Old", currencyCode: "USD", icon: "banknote", colorHex: "#123456")
        wallet.updatedAt = localTimestamp
        wallet.needsSync = false
        context.insert(wallet)
        try engine.withSyncWriteGuard { try context.save() }
        engine.resetDidApplyRemoteChangesForTesting()
        let row = SyncWalletRow(
            id: wallet.id, user_id: UUID(), name: "New",
            currency_code: wallet.currencyCode, icon: wallet.icon,
            color_hex: wallet.colorHex, is_archived: wallet.isArchived,
            created_at: wallet.createdAt, updated_at: localTimestamp.addingTimeInterval(1), deleted_at: nil
        )

        try engine.applyWalletRows([row], context: context)

        XCTAssertEqual(wallet.name, "New")
        XCTAssertTrue(engine.didApplyRemoteChangesForTesting)
    }

    func testBudgetEvaluationWithoutThresholdCrossingDoesNotDirtyContext() throws {
        let budget = Budget(amountLimit: 100)
        budget.alertMode = .nearingOver
        budget.lastAlertThreshold = 0
        context.insert(budget)
        try SyncEngine.shared.withSyncWriteGuard { try context.save() }
        BudgetNotificationService.shared.configure(modelContext: context)

        BudgetNotificationService.shared.evaluateStore()

        XCTAssertFalse(context.hasChanges)
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
