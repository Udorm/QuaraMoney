import CryptoKit
import Foundation
import Combine
import SwiftData
import Supabase

/// Bidirectional sync between local SwiftData and Supabase.
///
/// Phase 3c slice: wallets, categories, transactions. Strategy:
///  • Push: rows with `needsSync == true` are upserted (parents before children),
///    then flagged `needsSync = false`.
///  • Pull: rows changed since a per-table cursor (`updated_at`) are applied
///    locally with row-level last-write-wins.
///  • `SyncMutationTracker.isApplyingSyncChanges` is held true around local writes
///    so the engine's own saves are not re-flagged as user edits.
///
/// Runs on the main context/actor (modest data volumes); network awaits don't
/// block the UI. Foreign keys to entities not yet synced (event/debt/savings/
/// recurring) are intentionally left null until those entities are added.
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published var lastError: String?

    /// Whether the first full sync (the one-time upload of pre-existing local data)
    /// has completed. Persisted so it survives relaunches.
    @Published private(set) var hasCompletedInitialSync =
        UserDefaults.standard.bool(forKey: "hasCompletedInitialSync.v1")

    /// True during the very first sync — the UI shows a "setting up" state since
    /// uploading an existing dataset can take a moment.
    var isInitialSyncInProgress: Bool { isSyncing && !hasCompletedInitialSync }

    // MARK: - First sign-in conflict

    /// Raised when this device has pre-existing local data AND the cloud already
    /// holds data for the newly signed-in account. Sync is blocked until resolved.
    /// `.resolving` is held while the chosen resolution's wipe + sync runs, so the
    /// modal stays up and ordinary sync triggers remain gated until it finishes.
    enum ConflictState: Equatable { case none, pendingUserDecision, resolving }
    @Published private(set) var conflictState: ConflictState = .none

    private var autoSyncStarted = false
    private var autoSyncContext: ModelContext?
    private var debounceTask: Task<Void, Never>?

    /// Held true while the first-sign-in conflict check is in flight (it does a
    /// network round-trip). Set synchronously before the `await` so no auto-sync
    /// can push local data in the gap before the check either clears it (no
    /// conflict) or raises `conflictState = .pendingUserDecision` (conflict).
    private var isAwaitingInitialConflictCheck = false

    /// Set true during a `syncNow` whenever a pull fetches rows changed on the
    /// server since our cursor. Gates the completion broadcast so an idle sync
    /// (nothing pushed, nothing pulled) stays silent and doesn't needlessly wake
    /// every view-model observer.
    private var didApplyRemoteChanges = false

    private init() {}

    // MARK: - Auto-sync triggers

    /// Wires automatic sync: a debounced push after local saves. Idempotent.
    /// Safe to call when sync is off — `syncNow` guards on `isOperational`.
    func enableAutoSync(context: ModelContext) {
        guard !autoSyncStarted else { return }
        autoSyncStarted = true
        autoSyncContext = context
        NotificationCenter.default.addObserver(
            forName: .dataDidUpdate,
            object: nil,
            queue: nil
        ) { notification in
            // Ignore the engine's OWN completion broadcast (posted with
            // `object: self` at the end of `syncNow`). Without this filter the
            // sync self-triggers: the post is handled asynchronously (see the
            // main-actor hop below), by which point `syncNow` has returned and
            // its `defer` cleared `isApplyingSyncChanges`, so `handleLocalSave`
            // mistakes the engine's broadcast for a fresh user edit and schedules
            // another sync — a loop that runs every ~2s with no real changes.
            guard !(notification.object is SyncEngine) else { return }
            // `.dataDidUpdate` may be posted from background work (the detached
            // first-launch seeding task, sync apply, etc.), so we can't assume
            // main-thread isolation here — hop onto the main actor to schedule
            // the debounced sync instead of trapping via `assumeIsolated`.
            Task { @MainActor in
                SyncEngine.shared.handleLocalSave()
            }
        }
    }

    /// Triggers a sync only when sync is enabled, configured, and signed in.
    /// Use for foreground / post-sign-in triggers.
    /// No-ops while a first-sign-in conflict awaits user resolution.
    func syncIfOperational(context: ModelContext) async {
        #if DEBUG
        print("[SyncEngine] syncIfOperational called. isOperational: \(SupabaseFeatureFlags.isOperational)")
        #endif
        guard SupabaseFeatureFlags.isOperational else {
            #if DEBUG
            print("[SyncEngine] syncIfOperational skipped: not operational")
            #endif
            return
        }
        guard conflictState == .none else {
            #if DEBUG
            print("[SyncEngine] syncIfOperational skipped: conflict resolution pending")
            #endif
            return
        }
        await syncNow(context: context)
    }

    /// Flushes pending local changes while the current account is still signed in.
    /// Call before sign-out so an account switch (which wipes the local cache)
    /// can't lose un-pushed edits. Uses the context registered by `enableAutoSync`.
    ///
    /// Waits for any in-flight sync to finish first: `syncNow` returns
    /// immediately when a sync is already running, so without the wait the
    /// "flush" could be a silent no-op while edits newer than the running sync's
    /// push phase stayed local — and the subsequent wipe would destroy them.
    func flushBeforeSignOut() async {
        guard let context = autoSyncContext else { return }
        await waitForSyncIdle()
        await syncIfOperational(context: context)
    }

    /// Suspends until no sync is in flight. Poll-based: syncs are short-lived and
    /// this only runs on sign-out.
    func waitForSyncIdle() async {
        while isSyncing {
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    /// True when the device still holds anything a sync would push (dirty rows or
    /// queued deletions). Used as the final gate before a sign-out wipe.
    func hasPendingLocalChanges() -> Bool {
        guard let context = autoSyncContext else { return false }
        if !SyncDeletionQueue.all().isEmpty { return true }
        func has<T>(_ descriptor: FetchDescriptor<T>) -> Bool {
            var d = descriptor
            d.fetchLimit = 1
            return (try? context.fetch(d))?.isEmpty == false
        }
        if has(FetchDescriptor<Wallet>(predicate: #Predicate { $0.needsSync })) { return true }
        if has(FetchDescriptor<Category>(predicate: #Predicate { $0.needsSync })) { return true }
        if has(FetchDescriptor<Transaction>(predicate: #Predicate { $0.needsSync })) { return true }
        if has(FetchDescriptor<Event>(predicate: #Predicate { $0.needsSync })) { return true }
        if has(FetchDescriptor<EventMember>(predicate: #Predicate { $0.needsSync })) { return true }
        if has(FetchDescriptor<EventLedgerTransaction>(predicate: #Predicate { $0.needsSync })) { return true }
        if has(FetchDescriptor<EventLedgerParticipant>(predicate: #Predicate { $0.needsSync })) { return true }
        if has(FetchDescriptor<EventSettlementSnapshot>(predicate: #Predicate { $0.needsSync })) { return true }
        if has(FetchDescriptor<EventSettlementTransfer>(predicate: #Predicate { $0.needsSync })) { return true }
        if has(FetchDescriptor<EventWalletExportRecord>(predicate: #Predicate { $0.needsSync })) { return true }
        if has(FetchDescriptor<Debt>(predicate: #Predicate { $0.needsSync })) { return true }
        if has(FetchDescriptor<SavingsGoal>(predicate: #Predicate { $0.needsSync })) { return true }
        if has(FetchDescriptor<Budget>(predicate: #Predicate { $0.needsSync })) { return true }
        if has(FetchDescriptor<RecurringRule>(predicate: #Predicate { $0.needsSync })) { return true }
        if has(FetchDescriptor<TransactionLocation>(predicate: #Predicate { $0.needsSync })) { return true }
        return false
    }

    /// Clears the local cache on sign-out (shared-device privacy). Guarded so it
    /// creates no tombstones (the cloud copy is untouched). Caller must ensure
    /// pending changes were flushed first, so nothing un-synced is lost.
    ///
    /// After the wipe the device is unowned again (owner key removed), so we
    /// re-seed the preset categories immediately — otherwise a signed-out
    /// local-only user is left with an empty category picker until the next app
    /// launch re-seeds. Safe against the old duplicate-sync bug: the device is
    /// unowned (matches a fresh install), and canonical keys + the cloud's
    /// unique index + `stampAndDedupe` collapse these into the cloud's rows on
    /// the next sign-in.
    func wipeForSignOut() {
        guard let context = autoSyncContext else { return }
        do {
            SyncMutationTracker.isApplyingSyncChanges = true
            defer { SyncMutationTracker.isApplyingSyncChanges = false }
            wipeLocalData(context: context)
            resetSyncState()
        }
        lastSyncDate = nil
        UserDefaults.standard.removeObject(forKey: Self.localOwnerKey)
        // Device is now unowned — restore the preset set (mirrors the fresh-install
        // seeding in QuaraMoneyApp.setup()) so the local-only user immediately has
        // categories again instead of waiting for the next launch.
        do {
            try CategoryCatalog.seedDefaultsIfEmpty(in: context)
            for def in CategoryCatalog.all where def.ensureOnLaunch {
                _ = try CategoryCatalog.fetchOrCreate(key: def.key, in: context)
            }
            try context.save()
        } catch {
            #if DEBUG
            print("[SignOut] Failed to re-seed default categories: \(error)")
            #endif
        }
        // Profile identity (name/avatar) belongs to the account, not the device.
        ProfileSyncService.shared.clearLocal()
        // Wake view models that cache fetched arrays — @Query views update on
        // their own, but a VM-driven screen could otherwise keep showing the
        // signed-out account's numbers. Tagged `object: self` so auto-sync
        // ignores it (see enableAutoSync).
        NotificationCenter.default.post(name: .dataDidUpdate, object: self)
    }

    // MARK: - First sign-in conflict detection & resolution

    /// Checks whether this first-ever sign-in creates a conflict: local store has
    /// data AND the cloud already has data for this account. Only fires when
    /// `localOwnerKey` is nil (device never associated with any account before).
    ///
    /// Returns `true` and sets `conflictState = .pendingUserDecision` when both
    /// sides have data — the caller must skip sync and wait for the user to decide.
    /// Returns `false` when no conflict exists; normal sync may proceed.
    enum FirstSignInCheckResult {
        /// Sync may proceed; ownership is stamped (or was already resolved).
        case noConflict
        /// Both sides have real data — `conflictState` was raised; sync must wait.
        case conflict
        /// The cloud probe failed (network). Sync MUST NOT proceed — an unknown
        /// cloud state plus a push equals potential duplication. Retried on the
        /// next sync trigger.
        case checkFailed
    }

    func checkFirstSignInConflict(context: ModelContext) async -> FirstSignInCheckResult {
        guard UserDefaults.standard.string(forKey: Self.localOwnerKey) == nil else { return .noConflict }
        guard SupabaseFeatureFlags.isOperational,
              let client = SupabaseManager.shared.client,
              let uid = client.auth.currentUser?.id else { return .noConflict }

        // Block all auto-sync for the duration of this (network) check, so a local
        // save can't push before we know whether there's a conflict to resolve.
        isAwaitingInitialConflictCheck = true
        defer { isAwaitingInitialConflictCheck = false }

        // No local data — no conflict. Stamp ownership so this check doesn't
        // re-run on every subsequent sign-in.
        //
        // "Local data" must mean anything a sync would PUSH, not just wallets:
        // default categories are seeded on every fresh install (with fresh random
        // UUIDs), so on a returning sign-in they'd be uploaded and DUPLICATED
        // against the account's existing categories. Checking only wallets missed
        // the common "fresh install, no wallets yet, only default categories" case
        // and silently pushed those duplicates. Treat categories as local data too.
        guard localHasSyncableData(context) else {
            UserDefaults.standard.set(uid.uuidString, forKey: Self.localOwnerKey)
            return .noConflict
        }

        // Cloud data check. Use do/catch so a network failure is never
        // misidentified as "cloud empty", and never falls through to a sync.
        let cloudHasData: Bool
        do {
            cloudHasData = try await cloudHasSyncableData(client, uid)
        } catch {
            #if DEBUG
            print("[SyncEngine] checkFirstSignInConflict: cloud query failed — will retry: \(error)")
            #endif
            lastError = "Couldn't verify your account's cloud data. Will retry."
            return .checkFailed
        }

        guard cloudHasData else {
            // Cloud is empty — no conflict. Stamp ownership and allow normal sync.
            UserDefaults.standard.set(uid.uuidString, forKey: Self.localOwnerKey)
            return .noConflict
        }

        // When everything on this device is an untouched default seed (fresh
        // install or post-sign-out relaunch), there is nothing worth asking
        // about: adopt the cloud silently instead of raising a destructive-
        // sounding modal whose wrong answer ("keep this device") would replace
        // the user's entire cloud history with 20 empty categories.
        if isPristineDefaultDataset(context) {
            #if DEBUG
            print("[SyncEngine] first sign-in: local data is an untouched default seed — adopting cloud")
            #endif
            SyncMutationTracker.isApplyingSyncChanges = true
            wipeLocalData(context: context)
            resetSyncState()
            SyncMutationTracker.isApplyingSyncChanges = false
            UserDefaults.standard.set(uid.uuidString, forKey: Self.localOwnerKey)
            NotificationCenter.default.post(name: .dataDidUpdate, object: self)
            return .noConflict
        }

        // Both device and cloud have data — ask the user.
        // localOwnerKey is intentionally NOT stamped here; resolution functions
        // stamp it once the user decides, so a force-quit retriggers this check.
        conflictState = .pendingUserDecision
        return .conflict
    }

    /// True when the device's only syncable data is the auto-seeded default
    /// category set, untouched: no content in any other entity, and every live
    /// category still matches its `CategoryCatalog` definition (canonical key
    /// present, name unchanged in a shipped language). A renamed or user-created
    /// category makes this false — the conservative answer, which falls back to
    /// asking the user.
    private func isPristineDefaultDataset(_ context: ModelContext) -> Bool {
        func has<T>(_ descriptor: FetchDescriptor<T>) -> Bool {
            var d = descriptor
            d.fetchLimit = 1
            return (try? context.fetch(d))?.isEmpty == false
        }
        if has(FetchDescriptor<Wallet>(predicate: #Predicate { $0.deletedAt == nil })) { return false }
        if has(FetchDescriptor<Transaction>(predicate: #Predicate { $0.deletedAt == nil })) { return false }
        if has(FetchDescriptor<Event>(predicate: #Predicate { $0.deletedAt == nil })) { return false }
        if has(FetchDescriptor<Debt>(predicate: #Predicate { $0.deletedAt == nil })) { return false }
        if has(FetchDescriptor<SavingsGoal>(predicate: #Predicate { $0.deletedAt == nil })) { return false }
        if has(FetchDescriptor<Budget>(predicate: #Predicate { $0.deletedAt == nil })) { return false }
        if has(FetchDescriptor<RecurringRule>(predicate: #Predicate { $0.deletedAt == nil })) { return false }
        let categories = (try? context.fetch(FetchDescriptor<Category>(
            predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        for category in categories {
            guard let key = category.canonicalKey,
                  let def = CategoryCatalog.definition(forKey: key),
                  def.type == category.type,
                  CategoryCatalog.matchDefinition(name: category.name, type: category.type)?.key == key
            else { return false }
        }
        return true
    }

    /// True when the device holds any data a sync would push — across the main
    /// user-content entities, not just wallets/categories. A dataset of only
    /// (say) debts or events must still count as a potential first-sign-in merge
    /// conflict, otherwise it would silently auto-merge. Filters tombstones.
    private func localHasSyncableData(_ context: ModelContext) -> Bool {
        func has<T>(_ descriptor: FetchDescriptor<T>) -> Bool {
            var d = descriptor
            d.fetchLimit = 1
            return (try? context.fetch(d))?.isEmpty == false
        }
        if has(FetchDescriptor<Wallet>(predicate: #Predicate { $0.deletedAt == nil })) { return true }
        if has(FetchDescriptor<Category>(predicate: #Predicate { $0.deletedAt == nil })) { return true }
        if has(FetchDescriptor<Transaction>(predicate: #Predicate { $0.deletedAt == nil })) { return true }
        if has(FetchDescriptor<Event>(predicate: #Predicate { $0.deletedAt == nil })) { return true }
        if has(FetchDescriptor<Debt>(predicate: #Predicate { $0.deletedAt == nil })) { return true }
        if has(FetchDescriptor<SavingsGoal>(predicate: #Predicate { $0.deletedAt == nil })) { return true }
        if has(FetchDescriptor<Budget>(predicate: #Predicate { $0.deletedAt == nil })) { return true }
        if has(FetchDescriptor<RecurringRule>(predicate: #Predicate { $0.deletedAt == nil })) { return true }
        return false
    }

    /// True when the cloud already holds user-content rows for this account, across
    /// the same entity set as `localHasSyncableData`. Throws on a network error so
    /// the caller can distinguish "empty" from "couldn't check" and avoid pushing
    /// duplicates into an unknown cloud state.
    private func cloudHasSyncableData(_ client: SupabaseClient, _ uid: UUID) async throws -> Bool {
        struct IDOnly: Decodable { let id: UUID }
        let tables = ["transactions", "wallets", "categories", "events",
                      "debts", "savings_goals", "budgets", "recurring_rules"]
        for table in tables {
            let rows: [IDOnly] = try await client.from(table)
                .select("id")
                .eq("user_id", value: uid.uuidString)
                .limit(1)
                .execute().value
            if !rows.isEmpty { return true }
        }
        return false
    }

    /// Resolves the conflict by discarding local data and pulling everything from
    /// the cloud. Call when the user chooses "Use cloud data".
    func resolveUseCloud() async {
        guard let context = autoSyncContext,
              let uid = SupabaseManager.shared.client?.auth.currentUser?.id else { return }
        conflictState = .resolving
        do {
            SyncMutationTracker.isApplyingSyncChanges = true
            wipeLocalData(context: context)
            resetSyncState()
            SyncMutationTracker.isApplyingSyncChanges = false
        }
        NotificationCenter.default.post(name: .dataDidUpdate, object: self)
        UserDefaults.standard.set(uid.uuidString, forKey: Self.localOwnerKey)
        // Call syncNow directly: syncIfOperational is gated while resolving.
        await syncNow(context: context)
        finishResolution()
    }

    /// Resolves the conflict by deleting all cloud data for this account and
    /// uploading the device's local data. Call when the user chooses "Keep this
    /// device's data".
    func resolveKeepLocal() async {
        guard let context = autoSyncContext,
              let client = SupabaseManager.shared.client,
              let uid = client.auth.currentUser?.id else { return }
        conflictState = .resolving

        // Wipe the cloud copy child → parent so foreign keys don't block deletes.
        for table in Self.childFirstTableNames {
            do {
                try await client.from(table).delete().eq("user_id", value: uid.uuidString).execute()
            } catch {
                #if DEBUG
                print("[SyncEngine] resolveKeepLocal: failed to clear cloud table \(table): \(error)")
                #endif
            }
        }
        SyncDeletionQueue.clear()

        // Force every local row to push, regardless of its prior sync state —
        // this device's data is now the source of truth. Clearing cursors too so
        // the subsequent pull re-establishes them from the freshly pushed rows.
        resetSyncState()
        forceAllLocalNeedsSync(context: context)

        UserDefaults.standard.set(uid.uuidString, forKey: Self.localOwnerKey)
        // Call syncNow directly: syncIfOperational is gated while resolving.
        await syncNow(context: context)
        finishResolution()
    }

    /// Dismisses the conflict without choosing a side and turns cloud sync off, so
    /// the app reverts to fully local until the user re-enables it. Neither dataset
    /// is touched. `localOwnerKey` is intentionally left unstamped so the conflict
    /// is re-detected the next time the user enables sync and signs in.
    ///
    /// Disables the flag BEFORE clearing `conflictState` so the app's
    /// `conflictState == .none` observer can't (re)start Realtime — `isOperational`
    /// is already false by then.
    func deferConflictDecision() {
        guard conflictState == .pendingUserDecision else { return }
        SupabaseFeatureFlags.isSyncEnabled = false
        SyncRealtime.shared.stop()
        lastError = nil
        conflictState = .none
    }

    /// Settles `conflictState` after a resolution's sync. On success the modal
    /// dismisses; on failure it returns to the decision screen so the surfaced
    /// `lastError` is visible and the user can retry.
    private func finishResolution() {
        conflictState = (lastError == nil) ? .none : .pendingUserDecision
    }

    /// Flags every local synced row `needsSync = true` so the next push uploads
    /// the full dataset. Runs under the sync-write guard so the mutation tracker
    /// doesn't also rewrite `updatedAt` on every record.
    private func forceAllLocalNeedsSync(context: ModelContext) {
        withSyncWriteGuard {
            func flag<T: PersistentModel & SyncTrackable>(_ type: T.Type) {
                if let rows = try? context.fetch(FetchDescriptor<T>()) {
                    for row in rows { row.needsSync = true }
                }
            }
            flag(Wallet.self); flag(Category.self); flag(Event.self); flag(Debt.self)
            flag(SavingsGoal.self); flag(RecurringRule.self); flag(EventMember.self)
            flag(EventLedgerTransaction.self); flag(EventLedgerParticipant.self)
            flag(EventSettlementSnapshot.self); flag(EventSettlementTransfer.self)
            flag(EventWalletExportRecord.self); flag(Transaction.self)
            flag(Budget.self); flag(TransactionLocation.self)
            try? context.save()
        }
    }

    private func handleLocalSave() {
        // Ignore the engine's own writes; only react to genuine local edits.
        // Also stand down while a first-sign-in conflict is unresolved: an
        // auto-sync here would push local data (e.g. freshly seeded default
        // categories) before the user has chosen a side — the resolver runs its
        // own controlled sync once a choice is made.
        guard !SyncMutationTracker.isApplyingSyncChanges,
              SupabaseFeatureFlags.isOperational,
              conflictState == .none,
              !isAwaitingInitialConflictCheck,
              autoSyncContext != nil else { return }
        #if DEBUG
        print("[SyncEngine] handleLocalSave called. Debouncing auto-sync.")
        #endif
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, let ctx = self.autoSyncContext else { return }
            #if DEBUG
            print("[SyncEngine] Debounced auto-sync trigger firing.")
            #endif
            await self.syncNow(context: ctx)
        }
    }

    enum SyncError: LocalizedError {
        case notOperational
        case noUser
        var errorDescription: String? {
            switch self {
            case .notOperational: return "Cloud sync is not enabled or configured."
            case .noUser: return "You must be signed in to sync."
            }
        }
    }

    func syncNow(context: ModelContext) async {
        #if DEBUG
        print("[SyncEngine] syncNow called. isSyncing: \(isSyncing)")
        #endif
        guard !isSyncing else {
            #if DEBUG
            print("[SyncEngine] syncNow ignored: already syncing")
            #endif
            return
        }
        // Hard stop while the first-sign-in conflict modal is up: nothing may push
        // or pull until the user resolves it. The resolvers set `conflictState` to
        // `.resolving` (not `.pendingUserDecision`) before calling this, so their
        // own sync still runs.
        guard conflictState != .pendingUserDecision, !isAwaitingInitialConflictCheck else {
            #if DEBUG
            print("[SyncEngine] syncNow blocked: first-sign-in conflict pending/checking")
            #endif
            return
        }
        // A password-recovery sign-in defers the whole sync pipeline until the
        // user has set their new password: an un-owned store would otherwise
        // raise the first-sign-in conflict modal (via the check below) on top of
        // the reset sheet. The app re-triggers sync when the reset finishes.
        guard !SupabaseAuthManager.shared.passwordRecoveryPending else {
            #if DEBUG
            print("[SyncEngine] syncNow deferred: password recovery in progress")
            #endif
            return
        }
        guard SupabaseFeatureFlags.isOperational, let client = SupabaseManager.shared.client else {
            #if DEBUG
            print("[SyncEngine] syncNow failed: not operational")
            #endif
            lastError = SyncError.notOperational.errorDescription
            return
        }
        guard let uid = client.auth.currentUser?.id else {
            #if DEBUG
            print("[SyncEngine] syncNow failed: no user")
            #endif
            lastError = SyncError.noUser.errorDescription
            return
        }

        // An un-owned store must PASS the first-sign-in check before anything
        // can push. Previously a failed cloud probe fell through to a full sync,
        // which could upload freshly seeded default categories into an account
        // that already has data — the category-duplication bug. `.conflict`
        // raises the resolution modal; `.checkFailed` surfaces the error and the
        // next trigger retries. This also closes the foreground-sync path, which
        // used to bypass the check entirely.
        if UserDefaults.standard.string(forKey: Self.localOwnerKey) == nil {
            switch await checkFirstSignInConflict(context: context) {
            case .noConflict:
                break
            case .conflict:
                #if DEBUG
                print("[SyncEngine] syncNow blocked: first-sign-in conflict raised")
                #endif
                return
            case .checkFailed:
                #if DEBUG
                print("[SyncEngine] syncNow blocked: first-sign-in cloud check failed")
                #endif
                return
            }
        }

        isSyncing = true
        lastError = nil
        defer {
            isSyncing = false
            #if DEBUG
            print("[SyncEngine] syncNow finished (isSyncing set to false)")
            #endif
        }

        // NOTE on the sync-write guard: it is NOT held across this whole
        // operation. syncNow runs on the main actor and suspends at every
        // network await, where the UI is free to save user edits — a blanket
        // guard blinded SyncMutationTracker to those saves, so edits (and
        // deletions) made while a sync was in flight were never flagged and
        // never synced. Instead, each of the engine's own synchronous
        // write+save spans is wrapped in `withSyncWriteGuard`.
        didApplyRemoteChanges = false

        // Each table step runs in its own do/catch and records a failure instead
        // of aborting the rest of the sync. Before, a single throwing row (network
        // blip mid-table, one constraint-violating or oversized row, a failed image
        // upload) aborted every later table on every cycle — one poison row could
        // wedge the whole sync. Now an isolated failure is surfaced via `lastError`
        // while the other tables still sync; the failed table keeps its `needsSync`
        // flags / cursor unchanged and simply retries next cycle.
        var failures: [String] = []
        func runStep(_ label: String, _ work: () async throws -> Void) async {
            do { try await work() }
            catch {
                failures.append("\(label): \(error.localizedDescription)")
                #if DEBUG
                print("[SyncEngine] step failed — \(label): \(error)")
                #endif
            }
        }

        // One-time cleanup of rows a previous account left on this device
        // (legacy builds didn't wipe on account switch). Must run before any
        // push: their ids exist in the cloud under the other account, so
        // upserting them trips RLS and wedges the table's push.
        await runStep("reconcile foreign rows") { try self.purgeForeignRows(context, uid: uid) }

        // Propagate local hard-deletes first (set deleted_at on the server).
        await runStep("push deletions") { try await self.pushDeletions(client) }

        // Pull (parents → children) BEFORE pushing. This is what makes last-write-
        // wins actually arbitrate a concurrent edit: pulling first lets a newer
        // remote row overwrite a stale local row and clear its `needsSync` (so the
        // push below skips it), while a genuinely newer local row stays flagged and
        // wins on push. New local-only rows aren't touched by pull and still push.
        await runStep("pull wallets") { try await self.pullWallets(context, client, uid) }
        await runStep("pull categories") { try await self.pullCategories(context, client, uid) }
        // Merge same-canonical-key duplicates the pull may have surfaced (e.g.
        // two devices minted "Debt" on demand while offline). Winner selection is
        // deterministic, so every device converges on the same survivor; losers
        // become tombstones and the re-pointed children push below.
        await runStep("dedupe categories") {
            try self.withSyncWriteGuard {
                try CategoryCatalog.dedupeCanonicalCategories(in: context, owner: uid)
                try context.save()
            }
        }
        // A freshly-adopted account whose cloud has no categories (brand-new
        // sign-up, or an account-switch wipe via reconcileAccountIfNeeded) would
        // otherwise be left with an empty category picker. Seed the presets once —
        // after the pull, so an account that DID have cloud categories already has
        // them and `seedDefaultsIfEmpty`'s count==0 guard makes this a no-op.
        // Gated to the initial sync so an established store (where the user may
        // have intentionally deleted categories) is never re-seeded. Not under the
        // sync-write guard: these are this device's new rows and must push up.
        if !hasCompletedInitialSync {
            await runStep("seed default categories") {
                try CategoryCatalog.seedDefaultsIfEmpty(in: context)
                try context.save()
            }
        }
        await runStep("pull events") { try await self.pullEvents(context, client, uid) }
        await runStep("pull debts") { try await self.pullDebts(context, client, uid) }
        await runStep("pull savings goals") { try await self.pullSavingsGoals(context, client, uid) }
        await runStep("pull recurring rules") { try await self.pullRecurringRules(context, client, uid) }
        await runStep("pull event members") { try await self.pullEventMembers(context, client, uid) }
        await runStep("pull event ledger transactions") { try await self.pullEventLedgerTransactions(context, client, uid) }
        await runStep("pull event ledger participants") { try await self.pullEventLedgerParticipants(context, client, uid) }
        await runStep("pull event settlement snapshots") { try await self.pullEventSettlementSnapshots(context, client, uid) }
        await runStep("pull event settlement transfers") { try await self.pullEventSettlementTransfers(context, client, uid) }
        await runStep("pull event wallet export records") { try await self.pullEventWalletExportRecords(context, client, uid) }
        await runStep("pull transactions") { try await self.pullTransactions(context, client, uid) }
        await runStep("pull budgets") { try await self.pullBudgets(context, client, uid) }
        await runStep("pull transaction locations") { try await self.pullTransactionLocations(context, client, uid) }

        // Push parents → children. Rows the pull just reconciled are no longer dirty.
        await runStep("push wallets") { try await self.pushWallets(context, client, uid) }
        await runStep("push categories") { try await self.pushCategories(context, client, uid) }
        await runStep("push events") { try await self.pushEvents(context, client, uid) }
        await runStep("push debts") { try await self.pushDebts(context, client, uid) }
        await runStep("push savings goals") { try await self.pushSavingsGoals(context, client, uid) }
        await runStep("push recurring rules") { try await self.pushRecurringRules(context, client, uid) }
        await runStep("push event members") { try await self.pushEventMembers(context, client, uid) }
        await runStep("push event ledger transactions") { try await self.pushEventLedgerTransactions(context, client, uid) }
        await runStep("push event ledger participants") { try await self.pushEventLedgerParticipants(context, client, uid) }
        await runStep("push event settlement snapshots") { try await self.pushEventSettlementSnapshots(context, client, uid) }
        await runStep("push event settlement transfers") { try await self.pushEventSettlementTransfers(context, client, uid) }
        await runStep("push event wallet export records") { try await self.pushEventWalletExportRecords(context, client, uid) }
        await runStep("push transactions") { try await self.pushTransactions(context, client, uid) }
        await runStep("push budgets") { try await self.pushBudgets(context, client, uid) }
        await runStep("push transaction locations") { try await self.pushTransactionLocations(context, client, uid) }

        // Account profile (display name + avatar) — single-row pull/push.
        await runStep("profile") { try await ProfileSyncService.shared.sync(client, uid: uid) }

        // Retry any receipt/cover/avatar images that failed to download earlier.
        // Self-healing: successes clear themselves, failures stay queued. Never
        // counts as a sync failure (it can't block other data).
        await drainImageDownloads(client, context)

        // Pulled edits/deletions can change balances; the @Transient cache on
        // existing Wallet instances won't notice, so refresh them all.
        invalidateAllWalletBalanceCaches(context)

        if failures.isEmpty {
            lastSyncDate = Date()
            if !hasCompletedInitialSync {
                hasCompletedInitialSync = true
                UserDefaults.standard.set(true, forKey: "hasCompletedInitialSync.v1")
            }
        } else {
            // Some tables failed; surface them but keep what succeeded. The initial
            // sync isn't marked complete on a partial failure, so it retries.
            lastError = failures.joined(separator: "\n")
        }

        // Refresh active view models only when a pull actually applied remote
        // changes — an idle no-op sync shouldn't churn the UI. Tagged with
        // `object: self` so auto-sync ignores it (see `enableAutoSync`).
        if didApplyRemoteChanges {
            // Old-client budget writes converge immediately after pull. Derived
            // completion reconciliation stays local-only under the synchronous guard.
            let maintenanceRates = CurrencyManager.shared.rates
            _ = try? PlanDataMaintenance.run(in: context, ownerID: uid, rates: maintenanceRates)
            withSyncWriteGuard {
                _ = try? SavingsGoalReconciler.reconcileAll(in: context, markNeedsSync: false)
            }
            NotificationCenter.default.post(name: .dataDidUpdate, object: self)
        }
    }

    // MARK: - Account scoping

    nonisolated private static let localOwnerKey = "localStoreOwnerID.v1"

    /// True once this device's local store has been claimed by a cloud account
    /// (first sign-in / conflict resolution completed). `nonisolated` so the
    /// background launch-seeding task can read it without hopping to the main actor.
    ///
    /// Used to gate default-category seeding: an owned device must get its
    /// categories from the cloud via sync, never re-seed them locally — otherwise
    /// a re-seed after any sync wipe mints fresh random UUIDs and pushes duplicates.
    nonisolated static var isLocalStoreAccountOwned: Bool {
        UserDefaults.standard.string(forKey: localOwnerKey) != nil
    }

    /// The account that currently owns this device's local store, if any.
    /// `nonisolated` for the background launch-maintenance task.
    nonisolated static var localOwnerUUID: UUID? {
        UserDefaults.standard.string(forKey: localOwnerKey).flatMap(UUID.init(uuidString:))
    }

    private static let allTableNames = [
        "wallets", "categories", "events", "recurring_rules", "savings_goals", "debts",
        "transactions", "transaction_locations", "budgets", "budget_categories",
        "event_members", "event_ledger_transactions", "event_ledger_participants",
        "event_settlement_snapshots", "event_settlement_transfers", "event_wallet_export_records"
    ]

    /// Tables ordered child → parent, so a bulk cloud delete doesn't trip foreign
    /// keys (mirrors `wipeLocalData`'s model order; join table before its parent).
    private static let childFirstTableNames = [
        "transaction_locations", "transactions",
        "event_wallet_export_records", "event_settlement_transfers", "event_settlement_snapshots",
        "event_ledger_participants", "event_ledger_transactions", "event_members",
        "budget_categories", "budgets", "recurring_rules", "savings_goals", "debts", "events",
        "categories", "wallets"
    ]

    /// Ensures the local cache belongs to the currently signed-in account. If a
    /// *different* account previously owned the local data, that data is already
    /// in the cloud, so we wipe the local cache and reset sync state before
    /// adopting the new account. Prevents cross-account data leakage when users
    /// switch accounts on the same device.
    ///
    /// Call on sign-in, before syncing. The wipe runs under the sync-write guard
    /// so it does NOT create deletion tombstones (which would delete the previous
    /// account's *cloud* rows).
    func reconcileAccountIfNeeded(context: ModelContext) {
        guard let uid = SupabaseManager.shared.client?.auth.currentUser?.id else { return }
        let owner = UserDefaults.standard.string(forKey: Self.localOwnerKey).flatMap(UUID.init(uuidString:))
        // nil owner = first sign-in; checkFirstSignInConflict handles ownership
        // claiming for that case so we don't stomp the nil before it can check.
        guard let owner else { return }
        guard owner != uid else { return }
        // Different account owned this device — wipe and take ownership now.
        do {
            SyncMutationTracker.isApplyingSyncChanges = true
            defer { SyncMutationTracker.isApplyingSyncChanges = false }
            wipeLocalData(context: context)
            resetSyncState()
        }
        lastSyncDate = nil
        UserDefaults.standard.set(uid.uuidString, forKey: Self.localOwnerKey)
        // The previous account's profile identity must not leak to this one.
        ProfileSyncService.shared.clearLocal()
        NotificationCenter.default.post(name: .dataDidUpdate, object: self)
    }

    /// Bulk-deletes all synced models locally (children before parents to respect
    /// the Category→Transaction `.deny` rule). The on-disk store is a cache; the
    /// data remains in the cloud for the previous account.
    private func wipeLocalData(context: ModelContext) {
        let orderedChildFirst: [any PersistentModel.Type] = [
            TransactionLocation.self, Transaction.self,
            EventWalletExportRecord.self, EventSettlementTransfer.self, EventSettlementSnapshot.self,
            EventLedgerParticipant.self, EventLedgerTransaction.self, EventMember.self,
            Budget.self, RecurringRule.self, SavingsGoal.self, Debt.self, Event.self,
            Category.self, Wallet.self
        ]
        for type in orderedChildFirst {
            try? context.delete(model: type)
        }
        try? context.save()
    }

    private func resetSyncState() {
        for table in Self.allTableNames {
            UserDefaults.standard.removeObject(forKey: Self.cursorKey(table))
        }
        SyncDeletionQueue.clear()
        SyncImageDownloadQueue.clear()
        hasCompletedInitialSync = false
        UserDefaults.standard.set(false, forKey: "hasCompletedInitialSync.v1")
    }

    // MARK: - Foreign-row reconciliation (legacy account-switch cleanup)

    private static func foreignPurgeKey(_ uid: UUID) -> String { "foreignRowsPurged.v1.\(uid.uuidString)" }

    /// Removes (or adopts) rows that were synced under a DIFFERENT account and
    /// left on this device by builds that predate the account-reconcile wipe.
    ///
    /// Pushing such rows into the current account trips the cloud's RLS: their
    /// ids already exist there under the other account, so the upsert's UPDATE
    /// arm fails its USING check ("new row violates row-level security policy")
    /// and the whole table's push wedges. Beyond the error, pushing them would
    /// mix two accounts' financial data.
    ///
    /// The other account's cloud copy is intact, so:
    ///  • foreign *content* rows (transactions, events, debts, …) are dropped
    ///    locally — no tombstones (the guard suppresses deletion tracking), the
    ///    other account keeps its data;
    ///  • foreign wallets/categories still referenced by CURRENT-account rows
    ///    are adopted instead: fresh id, owner reassigned, flagged to push as
    ///    this account's own row (a hard delete would orphan the references —
    ///    and `Category.transactions` is `.deny`, so it would abort the save).
    ///    Adopted categories keep their canonical key, so the dedupe pass merges
    ///    them into the account's own copy right after the next pull.
    ///
    /// Runs once per (device, account); the reconcile wipe prevents new foreign
    /// rows from appearing afterwards.
    private func purgeForeignRows(_ context: ModelContext, uid: UUID) throws {
        guard !UserDefaults.standard.bool(forKey: Self.foreignPurgeKey(uid)) else { return }
        try withSyncWriteGuard {
            func foreignRows<T: PersistentModel & SyncTrackable>(_ type: T.Type) -> [T] {
                ((try? context.fetch(FetchDescriptor<T>())) ?? []).filter {
                    guard let owner = ($0 as? any SyncOwned)?.syncOwner else { return false }
                    return owner != uid
                }
            }
            var dropped = 0
            func drop<T: PersistentModel & SyncTrackable>(_ type: T.Type) {
                for row in foreignRows(type) {
                    context.delete(row)
                    dropped += 1
                }
            }
            // Content rows, children before parents (mirrors wipeLocalData).
            drop(TransactionLocation.self)
            drop(Transaction.self)
            drop(EventWalletExportRecord.self)
            drop(EventSettlementTransfer.self)
            drop(EventSettlementSnapshot.self)
            drop(EventLedgerParticipant.self)
            drop(EventLedgerTransaction.self)
            drop(EventMember.self)
            drop(Budget.self)
            drop(RecurringRule.self)
            drop(SavingsGoal.self)
            drop(Debt.self)
            drop(Event.self)

            var adopted = 0
            func adopt(_ row: some PersistentModel & SyncTrackable) {
                // Fresh identity: becomes a brand-new LOCAL row (owner cleared,
                // not assigned) — so if the current account already has its own
                // copy of this category in the cloud, the dedupe ranking treats
                // the adopted one as local-only and merges it INTO the real row,
                // never the other way around.
                if let c = row as? Category {
                    c.id = UUID()
                    c.syncUserID = nil
                }
                if let w = row as? Wallet {
                    w.id = UUID()
                    w.syncUserID = nil
                }
                row.updatedAt = Date()
                row.needsSync = true
                adopted += 1
            }

            // Foreign content is gone; any remaining reference to a foreign
            // wallet/category comes from the CURRENT account's data.
            let goals = (try? context.fetch(FetchDescriptor<SavingsGoal>())) ?? []
            for w in foreignRows(Wallet.self) {
                let referenced = !(w.outgoingTransactions ?? []).isEmpty
                    || !(w.incomingTransactions ?? []).isEmpty
                    || !(w.recurringRules ?? []).isEmpty
                    || goals.contains { $0.linkedWallet === w }
                if referenced { adopt(w) } else { context.delete(w); dropped += 1 }
            }
            for c in foreignRows(Category.self) {
                let referenced = !(c.transactions ?? []).isEmpty
                    || !(c.budgets ?? []).isEmpty
                    || !(c.recurringRules ?? []).isEmpty
                if referenced { adopt(c) } else { context.delete(c); dropped += 1 }
            }

            try context.save()
            if dropped > 0 || adopted > 0 {
                #if DEBUG
                print("[SyncEngine] purged \(dropped) foreign rows, adopted \(adopted) (previous-account leftovers)")
                #endif
            }
            UserDefaults.standard.set(true, forKey: Self.foreignPurgeKey(uid))
        }
    }

    // MARK: - Push

    private func pushWallets(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<Wallet>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let snapshot = updatedAtSnapshot(pending)
        let rows = pending.map { w in
            SyncWalletRow(id: w.id, user_id: uid, name: w.name, currency_code: w.currencyCode,
                      icon: w.icon, color_hex: w.colorHex, is_archived: w.isArchived,
                      created_at: w.createdAt, updated_at: w.updatedAt, deleted_at: w.deletedAt)
        }
        let returned = try await upsertInChunks(rows, to: "wallets", client)
        finishPush(returned, pending: pending, snapshot: snapshot, uid: uid, context: context)
    }

    private func pushCategories(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let snapshot = updatedAtSnapshot(pending)
        let rows = pending.map { c in
            SyncCategoryRow(id: c.id, user_id: uid, name: c.name, icon: c.icon, color_hex: c.colorHex,
                        type: c.type.rawValue, is_system: c.isSystem, canonical_key: c.canonicalKey,
                        created_at: c.createdAt, updated_at: c.updatedAt, deleted_at: c.deletedAt)
        }
        let returned = try await upsertInChunks(rows, to: "categories", client)
        finishPush(returned, pending: pending, snapshot: snapshot, uid: uid, context: context)
    }

    private func pushTransactions(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let snapshot = updatedAtSnapshot(pending)
        var rows: [SyncTransactionRow] = []
        rows.reserveCapacity(pending.count)
        for t in pending {
            var photoPath: String?
            if let data = t.photoData {
                photoPath = imagePath(uid, "transactions", t.id)
                let hash = Self.sha256(data)
                if t.photoUploadedHash != hash {
                    try await uploadImage(data, to: photoPath!, client) // throws → sync retries (needsSync kept)
                    t.photoUploadedHash = hash
                }
            } else {
                t.photoUploadedHash = nil
            }
            rows.append(SyncTransactionRow(
                id: t.id, user_id: uid, type: t.type.rawValue, date: t.date, note: t.note,
                tags: t.tags, exclude_from_reports: t.excludeFromReports, amount: t.amount,
                currency_code: t.currencyCode, exchange_rate: t.exchangeRate, stored_rate: t.storedRate,
                photo_path: photoPath,
                category_id: t.category?.id,
                event_id: t.event?.id,
                source_wallet_id: t.sourceWallet?.id,
                destination_wallet_id: t.destinationWallet?.id,
                recurring_rule_id: t.recurringRule?.id,
                debt_id: t.debt?.id,
                savings_goal_id: t.savingsGoal?.id,
                savings_is_withdrawal: t.savingsIsWithdrawal,
                created_at: t.createdAt, updated_at: t.updatedAt, deleted_at: t.deletedAt))
        }
        let returned = try await upsertInChunks(rows, to: "transactions", client)
        finishPush(returned, pending: pending, snapshot: snapshot, uid: uid, context: context)
    }

    private func pushEvents(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<Event>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let snapshot = updatedAtSnapshot(pending)
        var rows: [SyncEventRow] = []
        rows.reserveCapacity(pending.count)
        for e in pending {
            var coverPath: String?
            if let data = e.coverImageData {
                coverPath = imagePath(uid, "events", e.id)
                let hash = Self.sha256(data)
                if e.coverImageUploadedHash != hash {
                    try await uploadImage(data, to: coverPath!, client)
                    e.coverImageUploadedHash = hash
                }
            } else {
                e.coverImageUploadedHash = nil
            }
            rows.append(SyncEventRow(id: e.id, user_id: uid, title: e.title, start_date: e.startDate,
                         end_date: e.endDate, total_budget: e.totalBudget, cover_image_path: coverPath,
                         notes: e.notes, icon: e.icon, color_hex: e.colorHex, location: e.location,
                         status: e.status, currency_code: e.currencyCode, ledger_revision: e.ledgerRevision,
                         confirmed_settlement_revision: e.confirmedSettlementRevision,
                         ledger_mode: e.ledgerMode.rawValue, latitude: e.latitude, longitude: e.longitude,
                         updated_at: e.updatedAt, deleted_at: e.deletedAt))
        }
        let returned = try await upsertInChunks(rows, to: "events", client)
        finishPush(returned, pending: pending, snapshot: snapshot, uid: uid, context: context)
    }

    private func pushDebts(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<Debt>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let snapshot = updatedAtSnapshot(pending)
        let rows = pending.map { d in
            SyncDebtRow(id: d.id, user_id: uid, person_name: d.personName, total_amount: d.totalAmount,
                        currency_code: d.currencyCode, due_date: d.dueDate, type: d.type.rawValue, note: d.note,
                        date_created: d.dateCreated, is_completed: d.isCompleted, created_at: d.createdAt,
                        updated_at: d.updatedAt, deleted_at: d.deletedAt)
        }
        let returned = try await upsertInChunks(rows, to: "debts", client)
        finishPush(returned, pending: pending, snapshot: snapshot, uid: uid, context: context)
    }

    private func pushSavingsGoals(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<SavingsGoal>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let snapshot = updatedAtSnapshot(pending)
        let rows = pending.map { g in
            SyncSavingsGoalRow(id: g.id, user_id: uid, name: g.name, goal_description: g.goalDescription,
                               target_amount: g.targetAmount, current_amount: g.currentAmount,
                               starting_balance_currency_code: g.startingBalanceCurrencyCode,
                               currency_code: g.currencyCode, target_date: g.targetDate, created_date: g.createdDate,
                               updated_at: g.updatedAt, icon_name: g.iconName, color_hex: g.colorHex,
                               is_completed: g.isCompleted, completed_date: g.completedDate,
                               auto_contribute_enabled: g.autoContributeEnabled,
                               auto_contribute_amount: g.autoContributeAmount,
                               auto_contribute_period_raw: g.autoContributePeriod?.rawValue,
                               priority: g.priority, linked_wallet_id: g.linkedWallet?.id, deleted_at: g.deletedAt)
        }
        let returned = try await upsertInChunks(rows, to: "savings_goals", client)
        finishPush(returned, pending: pending, snapshot: snapshot, uid: uid, context: context)
    }

    private func pushRecurringRules(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<RecurringRule>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let snapshot = updatedAtSnapshot(pending)
        let rows = pending.map { r in
            SyncRecurringRuleRow(id: r.id, user_id: uid, name: r.name, amount: r.amount,
                                 currency_code: r.currencyCode, type: r.type.rawValue, frequency: r.frequency.rawValue,
                                 interval: r.interval,
                                 start_date: r.startDate, next_due_date: r.nextDueDate, end_date: r.endDate,
                                 is_active: r.isActive, reminders_enabled: r.remindersEnabled,
                                 wallet_id: r.wallet?.id, category_id: r.category?.id,
                                 updated_at: r.updatedAt, deleted_at: r.deletedAt)
        }
        let returned = try await upsertInChunks(rows, to: "recurring_rules", client)
        finishPush(returned, pending: pending, snapshot: snapshot, uid: uid, context: context)
    }

    private func pushEventMembers(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<EventMember>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let snapshot = updatedAtSnapshot(pending)
        var rows: [SyncEventMemberRow] = []
        rows.reserveCapacity(pending.count)
        for m in pending {
            var avatarPath: String?
            if let data = m.avatarData {
                avatarPath = imagePath(uid, "event_members", m.id)
                let hash = Self.sha256(data)
                if m.avatarUploadedHash != hash {
                    try await uploadImage(data, to: avatarPath!, client)
                    m.avatarUploadedHash = hash
                }
            } else {
                m.avatarUploadedHash = nil
            }
            rows.append(SyncEventMemberRow(id: m.id, user_id: uid, event_id: m.event?.id, name: m.name,
                                           avatar_path: avatarPath, avatar_icon: m.avatarIcon,
                                           color_hex: m.colorHex, is_archived: m.isArchived,
                                           is_local_user: m.isLocalUser, is_budget_pool: m.isBudgetPool,
                                           sort_order: m.sortOrder, created_at: m.createdAt,
                                           updated_at: m.updatedAt, deleted_at: m.deletedAt))
        }
        let returned = try await upsertInChunks(rows, to: "event_members", client)
        finishPush(returned, pending: pending, snapshot: snapshot, uid: uid, context: context)
    }

    private func pushEventLedgerTransactions(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<EventLedgerTransaction>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let snapshot = updatedAtSnapshot(pending)
        let rows = pending.map { t in
            SyncEventLedgerTransactionRow(id: t.id, user_id: uid, event_id: t.event?.id, kind: t.kind.rawValue,
                                          title: t.title, amount_minor: t.amountMinor, paid_source: t.paidSource.rawValue,
                                          paid_by_member_id: t.paidByMemberId, split_type: t.splitType.rawValue,
                                          date: t.date, note: t.note, category_id: t.categoryId,
                                          category_name: t.categoryName, category_icon: t.categoryIcon,
                                          category_color_hex: t.categoryColorHex, is_split_all: t.isSplitAll,
                                          is_deleted: t.isDeleted, created_at: t.createdAt, updated_at: t.updatedAt,
                                          deleted_at: t.deletedAt)
        }
        let returned = try await upsertInChunks(rows, to: "event_ledger_transactions", client)
        finishPush(returned, pending: pending, snapshot: snapshot, uid: uid, context: context)
    }

    private func pushEventLedgerParticipants(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<EventLedgerParticipant>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let snapshot = updatedAtSnapshot(pending)
        let rows = pending.map { p in
            SyncEventLedgerParticipantRow(id: p.id, user_id: uid, transaction_id: p.transaction?.id,
                                          member_id: p.memberId, event_member_id: p.member?.id,
                                          order_index: p.orderIndex, updated_at: p.updatedAt, deleted_at: p.deletedAt)
        }
        let returned = try await upsertInChunks(rows, to: "event_ledger_participants", client)
        finishPush(returned, pending: pending, snapshot: snapshot, uid: uid, context: context)
    }

    private func pushEventSettlementSnapshots(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<EventSettlementSnapshot>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let snapshot = updatedAtSnapshot(pending)
        let rows = pending.map { s in
            SyncEventSettlementSnapshotRow(id: s.id, user_id: uid, event_id: s.event?.id,
                                           ledger_revision: s.ledgerRevision, created_at: s.createdAt,
                                           updated_at: s.updatedAt, deleted_at: s.deletedAt)
        }
        let returned = try await upsertInChunks(rows, to: "event_settlement_snapshots", client)
        finishPush(returned, pending: pending, snapshot: snapshot, uid: uid, context: context)
    }

    private func pushEventSettlementTransfers(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<EventSettlementTransfer>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let snapshot = updatedAtSnapshot(pending)
        let rows = pending.map { t in
            SyncEventSettlementTransferRow(id: t.id, user_id: uid, snapshot_id: t.snapshot?.id,
                                           from_member_id: t.fromMemberId, to_member_id: t.toMemberId,
                                           amount_minor: t.amountMinor, sequence: t.sequence,
                                           updated_at: t.updatedAt, deleted_at: t.deletedAt)
        }
        let returned = try await upsertInChunks(rows, to: "event_settlement_transfers", client)
        finishPush(returned, pending: pending, snapshot: snapshot, uid: uid, context: context)
    }

    private func pushEventWalletExportRecords(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<EventWalletExportRecord>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let snapshot = updatedAtSnapshot(pending)
        let rows = pending.map { r in
            SyncEventWalletExportRecordRow(id: r.id, user_id: uid, event_id: r.event?.id, snapshot_id: r.snapshot?.id,
                                           member_id: r.memberId, wallet_transaction_id: r.walletTransactionId,
                                           amount_minor: r.amountMinor, direction: r.direction.rawValue,
                                           export_type: r.exportType.rawValue, created_at: r.createdAt,
                                           updated_at: r.updatedAt, deleted_at: r.deletedAt)
        }
        let returned = try await upsertInChunks(rows, to: "event_wallet_export_records", client)
        finishPush(returned, pending: pending, snapshot: snapshot, uid: uid, context: context)
    }

    private func pushBudgets(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let pending = try context.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.needsSync }))
        guard !pending.isEmpty else { return }
        let snapshot = updatedAtSnapshot(pending)
        let rows = pending.map { b in
            SyncBudgetRow(id: b.id, user_id: uid, name: b.name, amount_limit: b.amountLimit,
                          currency_code: b.currencyCode, period_type_raw: b.periodType.rawValue,
                          start_date: b.startDate, created_at: b.createdAt, updated_at: b.updatedAt,
                          custom_end_date: b.customEndDate, month: b.month, year: b.year,
                          is_recurring: b.isRecurring, rollover_excess: b.rolloverExcess,
                          rollover_amount: b.rolloverAmount,
                          amount_type_data: b.amountType.encode().flatMap { String(data: $0, encoding: .utf8) },
                          alert_at_50: b.alertAt50, alert_at_80: b.alertAt80, alert_at_100: b.alertAt100,
                          alert_on_projected_overspend: b.alertOnProjectedOverspend,
                          last_alert_triggered_date: b.lastAlertTriggeredDate,
                          last_alert_threshold: b.lastAlertThreshold,
                          budget_category_type_raw: b.budgetCategoryType?.rawValue,
                          category_id: b.category?.id, target_kind: b.targetKindRaw,
                          alert_mode: b.alertModeRaw, last_alert_period_key: b.lastAlertPeriodKey,
                          week_start_day: b.weekStartDay, deleted_at: b.deletedAt)
        }
        let returned = try await upsertInChunks(rows, to: "budgets", client)
        // Rebuild each budget's category join rows (delete then insert current set).
        for b in pending {
            try await client.from("budget_categories").delete().eq("budget_id", value: b.id.uuidString).execute()
            let joins = (b.categories ?? []).map {
                SyncBudgetCategoryRow(budget_id: b.id, category_id: $0.id, user_id: uid)
            }
            if !joins.isEmpty {
                try await client.from("budget_categories").insert(joins).execute()
            }
        }
        finishPush(returned, pending: pending, snapshot: snapshot, uid: uid, context: context)
    }

    private func pushTransactionLocations(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        // Locations have no back-reference, so gather them via their owning transactions.
        let txns = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.location != nil }))
        let pairs = txns.compactMap { t -> (Transaction, TransactionLocation)? in
            guard let loc = t.location, loc.needsSync else { return nil }
            return (t, loc)
        }
        guard !pairs.isEmpty else { return }
        let snapshot = updatedAtSnapshot(pairs.map { $0.1 })
        let rows = pairs.map { (t, loc) in
            SyncTransactionLocationRow(id: loc.id, user_id: uid, transaction_id: t.id,
                                       display_name: loc.displayName, full_address: loc.fullAddress,
                                       short_address: loc.shortAddress, latitude: loc.latitude,
                                       longitude: loc.longitude,
                                       horizontal_accuracy_meters: loc.horizontalAccuracyMeters,
                                       captured_at: loc.capturedAt, source_raw: loc.sourceRaw,
                                       apple_place_id: loc.applePlaceID,
                                       alternate_apple_place_ids: loc.alternateApplePlaceIDs,
                                       point_of_interest_category_raw: loc.pointOfInterestCategoryRaw,
                                       locality: loc.locality, administrative_area: loc.administrativeArea,
                                       country_code: loc.countryCode,
                                       normalized_spatial_key: loc.normalizedSpatialKey,
                                       updated_at: loc.updatedAt, deleted_at: loc.deletedAt)
        }
        let returned = try await upsertInChunks(rows, to: "transaction_locations", client)
        finishPush(returned, pending: pairs.map { $0.1 }, snapshot: snapshot, uid: uid, context: context)
    }

    /// Sets `deleted_at` on the server for each locally-deleted row, then clears
    /// the entry. No-ops for rows that were never pushed (update affects 0 rows).
    private func pushDeletions(_ client: SupabaseClient) async throws {
        struct DeletionPatch: Encodable { let deleted_at: Date }
        let patch = DeletionPatch(deleted_at: Date())
        for entry in SyncDeletionQueue.all() {
            try await client.from(entry.table)
                .update(patch)
                .eq("id", value: entry.id.uuidString)
                .execute()
            SyncDeletionQueue.remove(entry)
        }
    }

    /// Clears every wallet's cached balance after a pull so soft-deleted /
    /// edited / reassigned transactions are reflected immediately.
    private func invalidateAllWalletBalanceCaches(_ context: ModelContext) {
        if let wallets = try? context.fetch(FetchDescriptor<Wallet>()) {
            wallets.forEach { $0.invalidateBalanceCache() }
        }
    }

    /// Runs a synchronous span of the engine's own writes under the mutation-
    /// tracker guard, so the save inside isn't re-flagged as a user edit. Must
    /// never wrap an `await`: while suspended, the guard would blind the tracker
    /// to genuine user saves happening on the main actor.
    func withSyncWriteGuard<T>(_ body: () throws -> T) rethrows -> T {
        let previous = SyncMutationTracker.isApplyingSyncChanges
        SyncMutationTracker.isApplyingSyncChanges = true
        defer { SyncMutationTracker.isApplyingSyncChanges = previous }
        return try body()
    }

    /// Captures each model's `updatedAt` before a push's network await, so
    /// `finishPush` can tell "unchanged since we serialized it" apart from
    /// "user edited it while the upsert was in flight".
    private func updatedAtSnapshot(_ models: [any SyncTrackable]) -> [UUID: Date] {
        Dictionary(models.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { first, _ in first })
    }

    /// Completes a push: writes the server-authoritative `updated_at` back and
    /// clears `needsSync` — but ONLY for models whose `updatedAt` still matches
    /// the pre-push snapshot. A model edited during the upsert await keeps its
    /// dirty flag (and its newer local timestamp) so the edit pushes next cycle
    /// instead of being silently marked synced with stale server state.
    private func finishPush<R: SyncServerRow>(
        _ returned: [R],
        pending: [any SyncTrackable],
        snapshot: [UUID: Date],
        uid: UUID,
        context: ModelContext
    ) {
        withSyncWriteGuard {
            let serverDates = Dictionary(returned.map { ($0.id, $0.updated_at) },
                                         uniquingKeysWith: { first, _ in first })
            for m in pending {
                guard snapshot[m.id] == m.updatedAt else { continue }  // edited mid-push — stays dirty
                if let d = serverDates[m.id] { m.updatedAt = d }
                m.needsSync = false
                (m as? any SyncOwned)?.assignOwner(uid)
            }
            try? context.save()
        }
    }

    /// Hex SHA-256 — identity for uploaded image bytes, so receipts/covers/
    /// avatars re-upload only when the pixels actually changed.
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Resolves a pulled row's foreign-key reference, preserving an existing link
    /// when the parent can't be found locally yet.
    ///
    /// The naive `row.fk_id.flatMap { fetchByID(...) }` returns nil in two very
    /// different cases: (a) the remote genuinely cleared the reference, and (b) the
    /// referenced parent simply isn't present locally yet — e.g. its own pull step
    /// failed transiently this cycle (steps are now isolated, so one table failing
    /// no longer stops the others). Case (b) would silently sever a still-valid
    /// relationship and mark the child synced, so it never self-heals.
    ///
    /// This distinguishes them: a nil id clears the link; a non-nil id that resolves
    /// updates it; a non-nil id that *doesn't* resolve keeps `current` (the prior
    /// link) so a transient miss can't orphan an already-linked row.
    func resolveRef<T: PersistentModel>(_ type: T.Type, id: UUID?, current: T?, in context: ModelContext) throws -> T? {
        guard let id else { return nil }                                  // remote cleared the reference
        if let found = try fetchByID(type, id: id, in: context) { return found }
        return current                                                    // parent missing → keep existing link
    }

    /// Last-write-wins guard for a pulled row. Returns `true` when the local row
    /// holds an un-pushed change *newer* than the incoming remote row, so the
    /// remote change must be skipped: for a normal row the local value is kept;
    /// for a remote tombstone the local edit wins over the delete. Pure and
    /// side-effect-free so it can be unit-tested in isolation; called from every
    /// pull site (both the delete branch and the normal-apply branch).
    static func localChangeWins(localNeedsSync: Bool, localUpdatedAt: Date, remoteUpdatedAt: Date) -> Bool {
        localNeedsSync && localUpdatedAt > remoteUpdatedAt
    }

    // MARK: - Pull

    private func pullWallets(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncWalletRow] = try await fetchChanged("wallets", client, uid)
        guard !rows.isEmpty else { return }
        try withSyncWriteGuard {
            try applyLocal(table: "wallets", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
                if row.deleted_at != nil {
                    if let existing = try fetchByID(Wallet.self, id: row.id, in: context) {
                        if Self.localChangeWins(localNeedsSync: existing.needsSync, localUpdatedAt: existing.updatedAt, remoteUpdatedAt: row.updated_at) { return }  // newer un-pushed local edit wins over a remote delete
                        existing.deletedAt = row.deleted_at; existing.updatedAt = row.updated_at; existing.needsSync = false
                    }
                    return
                }
                let w = try fetchByID(Wallet.self, id: row.id, in: context) ?? {
                    let new = Wallet(name: row.name, currencyCode: row.currency_code, icon: row.icon, colorHex: row.color_hex)
                    new.id = row.id
                    new.needsSync = false
                    context.insert(new)
                    return new
                }()
                // LWW: keep local if it has a newer un-pushed change.
                if Self.localChangeWins(localNeedsSync: w.needsSync, localUpdatedAt: w.updatedAt, remoteUpdatedAt: row.updated_at) { return }
                w.name = row.name; w.currencyCode = row.currency_code; w.icon = row.icon
                w.colorHex = row.color_hex; w.isArchived = row.is_archived
                w.createdAt = row.created_at; w.updatedAt = row.updated_at
                w.deletedAt = row.deleted_at; w.syncUserID = row.user_id; w.needsSync = false
            }
            try context.save()
        }
    }

    private func pullCategories(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncCategoryRow] = try await fetchChanged("categories", client, uid)
        guard !rows.isEmpty else { return }
        try withSyncWriteGuard {
            try applyLocal(table: "categories", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
                if row.deleted_at != nil {
                    if let existing = try fetchByID(Category.self, id: row.id, in: context) {
                        if Self.localChangeWins(localNeedsSync: existing.needsSync, localUpdatedAt: existing.updatedAt, remoteUpdatedAt: row.updated_at) { return }  // newer un-pushed local edit wins over a remote delete
                        existing.deletedAt = row.deleted_at; existing.updatedAt = row.updated_at; existing.needsSync = false
                    }
                    return
                }
                let c = try fetchByID(Category.self, id: row.id, in: context) ?? {
                    let new = Category(name: row.name, icon: row.icon ?? "", colorHex: row.color_hex ?? "",
                                       type: TransactionType(rawValue: row.type) ?? .expense, isSystem: row.is_system,
                                       canonicalKey: row.canonical_key)
                    new.id = row.id
                    new.needsSync = false
                    context.insert(new)
                    return new
                }()
                if Self.localChangeWins(localNeedsSync: c.needsSync, localUpdatedAt: c.updatedAt, remoteUpdatedAt: row.updated_at) { return }
                c.name = row.name; c.icon = row.icon ?? ""; c.colorHex = row.color_hex ?? ""
                c.type = TransactionType(rawValue: row.type) ?? c.type; c.isSystem = row.is_system
                // Never let a pre-key cloud row (canonical_key null) erase a locally
                // stamped key — the stamp is what makes dedupe converge.
                if let key = row.canonical_key { c.canonicalKey = key }
                c.createdAt = row.created_at; c.updatedAt = row.updated_at
                c.deletedAt = row.deleted_at; c.syncUserID = row.user_id; c.needsSync = false
            }
            try context.save()
        }
    }

    private func pullTransactions(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncTransactionRow] = try await fetchChanged("transactions", client, uid)
        guard !rows.isEmpty else { return }
        var pendingPhotoDownloads: [(UUID, String)] = []
        try withSyncWriteGuard {
            try applyLocal(table: "transactions", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
                if row.deleted_at != nil {
                    if let existing = try fetchByID(Transaction.self, id: row.id, in: context) {
                        if Self.localChangeWins(localNeedsSync: existing.needsSync, localUpdatedAt: existing.updatedAt, remoteUpdatedAt: row.updated_at) { return }  // newer un-pushed local edit wins over a remote delete
                        existing.deletedAt = row.deleted_at; existing.updatedAt = row.updated_at; existing.needsSync = false
                    }
                    return
                }
                if let path = row.photo_path { pendingPhotoDownloads.append((row.id, path)) }
                let t = try fetchByID(Transaction.self, id: row.id, in: context) ?? {
                    let new = Transaction(amount: row.amount, currencyCode: row.currency_code,
                                          date: row.date, type: TransactionType(rawValue: row.type) ?? .expense,
                                          exchangeRate: row.exchange_rate)
                    new.id = row.id
                    new.needsSync = false
                    context.insert(new)
                    return new
                }()
                if Self.localChangeWins(localNeedsSync: t.needsSync, localUpdatedAt: t.updatedAt, remoteUpdatedAt: row.updated_at) { return }
                t.type = TransactionType(rawValue: row.type) ?? t.type
                t.date = row.date; t.note = row.note; t.tags = row.tags
                t.excludeFromReports = row.exclude_from_reports
                t.amount = row.amount; t.currencyCode = row.currency_code
                t.exchangeRate = row.exchange_rate; t.storedRate = row.stored_rate
                t.category = try resolveRef(Category.self, id: row.category_id, current: t.category, in: context)
                t.sourceWallet = try resolveRef(Wallet.self, id: row.source_wallet_id, current: t.sourceWallet, in: context)
                t.destinationWallet = try resolveRef(Wallet.self, id: row.destination_wallet_id, current: t.destinationWallet, in: context)
                t.event = try resolveRef(Event.self, id: row.event_id, current: t.event, in: context)
                t.recurringRule = try resolveRef(RecurringRule.self, id: row.recurring_rule_id, current: t.recurringRule, in: context)
                t.debt = try resolveRef(Debt.self, id: row.debt_id, current: t.debt, in: context)
                t.savingsGoal = try resolveRef(SavingsGoal.self, id: row.savings_goal_id, current: t.savingsGoal, in: context)
                t.savingsIsWithdrawal = row.savings_is_withdrawal
                t.createdAt = row.created_at; t.updatedAt = row.updated_at
                t.deletedAt = row.deleted_at; t.syncUserID = row.user_id; t.needsSync = false
            }
            try context.save()
        }
        // Download receipt images for rows that have a path but no local data.
        for (id, path) in pendingPhotoDownloads {
            guard let t = try fetchByID(Transaction.self, id: id, in: context), t.photoData == nil else { continue }
            await downloadAndStoreImage(path, kind: .transactionPhoto, id: id, client, context)
        }
        if !pendingPhotoDownloads.isEmpty { try withSyncWriteGuard { try context.save() } }
    }

    private func pullEvents(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncEventRow] = try await fetchChanged("events", client, uid)
        guard !rows.isEmpty else { return }
        var pendingCoverDownloads: [(UUID, String)] = []
        try withSyncWriteGuard {
            try applyLocal(table: "events", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
                if row.deleted_at != nil {
                    if let existing = try fetchByID(Event.self, id: row.id, in: context) {
                        if Self.localChangeWins(localNeedsSync: existing.needsSync, localUpdatedAt: existing.updatedAt, remoteUpdatedAt: row.updated_at) { return }  // newer un-pushed local edit wins over a remote delete
                        existing.deletedAt = row.deleted_at; existing.updatedAt = row.updated_at; existing.needsSync = false
                    }
                    return
                }
                if let path = row.cover_image_path { pendingCoverDownloads.append((row.id, path)) }
                let e = try fetchByID(Event.self, id: row.id, in: context) ?? {
                    let new = Event(title: row.title, startDate: row.start_date)
                    new.id = row.id
                    new.needsSync = false
                    context.insert(new)
                    return new
                }()
                if Self.localChangeWins(localNeedsSync: e.needsSync, localUpdatedAt: e.updatedAt, remoteUpdatedAt: row.updated_at) { return }
                e.title = row.title; e.startDate = row.start_date; e.endDate = row.end_date
                e.totalBudget = row.total_budget; e.notes = row.notes; e.icon = row.icon
                e.colorHex = row.color_hex; e.location = row.location; e.status = row.status
                e.currencyCode = row.currency_code; e.ledgerRevision = row.ledger_revision
                e.confirmedSettlementRevision = row.confirmed_settlement_revision
                e.ledgerMode = EventLedgerMode(rawValue: row.ledger_mode) ?? .isolatedV1
                e.latitude = row.latitude; e.longitude = row.longitude
                e.updatedAt = row.updated_at; e.deletedAt = row.deleted_at
                e.syncUserID = row.user_id; e.needsSync = false
            }
            try context.save()
        }
        for (id, path) in pendingCoverDownloads {
            guard let e = try fetchByID(Event.self, id: id, in: context), e.coverImageData == nil else { continue }
            await downloadAndStoreImage(path, kind: .eventCover, id: id, client, context)
        }
        if !pendingCoverDownloads.isEmpty { try withSyncWriteGuard { try context.save() } }
    }

    private func pullDebts(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncDebtRow] = try await fetchChanged("debts", client, uid)
        guard !rows.isEmpty else { return }
        try withSyncWriteGuard {
            try applyLocal(table: "debts", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
                if row.deleted_at != nil {
                    if let existing = try fetchByID(Debt.self, id: row.id, in: context) {
                        if Self.localChangeWins(localNeedsSync: existing.needsSync, localUpdatedAt: existing.updatedAt, remoteUpdatedAt: row.updated_at) { return }  // newer un-pushed local edit wins over a remote delete
                        existing.deletedAt = row.deleted_at; existing.updatedAt = row.updated_at; existing.needsSync = false
                    }
                    return
                }
                let d = try fetchByID(Debt.self, id: row.id, in: context) ?? {
                    let new = Debt(personName: row.person_name, totalAmount: row.total_amount,
                                   currencyCode: row.currency_code, type: DebtType(rawValue: row.type) ?? .iOwe,
                                   dueDate: row.due_date, note: row.note)
                    new.id = row.id
                    new.needsSync = false
                    context.insert(new)
                    return new
                }()
                if Self.localChangeWins(localNeedsSync: d.needsSync, localUpdatedAt: d.updatedAt, remoteUpdatedAt: row.updated_at) { return }
                d.personName = row.person_name; d.totalAmount = row.total_amount; d.currencyCode = row.currency_code
                d.dueDate = row.due_date; d.type = DebtType(rawValue: row.type) ?? d.type; d.note = row.note
                d.dateCreated = row.date_created; d.isCompleted = row.is_completed
                d.createdAt = row.created_at; d.updatedAt = row.updated_at; d.deletedAt = row.deleted_at
                d.syncUserID = row.user_id; d.needsSync = false
            }
            try context.save()
        }
    }

    private func pullSavingsGoals(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncSavingsGoalRow] = try await fetchChanged("savings_goals", client, uid)
        guard !rows.isEmpty else { return }
        try withSyncWriteGuard {
            try applyLocal(table: "savings_goals", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
                if row.deleted_at != nil {
                    if let existing = try fetchByID(SavingsGoal.self, id: row.id, in: context) {
                        if Self.localChangeWins(localNeedsSync: existing.needsSync, localUpdatedAt: existing.updatedAt, remoteUpdatedAt: row.updated_at) { return }  // newer un-pushed local edit wins over a remote delete
                        existing.deletedAt = row.deleted_at; existing.updatedAt = row.updated_at; existing.needsSync = false
                    }
                    return
                }
                let g = try fetchByID(SavingsGoal.self, id: row.id, in: context) ?? {
                    let new = SavingsGoal(name: row.name, targetAmount: row.target_amount,
                                          currencyCode: row.currency_code, targetDate: row.target_date,
                                          iconName: row.icon_name, colorHex: row.color_hex)
                    new.id = row.id
                    new.needsSync = false
                    context.insert(new)
                    return new
                }()
                if Self.localChangeWins(localNeedsSync: g.needsSync, localUpdatedAt: g.updatedAt, remoteUpdatedAt: row.updated_at) { return }
                g.name = row.name; g.goalDescription = row.goal_description; g.targetAmount = row.target_amount
                g.currentAmount = row.current_amount; g.currencyCode = row.currency_code; g.targetDate = row.target_date
                g.startingBalanceCurrencyCode = row.starting_balance_currency_code
                g.createdDate = row.created_date; g.updatedAt = row.updated_at; g.iconName = row.icon_name
                g.colorHex = row.color_hex; g.isCompleted = row.is_completed; g.completedDate = row.completed_date
                g.autoContributeEnabled = row.auto_contribute_enabled
                g.autoContributeAmount = row.auto_contribute_amount
                g.autoContributePeriod = row.auto_contribute_period_raw.flatMap { BudgetPeriodType(rawValue: $0) }
                g.priority = row.priority
                g.linkedWallet = try resolveRef(Wallet.self, id: row.linked_wallet_id, current: g.linkedWallet, in: context)
                g.deletedAt = row.deleted_at; g.syncUserID = row.user_id; g.needsSync = false
            }
            try context.save()
        }
    }

    private func pullRecurringRules(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncRecurringRuleRow] = try await fetchChanged("recurring_rules", client, uid)
        guard !rows.isEmpty else { return }
        try withSyncWriteGuard {
            try applyLocal(table: "recurring_rules", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
                if row.deleted_at != nil {
                    if let existing = try fetchByID(RecurringRule.self, id: row.id, in: context) {
                        if Self.localChangeWins(localNeedsSync: existing.needsSync, localUpdatedAt: existing.updatedAt, remoteUpdatedAt: row.updated_at) { return }  // newer un-pushed local edit wins over a remote delete
                        existing.deletedAt = row.deleted_at; existing.updatedAt = row.updated_at; existing.needsSync = false
                    }
                    return
                }
                let r = try fetchByID(RecurringRule.self, id: row.id, in: context) ?? {
                    let new = RecurringRule(name: row.name, amount: row.amount, currencyCode: row.currency_code,
                                            frequency: Frequency(rawValue: row.frequency) ?? .monthly,
                                            startDate: row.start_date,
                                            type: TransactionType(rawValue: row.type) ?? .expense)
                    new.id = row.id
                    new.interval = row.interval
                    new.needsSync = false
                    context.insert(new)
                    return new
                }()
                if Self.localChangeWins(localNeedsSync: r.needsSync, localUpdatedAt: r.updatedAt, remoteUpdatedAt: row.updated_at) { return }
                r.name = row.name; r.amount = row.amount; r.currencyCode = row.currency_code
                r.type = TransactionType(rawValue: row.type) ?? r.type
                r.frequency = Frequency(rawValue: row.frequency) ?? r.frequency
                r.interval = row.interval
                r.startDate = row.start_date; r.nextDueDate = row.next_due_date; r.endDate = row.end_date
                r.isActive = row.is_active; r.remindersEnabled = row.reminders_enabled
                r.wallet = try resolveRef(Wallet.self, id: row.wallet_id, current: r.wallet, in: context)
                r.category = try resolveRef(Category.self, id: row.category_id, current: r.category, in: context)
                r.updatedAt = row.updated_at; r.deletedAt = row.deleted_at
                r.syncUserID = row.user_id; r.needsSync = false
            }
            try context.save()
        }
    }

    private func pullEventMembers(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncEventMemberRow] = try await fetchChanged("event_members", client, uid)
        guard !rows.isEmpty else { return }
        var pendingAvatarDownloads: [(UUID, String)] = []
        try withSyncWriteGuard {
            try applyLocal(table: "event_members", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
                if row.deleted_at != nil {
                    if let dead = try fetchByID(EventMember.self, id: row.id, in: context) {
                        if Self.localChangeWins(localNeedsSync: dead.needsSync, localUpdatedAt: dead.updatedAt, remoteUpdatedAt: row.updated_at) { return }  // newer un-pushed local edit wins over a remote delete
                        dead.deletedAt = row.deleted_at; dead.updatedAt = row.updated_at; dead.needsSync = false
                    }
                    return
                }
                if let path = row.avatar_path { pendingAvatarDownloads.append((row.id, path)) }
                let existing = try fetchByID(EventMember.self, id: row.id, in: context)
                let m: EventMember
                if let existing { m = existing } else {
                    let ev = try row.event_id.flatMap { try fetchByID(Event.self, id: $0, in: context) }
                    m = EventMember(name: row.name, event: ev)
                    m.id = row.id
                    m.needsSync = false
                    context.insert(m)
                }
                if Self.localChangeWins(localNeedsSync: m.needsSync, localUpdatedAt: m.updatedAt, remoteUpdatedAt: row.updated_at) { return }
                m.name = row.name; m.avatarIcon = row.avatar_icon; m.colorHex = row.color_hex
                m.isArchived = row.is_archived; m.isLocalUser = row.is_local_user; m.isBudgetPool = row.is_budget_pool
                m.sortOrder = row.sort_order; m.createdAt = row.created_at; m.updatedAt = row.updated_at
                m.event = try resolveRef(Event.self, id: row.event_id, current: m.event, in: context)
                m.deletedAt = row.deleted_at; m.syncUserID = row.user_id; m.needsSync = false
            }
            try context.save()
        }
        for (id, path) in pendingAvatarDownloads {
            guard let m = try fetchByID(EventMember.self, id: id, in: context), m.avatarData == nil else { continue }
            await downloadAndStoreImage(path, kind: .memberAvatar, id: id, client, context)
        }
        if !pendingAvatarDownloads.isEmpty { try withSyncWriteGuard { try context.save() } }
    }

    private func pullEventLedgerTransactions(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncEventLedgerTransactionRow] = try await fetchChanged("event_ledger_transactions", client, uid)
        guard !rows.isEmpty else { return }
        try withSyncWriteGuard {
            try applyLocal(table: "event_ledger_transactions", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
                if row.deleted_at != nil {
                    if let dead = try fetchByID(EventLedgerTransaction.self, id: row.id, in: context) {
                        if Self.localChangeWins(localNeedsSync: dead.needsSync, localUpdatedAt: dead.updatedAt, remoteUpdatedAt: row.updated_at) { return }  // newer un-pushed local edit wins over a remote delete
                        dead.deletedAt = row.deleted_at; dead.updatedAt = row.updated_at; dead.needsSync = false
                    }
                    return
                }
                let existing = try fetchByID(EventLedgerTransaction.self, id: row.id, in: context)
                let t: EventLedgerTransaction
                if let existing { t = existing } else {
                    let ev = try row.event_id.flatMap { try fetchByID(Event.self, id: $0, in: context) }
                    t = EventLedgerTransaction(
                        kind: EventLedgerTransactionKind(rawValue: row.kind) ?? .expense, title: row.title,
                        amountMinor: row.amount_minor, paidSource: EventExpensePaidSource(rawValue: row.paid_source) ?? .member,
                        paidByMemberId: row.paid_by_member_id, splitType: EventSplitType(rawValue: row.split_type) ?? .equal,
                        date: row.date, note: row.note, categoryId: row.category_id, categoryName: row.category_name,
                        categoryIcon: row.category_icon, categoryColorHex: row.category_color_hex, event: ev)
                    t.id = row.id
                    t.needsSync = false
                    context.insert(t)
                }
                if Self.localChangeWins(localNeedsSync: t.needsSync, localUpdatedAt: t.updatedAt, remoteUpdatedAt: row.updated_at) { return }
                t.kind = EventLedgerTransactionKind(rawValue: row.kind) ?? t.kind
                t.title = row.title; t.amountMinor = row.amount_minor
                t.paidSource = EventExpensePaidSource(rawValue: row.paid_source) ?? t.paidSource
                t.paidByMemberId = row.paid_by_member_id
                t.splitType = EventSplitType(rawValue: row.split_type) ?? t.splitType
                t.date = row.date; t.note = row.note; t.categoryId = row.category_id
                t.categoryName = row.category_name; t.categoryIcon = row.category_icon
                t.categoryColorHex = row.category_color_hex; t.isSplitAll = row.is_split_all; t.isDeleted = row.is_deleted
                t.event = try resolveRef(Event.self, id: row.event_id, current: t.event, in: context)
                t.createdAt = row.created_at; t.updatedAt = row.updated_at; t.deletedAt = row.deleted_at
                t.syncUserID = row.user_id; t.needsSync = false
            }
            try context.save()
        }
    }

    private func pullEventLedgerParticipants(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncEventLedgerParticipantRow] = try await fetchChanged("event_ledger_participants", client, uid)
        guard !rows.isEmpty else { return }
        try withSyncWriteGuard {
            try applyLocal(table: "event_ledger_participants", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
                if row.deleted_at != nil {
                    if let dead = try fetchByID(EventLedgerParticipant.self, id: row.id, in: context) {
                        if Self.localChangeWins(localNeedsSync: dead.needsSync, localUpdatedAt: dead.updatedAt, remoteUpdatedAt: row.updated_at) { return }  // newer un-pushed local edit wins over a remote delete
                        dead.deletedAt = row.deleted_at; dead.updatedAt = row.updated_at; dead.needsSync = false
                    }
                    return
                }
                let existing = try fetchByID(EventLedgerParticipant.self, id: row.id, in: context)
                let p: EventLedgerParticipant
                if let existing { p = existing } else {
                    let txn = try row.transaction_id.flatMap { try fetchByID(EventLedgerTransaction.self, id: $0, in: context) }
                    let mem = try row.event_member_id.flatMap { try fetchByID(EventMember.self, id: $0, in: context) }
                    p = EventLedgerParticipant(memberId: row.member_id, orderIndex: row.order_index, transaction: txn, member: mem)
                    p.id = row.id
                    p.needsSync = false
                    context.insert(p)
                }
                if Self.localChangeWins(localNeedsSync: p.needsSync, localUpdatedAt: p.updatedAt, remoteUpdatedAt: row.updated_at) { return }
                p.memberId = row.member_id; p.orderIndex = row.order_index
                p.transaction = try resolveRef(EventLedgerTransaction.self, id: row.transaction_id, current: p.transaction, in: context)
                p.member = try resolveRef(EventMember.self, id: row.event_member_id, current: p.member, in: context)
                p.updatedAt = row.updated_at; p.deletedAt = row.deleted_at
                p.syncUserID = row.user_id; p.needsSync = false
            }
            try context.save()
        }
    }

    private func pullEventSettlementSnapshots(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncEventSettlementSnapshotRow] = try await fetchChanged("event_settlement_snapshots", client, uid)
        guard !rows.isEmpty else { return }
        try withSyncWriteGuard {
            try applyLocal(table: "event_settlement_snapshots", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
                if row.deleted_at != nil {
                    if let dead = try fetchByID(EventSettlementSnapshot.self, id: row.id, in: context) {
                        if Self.localChangeWins(localNeedsSync: dead.needsSync, localUpdatedAt: dead.updatedAt, remoteUpdatedAt: row.updated_at) { return }  // newer un-pushed local edit wins over a remote delete
                        dead.deletedAt = row.deleted_at; dead.updatedAt = row.updated_at; dead.needsSync = false
                    }
                    return
                }
                let existing = try fetchByID(EventSettlementSnapshot.self, id: row.id, in: context)
                let s: EventSettlementSnapshot
                if let existing { s = existing } else {
                    let ev = try row.event_id.flatMap { try fetchByID(Event.self, id: $0, in: context) }
                    s = EventSettlementSnapshot(ledgerRevision: row.ledger_revision, event: ev)
                    s.id = row.id
                    s.needsSync = false
                    context.insert(s)
                }
                if Self.localChangeWins(localNeedsSync: s.needsSync, localUpdatedAt: s.updatedAt, remoteUpdatedAt: row.updated_at) { return }
                s.ledgerRevision = row.ledger_revision
                s.event = try resolveRef(Event.self, id: row.event_id, current: s.event, in: context)
                s.createdAt = row.created_at; s.updatedAt = row.updated_at; s.deletedAt = row.deleted_at
                s.syncUserID = row.user_id; s.needsSync = false
            }
            try context.save()
        }
    }

    private func pullEventSettlementTransfers(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncEventSettlementTransferRow] = try await fetchChanged("event_settlement_transfers", client, uid)
        guard !rows.isEmpty else { return }
        try withSyncWriteGuard {
            try applyLocal(table: "event_settlement_transfers", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
                if row.deleted_at != nil {
                    if let dead = try fetchByID(EventSettlementTransfer.self, id: row.id, in: context) {
                        if Self.localChangeWins(localNeedsSync: dead.needsSync, localUpdatedAt: dead.updatedAt, remoteUpdatedAt: row.updated_at) { return }  // newer un-pushed local edit wins over a remote delete
                        dead.deletedAt = row.deleted_at; dead.updatedAt = row.updated_at; dead.needsSync = false
                    }
                    return
                }
                let existing = try fetchByID(EventSettlementTransfer.self, id: row.id, in: context)
                let t: EventSettlementTransfer
                if let existing { t = existing } else {
                    let snap = try row.snapshot_id.flatMap { try fetchByID(EventSettlementSnapshot.self, id: $0, in: context) }
                    t = EventSettlementTransfer(fromMemberId: row.from_member_id, toMemberId: row.to_member_id,
                                                amountMinor: row.amount_minor, sequence: row.sequence, snapshot: snap)
                    t.id = row.id
                    t.needsSync = false
                    context.insert(t)
                }
                if Self.localChangeWins(localNeedsSync: t.needsSync, localUpdatedAt: t.updatedAt, remoteUpdatedAt: row.updated_at) { return }
                t.fromMemberId = row.from_member_id; t.toMemberId = row.to_member_id
                t.amountMinor = row.amount_minor; t.sequence = row.sequence
                t.snapshot = try resolveRef(EventSettlementSnapshot.self, id: row.snapshot_id, current: t.snapshot, in: context)
                t.updatedAt = row.updated_at; t.deletedAt = row.deleted_at
                t.syncUserID = row.user_id; t.needsSync = false
            }
            try context.save()
        }
    }

    private func pullEventWalletExportRecords(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncEventWalletExportRecordRow] = try await fetchChanged("event_wallet_export_records", client, uid)
        guard !rows.isEmpty else { return }
        try withSyncWriteGuard {
            try applyLocal(table: "event_wallet_export_records", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
                if row.deleted_at != nil {
                    if let dead = try fetchByID(EventWalletExportRecord.self, id: row.id, in: context) {
                        if Self.localChangeWins(localNeedsSync: dead.needsSync, localUpdatedAt: dead.updatedAt, remoteUpdatedAt: row.updated_at) { return }  // newer un-pushed local edit wins over a remote delete
                        dead.deletedAt = row.deleted_at; dead.updatedAt = row.updated_at; dead.needsSync = false
                    }
                    return
                }
                let existing = try fetchByID(EventWalletExportRecord.self, id: row.id, in: context)
                let r: EventWalletExportRecord
                if let existing { r = existing } else {
                    let ev = try row.event_id.flatMap { try fetchByID(Event.self, id: $0, in: context) }
                    let snap = try row.snapshot_id.flatMap { try fetchByID(EventSettlementSnapshot.self, id: $0, in: context) }
                    r = EventWalletExportRecord(memberId: row.member_id, walletTransactionId: row.wallet_transaction_id,
                                                amountMinor: row.amount_minor,
                                                direction: EventWalletExportDirection(rawValue: row.direction) ?? .expense,
                                                exportType: EventWalletExportType(rawValue: row.export_type) ?? .settlement,
                                                event: ev, snapshot: snap)
                    r.id = row.id
                    r.needsSync = false
                    context.insert(r)
                }
                if Self.localChangeWins(localNeedsSync: r.needsSync, localUpdatedAt: r.updatedAt, remoteUpdatedAt: row.updated_at) { return }
                r.memberId = row.member_id; r.walletTransactionId = row.wallet_transaction_id
                r.amountMinor = row.amount_minor
                r.direction = EventWalletExportDirection(rawValue: row.direction) ?? r.direction
                r.exportType = EventWalletExportType(rawValue: row.export_type) ?? r.exportType
                r.event = try resolveRef(Event.self, id: row.event_id, current: r.event, in: context)
                r.snapshot = try resolveRef(EventSettlementSnapshot.self, id: row.snapshot_id, current: r.snapshot, in: context)
                r.createdAt = row.created_at; r.updatedAt = row.updated_at; r.deletedAt = row.deleted_at
                r.syncUserID = row.user_id; r.needsSync = false
            }
            try context.save()
        }
    }

    private func pullBudgets(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncBudgetRow] = try await fetchChanged("budgets", client, uid)
        guard !rows.isEmpty else { return }
        // Category join rows (no cursor; small set). Map budget → category ids.
        let joinRows: [SyncBudgetCategoryRow] = try await client.from("budget_categories")
            .select().eq("user_id", value: uid.uuidString).execute().value
        let joinMap = Dictionary(grouping: joinRows, by: { $0.budget_id }).mapValues { $0.map(\.category_id) }
        try withSyncWriteGuard {
            try applyLocal(table: "budgets", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
                if row.deleted_at != nil {
                    if let dead = try fetchByID(Budget.self, id: row.id, in: context) {
                        if Self.localChangeWins(localNeedsSync: dead.needsSync, localUpdatedAt: dead.updatedAt, remoteUpdatedAt: row.updated_at) { return }  // newer un-pushed local edit wins over a remote delete
                        dead.deletedAt = row.deleted_at; dead.updatedAt = row.updated_at; dead.needsSync = false
                    }
                    return
                }
                let existing = try fetchByID(Budget.self, id: row.id, in: context)
                let b: Budget
                if let existing { b = existing } else {
                    b = Budget(amountLimit: row.amount_limit)
                    b.id = row.id
                    b.needsSync = false
                    context.insert(b)
                }
                if Self.localChangeWins(localNeedsSync: b.needsSync, localUpdatedAt: b.updatedAt, remoteUpdatedAt: row.updated_at) { return }
                b.name = row.name; b.amountLimit = row.amount_limit; b.currencyCode = row.currency_code
                b.periodType = BudgetPeriodType(rawValue: row.period_type_raw) ?? .monthly
                b.startDate = row.start_date; b.createdAt = row.created_at; b.updatedAt = row.updated_at
                b.customEndDate = row.custom_end_date; b.month = row.month; b.year = row.year
                b.isRecurring = row.is_recurring; b.rolloverExcess = row.rollover_excess
                b.rolloverAmount = row.rollover_amount
                b.alertAt50 = row.alert_at_50; b.alertAt80 = row.alert_at_80; b.alertAt100 = row.alert_at_100
                b.alertOnProjectedOverspend = row.alert_on_projected_overspend
                b.lastAlertTriggeredDate = row.last_alert_triggered_date
                b.lastAlertThreshold = row.last_alert_threshold
                b.targetKindRaw = row.target_kind
                b.alertModeRaw = row.alert_mode
                b.lastAlertPeriodKey = row.last_alert_period_key
                b.weekStartDay = row.week_start_day
                b.budgetCategoryType = row.budget_category_type_raw.flatMap { BudgetCategoryType(rawValue: $0) }
                b.category = try resolveRef(Category.self, id: row.category_id, current: b.category, in: context)
                b.categories = try (joinMap[row.id] ?? []).compactMap { try fetchByID(Category.self, id: $0, in: context) }
                if let raw = row.amount_type_data, let data = raw.data(using: .utf8),
                   let amountType = BudgetAmountType.decode(from: data) {
                    b.amountType = amountType
                }
                b.deletedAt = row.deleted_at; b.syncUserID = row.user_id; b.needsSync = false
            }
            try context.save()
        }
    }

    private func pullTransactionLocations(_ context: ModelContext, _ client: SupabaseClient, _ uid: UUID) async throws {
        let rows: [SyncTransactionLocationRow] = try await fetchChanged("transaction_locations", client, uid)
        guard !rows.isEmpty else { return }
        try withSyncWriteGuard {
            try applyLocal(table: "transaction_locations", rows: rows, context: context, rowDate: \.updated_at, rowID: \.id) { row in
                if row.deleted_at != nil {
                    if let dead = try fetchByID(TransactionLocation.self, id: row.id, in: context) {
                        if Self.localChangeWins(localNeedsSync: dead.needsSync, localUpdatedAt: dead.updatedAt, remoteUpdatedAt: row.updated_at) { return }  // newer un-pushed local edit wins over a remote delete
                        dead.deletedAt = row.deleted_at; dead.updatedAt = row.updated_at; dead.needsSync = false
                    }
                    return
                }
                let existing = try fetchByID(TransactionLocation.self, id: row.id, in: context)
                let loc: TransactionLocation
                if let existing { loc = existing } else {
                    loc = TransactionLocation(latitude: row.latitude, longitude: row.longitude,
                                              source: TransactionLocationSource(rawValue: row.source_raw) ?? .manual)
                    loc.id = row.id
                    loc.needsSync = false
                    context.insert(loc)
                }
                if Self.localChangeWins(localNeedsSync: loc.needsSync, localUpdatedAt: loc.updatedAt, remoteUpdatedAt: row.updated_at) { return }
                loc.displayName = row.display_name; loc.fullAddress = row.full_address
                loc.shortAddress = row.short_address; loc.latitude = row.latitude; loc.longitude = row.longitude
                loc.horizontalAccuracyMeters = row.horizontal_accuracy_meters; loc.capturedAt = row.captured_at
                loc.sourceRaw = row.source_raw; loc.applePlaceID = row.apple_place_id
                loc.alternateApplePlaceIDs = row.alternate_apple_place_ids
                loc.pointOfInterestCategoryRaw = row.point_of_interest_category_raw
                loc.locality = row.locality; loc.administrativeArea = row.administrative_area
                loc.countryCode = row.country_code; loc.normalizedSpatialKey = row.normalized_spatial_key
                loc.updatedAt = row.updated_at; loc.deletedAt = row.deleted_at
                loc.syncUserID = row.user_id; loc.needsSync = false
                // Link to its owning transaction.
                if let tid = row.transaction_id, let t = try fetchByID(Transaction.self, id: tid, in: context) {
                    t.location = loc
                }
            }
            try context.save()
        }
    }

    // MARK: - Helpers

    /// Page size for pull/push (PostgREST caps responses at ~1000 rows).
    private static let pageSize = 1000

    /// Fetches all rows for `table` changed since its cursor, paginating so large
    /// datasets (e.g. first sync) aren't silently truncated.
    private func fetchChanged<Row: Decodable>(_ table: String, _ client: SupabaseClient, _ uid: UUID) async throws -> [Row] {
        let cursor = Self.cursorString(for: table)
        var all: [Row] = []
        var offset = 0
        while true {
            var filter = client.from(table).select().eq("user_id", value: uid.uuidString)
            if let cursor { filter = filter.gt("updated_at", value: cursor) }
            let page: [Row] = try await filter
                .order("updated_at", ascending: true)
                .range(from: offset, to: offset + Self.pageSize - 1)
                .execute().value
            all.append(contentsOf: page)
            if page.count < Self.pageSize { break }
            offset += Self.pageSize
        }
        // Any rows changed past our cursor count as remote changes to apply, so
        // the completion broadcast (and a UI refresh) is warranted.
        if !all.isEmpty { didApplyRemoteChanges = true }
        return all
    }

    /// Upserts rows in chunks so a large first push isn't one oversized request,
    /// returning the server's stored representation so the caller can write the
    /// trigger-assigned `updated_at` back onto the local models.
    @discardableResult
    private func upsertInChunks<R: SyncServerRow>(_ rows: [R], to table: String, _ client: SupabaseClient) async throws -> [R] {
        guard !rows.isEmpty else { return [] }
        var returned: [R] = []
        returned.reserveCapacity(rows.count)
        var index = 0
        while index < rows.count {
            let chunk = Array(rows[index..<min(index + Self.pageSize, rows.count)])
            // `upsert` returns the stored rows by default (Prefer: return=representation).
            let page: [R] = try await client.from(table).upsert(chunk).execute().value
            returned.append(contentsOf: page)
            index += Self.pageSize
        }
        return returned
    }

    /// Writes the server-authoritative `updated_at` from an upsert's returned rows
    /// back onto the just-pushed local models. Now that the DB trigger stamps
    /// `updated_at` on insert as well as update, the server's value differs from
    /// the device clock the row was created with; mirroring it locally keeps the
    /// last-write-wins key and the pull cursor in a single (server) clock domain,
    /// so a skewed device clock can't make a freshly inserted row sort below other
    /// devices' cursors and go unpulled. Runs under the sync-write guard.
    func writeBackServerTimestamps<R: SyncServerRow>(_ returned: [R], to models: [any SyncTrackable]) {
        guard !returned.isEmpty else { return }
        let dates = Dictionary(returned.map { ($0.id, $0.updated_at) }, uniquingKeysWith: { first, _ in first })
        for m in models {
            if let d = dates[m.id] { m.updatedAt = d }
        }
    }

    /// Applies pulled rows under the sync-write guard and advances the cursor.
    private func applyLocal<Row>(
        table: String,
        rows: [Row],
        context: ModelContext,
        rowDate: (Row) -> Date,
        rowID: (Row) -> UUID,
        apply: (Row) throws -> Void
    ) rethrows {
        // (sync-write guard is held for the whole syncNow operation)
        var maxDate = Self.cursorDate(for: table) ?? .distantPast
        for row in rows {
            try apply(row)
            maxDate = max(maxDate, rowDate(row))
        }
        Self.setCursor(maxDate, for: table)
    }

    private func fetchByID<T: PersistentModel>(_ type: T.Type, id: UUID, in context: ModelContext) throws -> T? {
        // Concrete predicates per type (PersistentModel id isn't usable generically in #Predicate).
        if T.self == Wallet.self {
            return try context.fetch(FetchDescriptor<Wallet>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == Category.self {
            return try context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == Transaction.self {
            return try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == Event.self {
            return try context.fetch(FetchDescriptor<Event>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == Debt.self {
            return try context.fetch(FetchDescriptor<Debt>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == SavingsGoal.self {
            return try context.fetch(FetchDescriptor<SavingsGoal>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == RecurringRule.self {
            return try context.fetch(FetchDescriptor<RecurringRule>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == EventMember.self {
            return try context.fetch(FetchDescriptor<EventMember>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == EventLedgerTransaction.self {
            return try context.fetch(FetchDescriptor<EventLedgerTransaction>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == EventLedgerParticipant.self {
            return try context.fetch(FetchDescriptor<EventLedgerParticipant>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == EventSettlementSnapshot.self {
            return try context.fetch(FetchDescriptor<EventSettlementSnapshot>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == EventSettlementTransfer.self {
            return try context.fetch(FetchDescriptor<EventSettlementTransfer>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == EventWalletExportRecord.self {
            return try context.fetch(FetchDescriptor<EventWalletExportRecord>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == Budget.self {
            return try context.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.id == id })).first as? T
        } else if T.self == TransactionLocation.self {
            return try context.fetch(FetchDescriptor<TransactionLocation>(predicate: #Predicate { $0.id == id })).first as? T
        }
        return nil
    }

    // MARK: - Storage (images)

    /// Storage object path. The first folder MUST be the lowercased user id to
    /// satisfy the receipts-bucket RLS policy (compares to auth.uid()::text).
    private func imagePath(_ uid: UUID, _ folder: String, _ id: UUID) -> String {
        "\(uid.uuidString.lowercased())/\(folder)/\(id.uuidString.lowercased()).jpg"
    }

    private func uploadImage(_ data: Data, to path: String, _ client: SupabaseClient) async throws {
        _ = try await client.storage.from("receipts").upload(
            path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
    }

    private func downloadImage(_ path: String, _ client: SupabaseClient) async throws -> Data {
        try await client.storage.from("receipts").download(path: path)
    }

    /// Downloads an image and stores it on its model. On success the matching
    /// retry-queue entry is cleared; on failure it is enqueued durably so a later
    /// sync retries instead of leaving the row permanently image-less (its cursor
    /// has already advanced, so the row itself never re-pulls to trigger this).
    private func downloadAndStoreImage(_ path: String, kind: SyncImageKind, id: UUID,
                                       _ client: SupabaseClient, _ context: ModelContext) async {
        let entry = SyncImageDownloadQueue.Entry(kind: kind, id: id, path: path)
        do {
            let data = try await downloadImage(path, client)
            let hash = Self.sha256(data)
            switch kind {
            case .transactionPhoto:
                if let t = try fetchByID(Transaction.self, id: id, in: context) {
                    t.photoData = data
                    t.photoUploadedHash = hash
                }
            case .eventCover:
                if let e = try fetchByID(Event.self, id: id, in: context) {
                    e.coverImageData = data
                    e.coverImageUploadedHash = hash
                }
            case .memberAvatar:
                if let m = try fetchByID(EventMember.self, id: id, in: context) {
                    m.avatarData = data
                    m.avatarUploadedHash = hash
                }
            }
            SyncImageDownloadQueue.remove(entry)
        } catch {
            #if DEBUG
            print("[SyncEngine] image download failed (\(kind.rawValue) \(id)) — queued for retry: \(error)")
            #endif
            SyncImageDownloadQueue.enqueue(entry)
        }
    }

    /// Retries every image that failed to download in an earlier sync. Runs at the
    /// end of `syncNow`; successes clear themselves from the queue.
    private func drainImageDownloads(_ client: SupabaseClient, _ context: ModelContext) async {
        let pending = SyncImageDownloadQueue.all()
        guard !pending.isEmpty else { return }
        for entry in pending {
            // Skip (and clear) if the row already has its image — a stale entry.
            if imageAlreadyPresent(entry, context) {
                SyncImageDownloadQueue.remove(entry)
                continue
            }
            await downloadAndStoreImage(entry.path, kind: entry.kind, id: entry.id, client, context)
        }
        withSyncWriteGuard { try? context.save() }
    }

    private func imageAlreadyPresent(_ entry: SyncImageDownloadQueue.Entry, _ context: ModelContext) -> Bool {
        switch entry.kind {
        case .transactionPhoto:
            return ((try? fetchByID(Transaction.self, id: entry.id, in: context)) ?? nil)?.photoData != nil
        case .eventCover:
            return ((try? fetchByID(Event.self, id: entry.id, in: context)) ?? nil)?.coverImageData != nil
        case .memberAvatar:
            return ((try? fetchByID(EventMember.self, id: entry.id, in: context)) ?? nil)?.avatarData != nil
        }
    }

    // MARK: - Cursor persistence (per table, UserDefaults)

    private static func cursorKey(_ table: String) -> String { "syncCursor.v1.\(table)" }

    private static func cursorDate(for table: String) -> Date? {
        let t = UserDefaults.standard.double(forKey: cursorKey(table))
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    private static func cursorString(for table: String) -> String? {
        guard let date = cursorDate(for: table) else { return nil }
        return isoFormatter.string(from: date)
    }

    private static func setCursor(_ date: Date, for table: String) {
        guard date > .distantPast else { return }
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: cursorKey(table))
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

/// Lets `finishPush` stamp — and `purgeForeignRows` inspect — the owning
/// account uniformly across entity types.
protocol SyncOwned: AnyObject {
    nonisolated func assignOwner(_ uid: UUID)
    nonisolated var syncOwner: UUID? { get }
}
extension Wallet: SyncOwned {
    func assignOwner(_ uid: UUID) { syncUserID = uid }
    var syncOwner: UUID? { syncUserID }
}
extension Category: SyncOwned {
    func assignOwner(_ uid: UUID) { syncUserID = uid }
    var syncOwner: UUID? { syncUserID }
}
extension Transaction: SyncOwned {
    func assignOwner(_ uid: UUID) { syncUserID = uid }
    var syncOwner: UUID? { syncUserID }
}
extension Event: SyncOwned {
    func assignOwner(_ uid: UUID) { syncUserID = uid }
    var syncOwner: UUID? { syncUserID }
}
extension Debt: SyncOwned {
    func assignOwner(_ uid: UUID) { syncUserID = uid }
    var syncOwner: UUID? { syncUserID }
}
extension SavingsGoal: SyncOwned {
    func assignOwner(_ uid: UUID) { syncUserID = uid }
    var syncOwner: UUID? { syncUserID }
}
extension RecurringRule: SyncOwned {
    func assignOwner(_ uid: UUID) { syncUserID = uid }
    var syncOwner: UUID? { syncUserID }
}
extension EventMember: SyncOwned {
    func assignOwner(_ uid: UUID) { syncUserID = uid }
    var syncOwner: UUID? { syncUserID }
}
extension EventLedgerTransaction: SyncOwned {
    func assignOwner(_ uid: UUID) { syncUserID = uid }
    var syncOwner: UUID? { syncUserID }
}
extension EventLedgerParticipant: SyncOwned {
    func assignOwner(_ uid: UUID) { syncUserID = uid }
    var syncOwner: UUID? { syncUserID }
}
extension EventSettlementSnapshot: SyncOwned {
    func assignOwner(_ uid: UUID) { syncUserID = uid }
    var syncOwner: UUID? { syncUserID }
}
extension EventSettlementTransfer: SyncOwned {
    func assignOwner(_ uid: UUID) { syncUserID = uid }
    var syncOwner: UUID? { syncUserID }
}
extension EventWalletExportRecord: SyncOwned {
    func assignOwner(_ uid: UUID) { syncUserID = uid }
    var syncOwner: UUID? { syncUserID }
}
extension Budget: SyncOwned {
    func assignOwner(_ uid: UUID) { syncUserID = uid }
    var syncOwner: UUID? { syncUserID }
}
extension TransactionLocation: SyncOwned {
    func assignOwner(_ uid: UUID) { syncUserID = uid }
    var syncOwner: UUID? { syncUserID }
}
