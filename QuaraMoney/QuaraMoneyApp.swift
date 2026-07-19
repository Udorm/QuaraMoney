//
//  QuaraMoneyApp.swift
//  QuaraMoney
//
//  Created by Udorm Phon on 01-02-2026.
//

import SwiftUI
import SwiftData
import Combine
import Supabase

nonisolated private struct MaintenanceDatabaseResult: Sendable {
    let commit: StartupMaintenanceGuard.CommitResult
    let planMarkerKey: String
}

nonisolated private enum MaintenanceDatabaseOutcome: Sendable {
    case saved(MaintenanceDatabaseResult)
    case invalidated
    case failed
}

@main
struct QuaraMoneyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var languageManager = LanguageManager.shared
    @StateObject private var errorService = ErrorService.shared
    @State private var securityManager: SecurityManager
    @StateObject private var authManager = SupabaseAuthManager.shared
    @AppStorage("isSupabaseSyncEnabled") private var isSyncEnabled = false
    // NOTE: deliberately NOT observing SyncEngine here — its isSyncing/lastSyncDate
    // churn would invalidate the whole scene on every auto-sync. The conflict
    // sheet observes it from a leaf modifier instead (SyncConflictPresenter).
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPrivacyOverlay = false
    @State private var showSplash: Bool
    @State private var authGeneration = 0
    @State private var accountPipelineState: AccountPipelineState = .sessionRestoring
    @State private var accountMaintenanceCompleted = false
    @State private var maintenanceTask: Task<Void, Never>?
    @State private var pipelineTask: Task<Void, Never>?
    @State private var reminderRebuildInFlight = false
    /// Main-actor-only (read in the App's init and written from the splash
    /// completion, both on the main actor).
    @MainActor private static var _hasShownSplash = false
    
    init() {
        let container = Self.sharedContainer
        let securityManager = SecurityManager.shared
        _securityManager = State(initialValue: securityManager)
        _showSplash = State(initialValue: !Self._hasShownSplash)

        // Critical phase: install save tracking and appearance before any scene
        // content can mount beneath the short splash.
        SyncMutationTracker.start(mainContext: container.mainContext)
        SyncEngine.shared.enableAutoSync(context: container.mainContext)
        UIFont.setupAppAppearance()
    }
    
    // MARK: - ModelContainer (lazily created on first access)

    /// The one shared container, also used by non-SwiftUI entry points (the
    /// notification delegate, BGTask handlers). `static let` gives thread-safe,
    /// lazy, once-only initialization (guaranteed by Swift) — replacing the
    /// previous unsynchronized `nonisolated(unsafe)` cache, which could race
    /// and build two containers when first touched off the main thread.
    static let sharedContainer: ModelContainer = makeModelContainer()

    private var sharedModelContainer: ModelContainer {
        Self.sharedContainer
    }
    
    // Derive the active schema from the versioned baseline so the container and
    // the migration plan can never drift apart. Bump this to the latest
    // VersionedSchema when SchemaV2 is introduced.
    private static let modelSchema = Schema(versionedSchema: SchemaV1.self)

    private static func makeModelContainer() -> ModelContainer {
        let modelConfiguration = ModelConfiguration(schema: modelSchema, isStoredInMemoryOnly: false)

        do {
            // SchemaV1 is the launch baseline (post-`.unique`-removal). The plan
            // has no stages yet; adding SchemaV2 + a MigrationStage here is what
            // lets future schema changes migrate instead of falling into the
            // (now non-destructive) recovery path below.
            return try ModelContainer(
                for: modelSchema,
                migrationPlan: QuaraMoneySchemaMigrationPlan.self,
                configurations: [modelConfiguration]
            )
        } catch {
            // First failure: try deleting the corrupted store and recreating
            #if DEBUG
            print("ModelContainer creation failed: \(error). Attempting recovery by deleting store.")
            #endif
            return recoverModelContainer(originalError: error)
        }
    }

    /// Attempts to recover from a corrupted ModelContainer.
    ///
    /// IMPORTANT: this is a finance app — the on-disk store is the user's only
    /// copy of their financial history. Before removing the corrupted store we
    /// move it aside to a timestamped backup so the data is recoverable (support
    /// can restore it, or a future migration can re-import it) instead of being
    /// silently and permanently destroyed.
    private static func recoverModelContainer(originalError: Error) -> ModelContainer {
        if let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let defaultStoreURL = storeURL.appendingPathComponent("default.store")
            let stamp = Int(Date().timeIntervalSince1970)
            let suffixes = ["", "-wal", "-shm"]

            for suffix in suffixes {
                let liveURL = URL(fileURLWithPath: defaultStoreURL.path + suffix)
                guard FileManager.default.fileExists(atPath: liveURL.path) else { continue }

                // Preserve the corrupted store as a backup rather than deleting it.
                let backupURL = URL(fileURLWithPath: defaultStoreURL.path + ".corrupt-\(stamp)" + suffix)
                do {
                    try FileManager.default.moveItem(at: liveURL, to: backupURL)
                } catch {
                    // If we cannot move it aside, fall back to removing so the app
                    // can at least launch — but log loudly.
                    #if DEBUG
                    print("[Recovery] Could not back up \(liveURL.lastPathComponent): \(error). Removing instead.")
                    #endif
                    try? FileManager.default.removeItem(at: liveURL)
                }
            }
            UserDefaults.standard.set(true, forKey: "didRecoverCorruptStore")
            UserDefaults.standard.set(stamp, forKey: "lastStoreRecoveryStamp")
        }

        let modelConfiguration = ModelConfiguration(schema: modelSchema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(
                for: modelSchema,
                migrationPlan: QuaraMoneySchemaMigrationPlan.self,
                configurations: [modelConfiguration]
            )
        } catch {
            // Last resort: use in-memory store so the app doesn't crash-loop
            #if DEBUG
            print("Recovery failed: \(error). Using in-memory store.")
            #endif
            let inMemoryConfig = ModelConfiguration(schema: modelSchema, isStoredInMemoryOnly: true)
            // If even in-memory fails, there's a fundamental code issue — crash is appropriate
            return try! ModelContainer(for: modelSchema, configurations: [inMemoryConfig])
        }
    }
    
    /// The default cascaded font for the entire app (computed once, then cached by NSCache)
    private static let defaultAppFont: Font = Font(UIFont.appWithCascade(ofSize: 17, weight: .regular))

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if isOnboardingCompleted {
                        ContentView()
                            .task(id: showSplash) {
                                setupGlobalServicesIfNeeded()
                                guard !showSplash else { return }
                                startAccountMaintenanceIfNeeded()
                            }
                    } else {
                        OnboardingView()
                    }
                }
                .opacity(showSplash ? 0 : 1)

                if showSplash {
                    SplashScreenView {
                        finishSplash()
                    }
                    .transition(.opacity)
                }

                // Biometric gate: covers all content (including the privacy
                // overlay) until the user authenticates.
                if securityManager.isAppLocked {
                    AppLockView {
                        securityManager.authenticate()
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .environment(\.font, Self.defaultAppFont)
            // Force view recreation when language changes
            .id(languageManager.fontRefreshID)
            .environmentObject(languageManager)
            .environmentObject(authManager)
            .onOpenURL { url in
                // Auth callbacks (magic link / email confirmation / password
                // recovery) for the quaramoney:// scheme. No-op when sync is
                // off / unconfigured.
                authManager.handleCallback(url)
            }
            // Password-recovery links sign the user in and must land on the
            // "set new password" step, wherever the app was when the link opened.
            .sheet(isPresented: $authManager.passwordRecoveryPending) {
                ResetPasswordSheetView()
                    .environmentObject(authManager)
            }
            .task {
                // Restore an existing session on launch when sync is enabled.
                if SupabaseFeatureFlags.isSyncEnabled {
                    authManager.start()
                } else {
                    accountPipelineState = .notApplicable
                    startAccountMaintenanceIfNeeded()
                }
                // Rare path: a shortcut arrived on a scene (re)connect in a
                // process where the splash won't show — hand it over directly.
                if !showSplash {
                    Self.transferPendingShortcutToRouter()
                }
            }
            .onChange(of: authManager.state) { _, _ in
                handleAuthTransition()
            }
            .onChange(of: isSyncEnabled) { _, _ in
                handleAuthTransition()
            }
            .onChange(of: authManager.passwordRecoveryPending) { _, pending in
                // Password reset finished (saved or dismissed): run the pipeline
                // that was deferred when the recovery link signed the user in.
                if !pending && authManager.isSignedIn {
                    guard let userID = currentAuthUserID else { return }
                    runPostSignInPipeline(userID: userID, generation: authGeneration)
                }
            }
            .preferredColorScheme(selectedTheme.colorScheme)
            .alert(
                item: $errorService.currentError
            ) { appError in
                Alert(
                    title: Text(appError.title),
                    message: Text(appError.message),
                    dismissButton: .default(Text(L10n.Common.ok)) {
                        errorService.dismiss()
                    }
                )
            }
            // Conflict sheet + deferred-Realtime start; observes SyncEngine in a
            // leaf modifier so sync ticks don't invalidate the whole scene.
            .syncConflictPresenter(mainContext: sharedModelContainer.mainContext)
            .overlay {
                if showPrivacyOverlay {
                    ZStack {
                        Color(.systemBackground)
                            .ignoresSafeArea()
                        Image(systemName: "lock.shield.fill")
                            .appFont(size: 48)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                withAnimation(.easeInOut(duration: 0.15)) {
                    showPrivacyOverlay = (newPhase != .active)
                }

                switch newPhase {
                case .background, .inactive:
                    // Lock when leaving the foreground (no-op unless the user
                    // enabled app-lock in Settings).
                    securityManager.lockApp()
                    // Release the Realtime connection while backgrounded.
                    SyncRealtime.shared.stop()
                    // Queue the next background re-arm of recurring reminders/badge.
                    if newPhase == .background {
                        RecurringBackgroundRefresh.schedule()
                    }
                case .active:
                    BudgetNotificationService.shared.evaluateStore()
                    // Returning to the foreground: prompt for biometrics if locked.
                    if securityManager.isAppLocked {
                        securityManager.authenticate()
                    }
                    // Pull any changes from other devices, then resume live updates.
                    let generation = authGeneration
                    let userID = currentAuthUserID
                    Task { @MainActor in
                        await SyncEngine.shared.syncIfOperational(context: sharedModelContainer.mainContext)
                        guard StartupMaintenanceGuard.acceptsSettlementCompletion(
                            authUserID: userID,
                            generation: generation,
                            currentAuthUserID: currentAuthUserID,
                            currentGeneration: authGeneration
                        ) else { return }
                        await refreshRecurringRemindersIfSafe()
                    }
                    SyncRealtime.shared.start(context: sharedModelContainer.mainContext)
                @unknown default:
                    break
                }
            }
            .onReceive(SyncEngine.shared.$conflictState.removeDuplicates()) { _ in
                handleSyncSettlementChange()
            }
            .onReceive(SyncEngine.shared.$isSyncing.removeDuplicates()) { _ in
                handleSyncSettlementChange()
            }
            .onReceive(SyncEngine.shared.$hasCompletedInitialSync.removeDuplicates()) { _ in
                handleSyncSettlementChange()
            }
            .onReceive(NotificationCenter.default.publisher(for: .currencyRatesDidChange)) { _ in
                let context = sharedModelContainer.mainContext
                SyncEngine.shared.withSyncWriteGuard {
                    _ = try? SavingsGoalReconciler.reconcileAll(in: context, markNeedsSync: false)
                }
                NotificationCenter.default.post(name: .dataDidUpdate, object: CurrencyManager.shared)
            }
        }
        .modelContainer(sharedModelContainer)
    }
    
    
    @AppStorage("appTheme") private var selectedTheme: AppTheme = .system
    
    enum AppTheme: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
        
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .system: return "settings.theme.system".localized
            case .light: return "settings.theme.light".localized
            case .dark: return "settings.theme.dark".localized
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
        
        var icon: String {
            switch self {
            case .system: return "gear"
            case .light: return "sun.max"
            case .dark: return "moon"
            }
        }
    }
    
    private enum AccountPipelineState: Equatable {
        case notApplicable
        case sessionRestoring
        case checkingConflict
        case conflictPending
        case checkFailed
        case initialSyncInFlight
        case settled
    }

    private enum MaintenanceOutcome {
        case completed
        case invalidated
        case failed
    }

    /// The 2-second BudgetNotificationService timing is intentionally preserved.
    /// Account-scoped database maintenance has a separate completion lifecycle.
    @MainActor private static var didRunGlobalSetup = false

    private var currentAuthUserID: UUID? {
        SupabaseManager.shared.client?.auth.currentUser?.id
    }

    private var currentMaintenanceIdentity: StartupMaintenanceIdentity {
        StartupMaintenanceIdentity(
            authUserID: currentAuthUserID,
            localOwnerID: SyncEngine.localOwnerUUID,
            authGeneration: authGeneration
        )
    }

    private func finishSplash() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showSplash = false
        } completion: {
            Self._hasShownSplash = true
            Self.transferPendingShortcutToRouter()
            Task { @MainActor in
                await Task.yield()
                UIFont.prewarmFontCache()
            }
        }
    }

    private func handleAuthTransition() {
        authGeneration &+= 1
        let generation = authGeneration
        pipelineTask?.cancel()
        maintenanceTask?.cancel()
        pipelineTask = nil
        accountMaintenanceCompleted = false

        if reminderRebuildInFlight {
            Task { @MainActor in
                await RecurringNotificationService.clearAllPendingRequests()
            }
        }

        guard SupabaseFeatureFlags.isSyncEnabled else {
            accountPipelineState = .notApplicable
            SyncRealtime.shared.stop()
            startAccountMaintenanceIfNeeded()
            return
        }

        switch authManager.state {
        case .unknown:
            accountPipelineState = .sessionRestoring
        case .signedOut:
            accountPipelineState = .notApplicable
            SyncRealtime.shared.stop()
            startAccountMaintenanceIfNeeded()
        case .signedIn:
            guard !authManager.passwordRecoveryPending,
                  let userID = currentAuthUserID else {
                accountPipelineState = .sessionRestoring
                return
            }
            runPostSignInPipeline(userID: userID, generation: generation)
        }
    }

    /// Post-sign-in reconcile → conflict check → initial sync pipeline. Every
    /// completion is rejected if its auth user or generation is stale.
    private func runPostSignInPipeline(userID: UUID, generation: Int) {
        guard StartupMaintenanceGuard.acceptsSettlementCompletion(
            authUserID: userID,
            generation: generation,
            currentAuthUserID: currentAuthUserID,
            currentGeneration: authGeneration
        ) else { return }

        let context = sharedModelContainer.mainContext
        SyncEngine.shared.reconcileAccountIfNeeded(context: context)
        accountPipelineState = .checkingConflict

        pipelineTask?.cancel()
        pipelineTask = Task { @MainActor in
            let result = await SyncEngine.shared.checkFirstSignInConflict(context: context)
            guard StartupMaintenanceGuard.acceptsSettlementCompletion(
                authUserID: userID,
                generation: generation,
                currentAuthUserID: currentAuthUserID,
                currentGeneration: authGeneration
            ) else { return }

            switch result {
            case .noConflict:
                accountPipelineState = .initialSyncInFlight
                await SyncEngine.shared.syncIfOperational(context: context)
                guard StartupMaintenanceGuard.acceptsSettlementCompletion(
                    authUserID: userID,
                    generation: generation,
                    currentAuthUserID: currentAuthUserID,
                    currentGeneration: authGeneration
                ) else { return }
                if SyncEngine.shared.hasCompletedInitialSync && !SyncEngine.shared.isSyncing {
                    accountPipelineState = .settled
                    SyncRealtime.shared.start(context: context)
                }
            case .conflict:
                accountPipelineState = .conflictPending
            case .checkFailed:
                accountPipelineState = .checkFailed
            }
            startAccountMaintenanceIfNeeded()
        }
    }

    private func handleSyncSettlementChange() {
        let canAdvanceToSettled = accountPipelineState == .initialSyncInFlight ||
            accountPipelineState == .conflictPending ||
            accountPipelineState == .settled
        if canAdvanceToSettled,
           authManager.isSignedIn,
           SyncEngine.shared.conflictState == .none,
           SyncEngine.shared.hasCompletedInitialSync,
           !SyncEngine.shared.isSyncing {
            accountPipelineState = .settled
        }
        startAccountMaintenanceIfNeeded()
    }

    private func setupGlobalServicesIfNeeded() {
        guard isOnboardingCompleted, !Self.didRunGlobalSetup else { return }
        Self.didRunGlobalSetup = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            let mainContext = sharedModelContainer.mainContext
            BudgetNotificationService.shared.configure(modelContext: mainContext)
            BudgetNotificationService.shared.loadNotifications()
            BudgetNotificationService.shared.setupNotificationCategories()
        }
    }

    private func maintenancePolicyInput(
        settlementWait: StartupMaintenancePolicy.SettlementWait
    ) -> StartupMaintenancePolicy.Input {
        let syncEnabled = SupabaseFeatureFlags.isSyncEnabled
        let authState: StartupMaintenancePolicy.AuthState
        switch authManager.state {
        case .unknown:
            authState = .sessionRestoring
        case .signedOut:
            authState = .signedOut
        case .signedIn:
            authState = .signedIn
        }

        let conflictState: StartupMaintenancePolicy.ConflictState
        if !syncEnabled || authState == .signedOut {
            conflictState = .notApplicable
        } else if SyncEngine.shared.conflictState != .none || accountPipelineState == .conflictPending {
            conflictState = .pending
        } else {
            switch accountPipelineState {
            case .checkingConflict, .sessionRestoring:
                conflictState = .checking
            case .checkFailed:
                conflictState = .checkFailed
            case .settled:
                conflictState = .resolved
            default:
                conflictState = .checking
            }
        }

        let initialSyncState: StartupMaintenancePolicy.InitialSyncState
        if !syncEnabled || authState == .signedOut {
            initialSyncState = .notApplicable
        } else if SyncEngine.shared.isSyncing || accountPipelineState == .initialSyncInFlight {
            initialSyncState = .inFlight
        } else if SyncEngine.shared.hasCompletedInitialSync {
            initialSyncState = .idleCompleted
        } else {
            initialSyncState = .idleIncomplete
        }

        return StartupMaintenancePolicy.Input(
            isSyncEnabled: syncEnabled,
            authState: authState,
            conflictState: conflictState,
            initialSyncState: initialSyncState,
            settlementWait: settlementWait
        )
    }

    private func waitForAccountSettlement(
        authUserID: UUID?,
        generation: Int,
        timeout: Duration = .seconds(5)
    ) async -> StartupMaintenancePolicy.SettlementWait {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            guard StartupMaintenanceGuard.acceptsSettlementCompletion(
                authUserID: authUserID,
                generation: generation,
                currentAuthUserID: currentAuthUserID,
                currentGeneration: authGeneration
            ), !Task.isCancelled else { return .timedOut }
            let input = maintenancePolicyInput(settlementWait: .settled)
            if StartupMaintenancePolicy.decision(for: input) == .run {
                return .settled
            }
            if input.conflictState == .pending || input.conflictState == .checkFailed {
                return .settled
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return .timedOut
    }

    private func startAccountMaintenanceIfNeeded() {
        guard !showSplash,
              isOnboardingCompleted,
              !accountMaintenanceCompleted,
              maintenanceTask == nil else { return }

        let generation = authGeneration
        let authUserID = currentAuthUserID
        maintenanceTask = Task { @MainActor in
            var shouldRearm = false
            defer {
                maintenanceTask = nil
                if shouldRearm,
                   StartupMaintenancePolicy.shouldRearm(
                       after: .skipAndRearm,
                       with: maintenancePolicyInput(settlementWait: .settled)
                   ) {
                    startAccountMaintenanceIfNeeded()
                }
            }

            let wait = await waitForAccountSettlement(
                authUserID: authUserID,
                generation: generation
            )
            guard StartupMaintenanceGuard.acceptsSettlementCompletion(
                authUserID: authUserID,
                generation: generation,
                currentAuthUserID: currentAuthUserID,
                currentGeneration: authGeneration
            ), !Task.isCancelled else {
                shouldRearm = true
                return
            }
            let input = maintenancePolicyInput(settlementWait: wait)
            guard StartupMaintenancePolicy.decision(for: input) == .run else {
                shouldRearm = true
                return
            }
            let expectedIdentity = currentMaintenanceIdentity
            switch await performAccountMaintenance(expectedIdentity: expectedIdentity) {
            case .completed, .failed:
                break
            case .invalidated:
                accountMaintenanceCompleted = false
                shouldRearm = true
            }
        }
    }

    private func performAccountMaintenance(
        expectedIdentity: StartupMaintenanceIdentity
    ) async -> MaintenanceOutcome {
        guard StartupMaintenanceGuard.isCurrent(
            expectedIdentity,
            current: currentMaintenanceIdentity
        ) else { return .invalidated }

        // The rate request self-throttles to 24 hours and has a bounded timeout.
        // Failure leaves the cached/fallback table intact for rollover conversion.
        _ = await CurrencyManager.shared.fetchRates()
        guard !Task.isCancelled,
              StartupMaintenanceGuard.isCurrent(
                expectedIdentity,
                current: currentMaintenanceIdentity
              ) else { return .invalidated }

        let container = sharedModelContainer
        let maintenanceRates = CurrencyManager.shared.rates
        let databaseTask = Task.detached(priority: .utility) {
            guard !Task.isCancelled else {
                return MaintenanceDatabaseOutcome.invalidated
            }
            let identityBeforeWork = await MainActor.run {
                currentMaintenanceIdentity
            }
            guard StartupMaintenanceGuard.isCurrent(
                expectedIdentity,
                current: identityBeforeWork
            ), !Task.isCancelled else {
                return MaintenanceDatabaseOutcome.invalidated
            }

            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                try CategoryCatalog.stampAndDedupe(
                    in: context,
                    owner: expectedIdentity.localOwnerID
                )
                if expectedIdentity.localOwnerID == nil {
                    try CategoryCatalog.seedDefaultsIfEmpty(in: context)
                    for definition in CategoryCatalog.all where definition.ensureOnLaunch {
                        _ = try CategoryCatalog.fetchOrCreate(key: definition.key, in: context)
                    }
                }
                let planMaintenance = try PlanDataMaintenance.run(
                    in: context,
                    ownerID: expectedIdentity.localOwnerID,
                    rates: maintenanceRates,
                    commitsMarker: false
                )

                guard !Task.isCancelled else {
                    context.rollback()
                    return MaintenanceDatabaseOutcome.invalidated
                }
                let identityBeforeSave = await MainActor.run {
                    currentMaintenanceIdentity
                }
                guard !Task.isCancelled else {
                    context.rollback()
                    return MaintenanceDatabaseOutcome.invalidated
                }
                guard let commit = try StartupMaintenanceGuard.commit(
                    context: context,
                    expected: expectedIdentity,
                    currentIdentity: { identityBeforeSave }
                ) else {
                    return MaintenanceDatabaseOutcome.invalidated
                }
                return MaintenanceDatabaseOutcome.saved(
                    MaintenanceDatabaseResult(commit: commit, planMarkerKey: planMaintenance.markerKey)
                )
            } catch {
                context.rollback()
                #if DEBUG
                print("[Setup] Account maintenance failed: \(error)")
                #endif
                return MaintenanceDatabaseOutcome.failed
            }
        }

        let databaseOutcome = await withTaskCancellationHandler {
            await databaseTask.value
        } onCancel: {
            databaseTask.cancel()
        }

        switch databaseOutcome {
        case .invalidated:
            return .invalidated
        case .failed:
            return .failed
        case .saved(let result):
            guard !Task.isCancelled,
                  StartupMaintenanceGuard.isCurrent(
                    expectedIdentity,
                    current: currentMaintenanceIdentity
                  ) else { return .invalidated }

            // Completion belongs to this exact generation and is set only after
            // the guarded caller-owned save succeeds.
            accountMaintenanceCompleted = true
            UserDefaults.standard.set(true, forKey: result.planMarkerKey)

            if result.commit.hadChanges {
                NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            }

            guard StartupMaintenanceGuard.isCurrent(
                expectedIdentity,
                current: currentMaintenanceIdentity
            ) else {
                await RecurringNotificationService.clearAllPendingRequests()
                return .invalidated
            }

            reminderRebuildInFlight = true
            defer { reminderRebuildInFlight = false }
            let reminderContext = ModelContext(container)
            let rebuilt = await RecurringNotificationService.rescheduleAll(in: reminderContext) {
                StartupMaintenanceGuard.isCurrent(
                    expectedIdentity,
                    current: currentMaintenanceIdentity
                )
            }
            return rebuilt ? .completed : .invalidated
        }
    }

    private func refreshRecurringRemindersIfSafe() async {
        guard accountMaintenanceCompleted else {
            startAccountMaintenanceIfNeeded()
            return
        }
        guard maintenanceTask == nil, !reminderRebuildInFlight else { return }
        let input = maintenancePolicyInput(settlementWait: .settled)
        guard StartupMaintenancePolicy.decision(for: input) == .run else { return }
        let expectedIdentity = currentMaintenanceIdentity
        reminderRebuildInFlight = true
        defer { reminderRebuildInFlight = false }
        _ = await RecurringNotificationService.rescheduleAll(
            in: sharedModelContainer.mainContext
        ) {
            StartupMaintenanceGuard.isCurrent(
                expectedIdentity,
                current: currentMaintenanceIdentity
            )
        }
    }

    /// Moves a cold-launch quick-action shortcut onto the router, where the
    /// Home tab consumes it once visible. Replaces the old 1.5 s launch sleep.
    @MainActor
    private static func transferPendingShortcutToRouter() {
        guard AppDelegate.pendingShortcutType == AppDelegate.ShortcutType.addTransaction else { return }
        AppDelegate.pendingShortcutType = nil
        AppRouter.shared.pendingAddTransaction = true
    }
}
