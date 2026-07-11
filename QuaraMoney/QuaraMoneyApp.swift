//
//  QuaraMoneyApp.swift
//  QuaraMoney
//
//  Created by Udorm Phon on 01-02-2026.
//

import SwiftUI
import SwiftData

@main
struct QuaraMoneyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var languageManager = LanguageManager.shared
    @StateObject private var errorService = ErrorService.shared
    @StateObject private var securityManager = SecurityManager.shared
    @StateObject private var authManager = SupabaseAuthManager.shared
    // NOTE: deliberately NOT observing SyncEngine here — its isSyncing/lastSyncDate
    // churn would invalidate the whole scene on every auto-sync. The conflict
    // sheet observes it from a leaf modifier instead (SyncConflictPresenter).
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPrivacyOverlay = false
    @State private var showSplash = !_hasShownSplash
    /// Main-actor-only (read in the App's init and written from the splash
    /// completion, both on the main actor).
    @MainActor private static var _hasShownSplash = false
    
    init() {
        // All heavy work deferred to .task{} modifiers
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
                            .task {
                                setupServices()
                            }
                    } else {
                        OnboardingView()
                    }
                }
                .opacity(showSplash ? 0 : 1)

                if showSplash {
                    SplashScreenView {
                        Self._hasShownSplash = true
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSplash = false
                        }
                        // Cold-launch quick action: hand the staged shortcut to
                        // the router now that the splash is gone — HomeView
                        // presents the sheet as soon as it's visible.
                        Self.transferPendingShortcutToRouter()
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
                // Track local edits so the sync engine can detect changes.
                // Harmless when sync is off (just stamps local metadata).
                SyncMutationTracker.start(mainContext: sharedModelContainer.mainContext)
                // Auto-sync after local edits (debounced); no-op when sync is off.
                SyncEngine.shared.enableAutoSync(context: sharedModelContainer.mainContext)
                // Restore an existing session on launch when sync is enabled.
                if SupabaseFeatureFlags.isSyncEnabled {
                    authManager.start()
                }
            }
            .onChange(of: authManager.state) { _, _ in
                if authManager.isSignedIn {
                    // A password-recovery link signs the user in, but they came
                    // to set a new password — deferring the pipeline keeps the
                    // data-conflict sheet from landing on top of the reset
                    // sheet. Re-run below when the reset finishes.
                    guard !authManager.passwordRecoveryPending else { return }
                    runPostSignInPipeline()
                } else {
                    SyncRealtime.shared.stop()
                }
            }
            .onChange(of: authManager.passwordRecoveryPending) { _, pending in
                // Password reset finished (saved or dismissed): run the pipeline
                // that was deferred when the recovery link signed the user in.
                if !pending && authManager.isSignedIn {
                    runPostSignInPipeline()
                }
            }
            .preferredColorScheme(selectedTheme.colorScheme)
            .task {
                // Deferred from init() — runs after first frame renders
                UIFont.setupAppAppearance()
                // Pre-warm common font sizes on background thread for smoother scrolling
                UIFont.prewarmFontCache()
            }
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
                    // Returning to the foreground: prompt for biometrics if locked.
                    if securityManager.isAppLocked {
                        securityManager.authenticate()
                    }
                    // Pull any changes from other devices, then resume live updates.
                    Task { await SyncEngine.shared.syncIfOperational(context: sharedModelContainer.mainContext) }
                    SyncRealtime.shared.start(context: sharedModelContainer.mainContext)
                    // Re-arm reminders and refresh the due badge for any rules that
                    // came due while we were away.
                    Task { await RecurringNotificationService.rescheduleAll(in: sharedModelContainer.mainContext) }
                @unknown default:
                    break
                }
            }
            .task {
                // Lock on cold launch if the user enabled app-lock.
                if securityManager.isAppLockEnabled {
                    securityManager.isAppLocked = true
                }
                // Rare path: a shortcut arrived on a scene (re)connect in a
                // process where the splash won't show — hand it over directly.
                if !showSplash {
                    Self.transferPendingShortcutToRouter()
                }
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
    
    /// Post-sign-in sync pipeline: account reconcile + first-sign-in conflict
    /// check, then sync + Realtime. Runs on auth-state change — or, when the
    /// sign-in came from a password-recovery link, after the reset sheet closes.
    private func runPostSignInPipeline() {
        let context = sharedModelContainer.mainContext
        // If a different account previously owned this device's local
        // data, clear it before adopting the new account (prevents
        // cross-account data mixing).
        SyncEngine.shared.reconcileAccountIfNeeded(context: context)
        Task {
            // On first-ever sign-in: check whether both the device and
            // cloud have existing data. `.conflict` pauses sync and
            // shows the resolution sheet; `.checkFailed` (network)
            // blocks sync entirely — proceeding could push duplicate
            // data into an unverified cloud state. Realtime is also
            // deferred in both cases.
            switch await SyncEngine.shared.checkFirstSignInConflict(context: context) {
            case .noConflict:
                await SyncEngine.shared.syncIfOperational(context: context)
                SyncRealtime.shared.start(context: context)
            case .conflict, .checkFailed:
                break
            }
        }
    }

    /// Once per launch: the `.task` that calls this is attached to ContentView,
    /// whose identity resets on language change (`.id(fontRefreshID)`) — without
    /// the guard, every language switch re-ran budget rollovers, category
    /// stamping, and the notification setup.
    @MainActor private static var didRunSetupServices = false

    private func setupServices() {
        guard !Self.didRunSetupServices else { return }
        Self.didRunSetupServices = true

        let container = sharedModelContainer

        // Capture MainActor data to pass to background tasks
        let rates = CurrencyManager.shared.rates
        let preferredCurrency = CurrencyManager.shared.preferredCurrencyCode
        
        // Perform heavy database operations in background (utility priority to avoid competing with UI)
        Task.detached(priority: .utility) {
            let context = ModelContext(container)

            // Recurring rules are confirm-before-post: they are NOT auto-generated
            // on launch. Due occurrences surface in the Recurring review inbox.
            // Refresh due-date reminders to match the current rules (the helper is
            // @MainActor, so its ModelContext is created and used on the main actor).
            await Self.rescheduleRecurringReminders(container)

            // Check budget rollovers
            BudgetRolloverService.checkAndProcessBudgetRollovers(
                modelContext: context,
                rates: rates,
                preferredCurrency: preferredCurrency
            )

            // Snapshot ownership before touching categories: if a first-sign-in
            // conflict resolution claims the device while this task is running,
            // its wipe/pull races our background context — roll back instead of
            // saving stale inserts on top of the freshly adopted cloud data.
            let ownedAtStart = SyncEngine.isLocalStoreAccountOwned
            do {
                // Stamp canonical keys onto pre-key categories and merge duplicates
                // (idempotent; runs for owned devices too so legacy cloud rows gain
                // keys and cross-language/dual-device duplicates self-heal).
                try CategoryCatalog.stampAndDedupe(in: context, owner: SyncEngine.localOwnerUUID)

                // Seed/ensure default categories ONLY on a device that has never
                // been claimed by a cloud account. Once the device is account-owned,
                // categories are authoritative in the cloud and arrive via sync;
                // auto-seeding here would re-create them after any sync wipe (e.g.
                // "Use Cloud Data") and push duplicates back up.
                if !ownedAtStart {
                    try CategoryCatalog.seedDefaultsIfEmpty(in: context)
                    for def in CategoryCatalog.all where def.ensureOnLaunch {
                        _ = try CategoryCatalog.fetchOrCreate(key: def.key, in: context)
                    }
                }

                if SyncEngine.isLocalStoreAccountOwned != ownedAtStart {
                    context.rollback()
                } else {
                    try context.save()
                }
            } catch {
                #if DEBUG
                print("[Setup] Failed to save default data: \(error)")
                #endif
            }
        }
        // Defer notification setup to avoid blocking the main thread at launch
        Task { @MainActor in
            // Let the UI settle before loading notifications
            try? await Task.sleep(for: .seconds(2))
            let mainContext = sharedModelContainer.mainContext
            BudgetNotificationService.shared.configure(modelContext: mainContext)
            BudgetNotificationService.shared.loadNotifications()
            BudgetNotificationService.shared.setupNotificationCategories()

            // Opportunistically refresh FX rates so display-time conversions
            // (reports, net worth, budgets in the preferred currency) are current.
            // fetchRates() self-throttles to once per 24h, so this is cheap and
            // runs for all users — including USD-base users, who previously never
            // refreshed. Historical wallet balances are unaffected: they derive
            // from each transaction's stored rate, not these live rates.
            await CurrencyManager.shared.fetchRates()
        }
    }

    /// Rebuilds recurring due-date reminders on launch. `@MainActor` so the
    /// `ModelContext` is created and consumed entirely on the main actor.
    @MainActor
    private static func rescheduleRecurringReminders(_ container: ModelContainer) async {
        await RecurringNotificationService.rescheduleAll(in: ModelContext(container))
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
