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
    @ObservedObject private var syncEngine = SyncEngine.shared
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPrivacyOverlay = false
    @State private var showSplash = !_hasShownSplash
    nonisolated(unsafe) private static var _hasShownSplash = false
    
    init() {
        // All heavy work deferred to .task{} modifiers
    }
    
    // MARK: - ModelContainer (lazily created on first access)
    
    /// Cached container – created once, reused across body evaluations.
    /// Using nonisolated(unsafe) static because App struct is recreated on every body eval.
    nonisolated(unsafe) private static var _cachedContainer: ModelContainer?
    
    private var sharedModelContainer: ModelContainer {
        if let cached = Self._cachedContainer {
            return cached
        }
        let container = Self.makeModelContainer()
        Self._cachedContainer = container
        return container
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
                // Auth callbacks (magic link / email confirmation) for the
                // quaramoney:// scheme. No-op when sync is off / unconfigured.
                authManager.handleCallback(url)
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
                    let context = sharedModelContainer.mainContext
                    // If a different account previously owned this device's local
                    // data, clear it before adopting the new account (prevents
                    // cross-account data mixing).
                    SyncEngine.shared.reconcileAccountIfNeeded(context: context)
                    Task {
                        // On first-ever sign-in: check whether both the device and
                        // cloud have existing data. If so, pause sync and show the
                        // conflict resolution sheet (Realtime is also deferred to
                        // prevent a premature sync during the decision window).
                        let hasConflict = await SyncEngine.shared.checkFirstSignInConflict(context: context)
                        if !hasConflict {
                            await SyncEngine.shared.syncIfOperational(context: context)
                            SyncRealtime.shared.start(context: context)
                        }
                    }
                } else {
                    SyncRealtime.shared.stop()
                }
            }
            .onChange(of: syncEngine.conflictState) { _, newState in
                // Conflict resolved — start Realtime now (was deferred above).
                if newState == .none && authManager.isSignedIn {
                    SyncRealtime.shared.start(context: sharedModelContainer.mainContext)
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
            .sheet(isPresented: Binding(
                get: { syncEngine.conflictState != .none },
                set: { _ in }
            )) {
                DataConflictResolutionView()
            }
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
                case .active:
                    // Returning to the foreground: prompt for biometrics if locked.
                    if securityManager.isAppLocked {
                        securityManager.authenticate()
                    }
                    // Pull any changes from other devices, then resume live updates.
                    Task { await SyncEngine.shared.syncIfOperational(context: sharedModelContainer.mainContext) }
                    SyncRealtime.shared.start(context: sharedModelContainer.mainContext)
                @unknown default:
                    break
                }
            }
            .task {
                // Lock on cold launch if the user enabled app-lock.
                if securityManager.isAppLockEnabled {
                    securityManager.isAppLocked = true
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
    
    private func setupServices() {
        let container = sharedModelContainer
        
        // Capture MainActor data to pass to background tasks
        let rates = CurrencyManager.shared.rates
        let preferredCurrency = CurrencyManager.shared.preferredCurrencyCode
        
        let defaultCategories = [
            // Income
            DefaultCategoryData(name: L10n.Category.salary, icon: "dollarsign.circle", colorHex: "#4CAF50", type: .income),
            DefaultCategoryData(name: L10n.Category.investments, icon: "chart.line.uptrend.xyaxis", colorHex: "#2196F3", type: .income),
            DefaultCategoryData(name: L10n.Category.others, icon: "gift", colorHex: "#FFC107", type: .income),
            DefaultCategoryData(name: L10n.Category.debtAndLoans, icon: "banknote", colorHex: "#795548", type: .income),
            
            // Expense
            DefaultCategoryData(name: L10n.Category.foodAndDrink, icon: "fork.knife", colorHex: "#FF5722", type: .expense),
            DefaultCategoryData(name: L10n.Category.housing, icon: "house", colorHex: "#795548", type: .expense),
            DefaultCategoryData(name: L10n.Category.transportation, icon: "car", colorHex: "#03A9F4", type: .expense),
            DefaultCategoryData(name: L10n.Category.personalLifestyle, icon: "tshirt", colorHex: "#E91E63", type: .expense),
            DefaultCategoryData(name: L10n.Category.health, icon: "heart", colorHex: "#F44336", type: .expense),
            DefaultCategoryData(name: L10n.Category.education, icon: "book", colorHex: "#9C27B0", type: .expense),
            DefaultCategoryData(name: L10n.Category.tech, icon: "laptopcomputer", colorHex: "#607D8B", type: .expense),
            DefaultCategoryData(name: L10n.Category.leisure, icon: "gamecontroller", colorHex: "#673AB7", type: .expense),
            DefaultCategoryData(name: L10n.Category.subscriptions, icon: "arrow.triangle.2.circlepath", colorHex: "#3F51B5", type: .expense),
            DefaultCategoryData(name: L10n.Category.financial, icon: "building.columns", colorHex: "#009688", type: .expense),
            DefaultCategoryData(name: L10n.Category.debtAndLoans, icon: "banknote", colorHex: "#795548", type: .expense),
            DefaultCategoryData(name: L10n.Category.trip, icon: "airplane", colorHex: "#FF9800", type: .expense),
            DefaultCategoryData(name: L10n.Category.saving, icon: "banknote.fill", colorHex: "#4CAF50", type: .expense),
            DefaultCategoryData(name: L10n.Category.giftsAndDonations, icon: "gift.fill", colorHex: "#E91E63", type: .expense),
            
            // Bills
            DefaultCategoryData(name: L10n.Category.electricityBill, icon: "bolt", colorHex: "#FFEB3B", type: .expense),
            DefaultCategoryData(name: L10n.Category.waterBill, icon: "drop", colorHex: "#2196F3", type: .expense),
            DefaultCategoryData(name: L10n.Category.internetBill, icon: "wifi", colorHex: "#00BCD4", type: .expense)
        ]
        
        let debtCategoryName = L10n.Category.debtAndLoans
        
        let debtSystemCategoryDebt = L10n.Debt.SystemCategory.debt
        let debtSystemCategoryDebtCollection = L10n.Debt.SystemCategory.debtCollection
        let debtSystemCategoryLoan = L10n.Debt.SystemCategory.loan
        let debtSystemCategoryLoanRepayment = L10n.Debt.SystemCategory.loanRepayment
        let categoryTrip = L10n.Category.trip
        let categorySaving = L10n.Category.saving
        let categoryGiftsAndDonations = L10n.Category.giftsAndDonations
        
        let mustHaveCategories: [(String, String, String, TransactionType)] = [
            // Income
            (L10n.Category.salary, "dollarsign.circle", "#4CAF50", .income),
            (L10n.Category.investments, "chart.line.uptrend.xyaxis", "#2196F3", .income),
            (L10n.Category.others, "gift", "#FFC107", .income),
            // Expense
            (L10n.Category.foodAndDrink, "fork.knife", "#FF5722", .expense),
            (L10n.Category.housing, "house", "#795548", .expense),
            (L10n.Category.transportation, "car", "#03A9F4", .expense),
            (L10n.Category.health, "heart", "#F44336", .expense),
            (L10n.Category.financial, "building.columns", "#009688", .expense),
            (L10n.Category.debtAndLoans, "banknote", "#795548", .expense),
            (L10n.Category.trip, "airplane", "#FF9800", .expense),
            (L10n.Category.saving, "banknote.fill", "#4CAF50", .expense),
            // Bills
            (L10n.Category.electricityBill, "bolt", "#FFEB3B", .expense),
            (L10n.Category.waterBill, "drop", "#2196F3", .expense),
            (L10n.Category.internetBill, "wifi", "#00BCD4", .expense),
        ]
        
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
            
            // Seed/ensure default categories ONLY on a device that has never been
            // claimed by a cloud account. Once the device is account-owned,
            // categories are authoritative in the cloud and arrive via sync;
            // auto-seeding here would re-create them with fresh random UUIDs after
            // any sync wipe (e.g. "Use Cloud Data") and push duplicates back up —
            // the root cause of recurring category duplication.
            if !SyncEngine.isLocalStoreAccountOwned {
            // Seed default categories if needed
            DefaultDataService.seedDefaultCategories(modelContext: context, data: defaultCategories)

            // Ensure System Categories for Debt & Loan
            // 1. Debt (Lending out money) - Expense
            DefaultDataService.ensureSystemCategoryExists(
                modelContext: context,
                name: debtSystemCategoryDebt,
                icon: "arrow.up.right",
                colorHex: "#FF3B30",
                type: .expense
            )
            
            // 2. Debt Collection (Receiving money back) - Income
            DefaultDataService.ensureSystemCategoryExists(
                modelContext: context,
                name: debtSystemCategoryDebtCollection,
                icon: "tray.and.arrow.down.fill",
                colorHex: "#34C759",
                type: .income
            )
            
            // 3. Loan (Borrowing money) - Income
            DefaultDataService.ensureSystemCategoryExists(
                modelContext: context,
                name: debtSystemCategoryLoan,
                icon: "arrow.down.left",
                colorHex: "#34C759",
                type: .income
            )
            
            // 4. Loan Repayment (Paying back money) - Expense
            DefaultDataService.ensureSystemCategoryExists(
                modelContext: context,
                name: debtSystemCategoryLoanRepayment,
                icon: "tray.and.arrow.up.fill",
                colorHex: "#007AFF",
                type: .expense
            )
            
            // Maintain compatibility for "Debts & Loans" (Legacy)
            DefaultDataService.ensureCategoryExists(
                modelContext: context,
                name: debtCategoryName,
                icon: "banknote",
                colorHex: "#795548",
                type: .income
            )
            
            DefaultDataService.ensureCategoryExists(
                modelContext: context,
                name: debtCategoryName,
                icon: "banknote",
                colorHex: "#795548",
                type: .expense
            )
            
            // Ensure new categories exist for existing users (safe: won't duplicate)
            DefaultDataService.ensureCategoryExists(
                modelContext: context,
                name: categoryTrip,
                icon: "airplane",
                colorHex: "#FF9800",
                type: .expense
            )
            DefaultDataService.ensureCategoryExists(
                modelContext: context,
                name: categorySaving,
                icon: "banknote.fill",
                colorHex: "#4CAF50",
                type: .expense
            )
            DefaultDataService.ensureCategoryExists(
                modelContext: context,
                name: categoryGiftsAndDonations,
                icon: "gift.fill",
                colorHex: "#E91E63",
                type: .expense
            )
            
            for (name, icon, colorHex, type) in mustHaveCategories {
                DefaultDataService.ensureSystemCategoryExists(
                    modelContext: context,
                    name: name,
                    icon: icon,
                    colorHex: colorHex,
                    type: type
                )
            }
            } // end: seed only when the device is not yet account-owned

            do {
                try context.save()
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
}
