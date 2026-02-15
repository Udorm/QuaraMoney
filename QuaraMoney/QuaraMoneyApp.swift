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
    @StateObject private var languageManager = LanguageManager.shared
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false
    
    // Initialize appearance BEFORE any views are created
    init() {
        // Setup UIKit appearances (must happen before views are created)
        UIFont.setupAppAppearance()
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Wallet.self,
            Category.self,
            Event.self,
            RecurringRule.self,
            Transaction.self,
            Budget.self,

        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    /// The default cascaded font for the entire app
    private var defaultAppFont: Font {
        Font(UIFont.appWithCascade(ofSize: 17, weight: .regular))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isOnboardingCompleted {
                    ContentView()
                        .onAppear {
                            setupServices()
                        }
                } else {
                    OnboardingView()
                }
            }
    // Apply cascaded font globally - this makes ALL text use the font with Khmer fallback
            .environment(\.font, defaultAppFont)
            // Force view recreation when language changes
            .id(languageManager.fontRefreshID)
            .environmentObject(languageManager)
            .preferredColorScheme(selectedTheme.colorScheme)
            .onAppear {
                // Setup UIKit appearances after window appears to ensure font is loaded
                UIFont.setupAppAppearance()
            }
        }
        .modelContainer(sharedModelContainer)
    }
    
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var securityManager = SecurityManager.shared
    
    private var bodyContent: some View {
        Group {
            if securityManager.isAppLocked {
                ZStack {
                    ContentView()
                        .blur(radius: 10)
                        .disabled(true)
                    
                    Color.black.ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.white)
                        
                        Text("QuaraMoney Locked")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        
                        Button {
                            securityManager.authenticate()
                        } label: {
                            Label("Unlock", systemImage: "faceid")
                                .font(.headline)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                }
            } else {
                Group {
                    if isOnboardingCompleted {
                        ContentView()
                            .onAppear {
                                setupServices()
                            }
                    } else {
                        OnboardingView()
                    }
                }
                // Apply cascaded font globally
                .environment(\.font, defaultAppFont)
                .id(languageManager.fontRefreshID)
                .environmentObject(languageManager)
                .preferredColorScheme(selectedTheme.colorScheme)
            }
        }
        .onAppear {
             UIFont.setupAppAppearance()
             // Initial check if locked
             if securityManager.isAppLockEnabled {
                 securityManager.lockApp()
                 securityManager.authenticate()
             }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                // Lock instantly when backgrounded
                securityManager.lockApp()
            } else if newPhase == .active {
                // Try to unlock if locked and enabled
                if securityManager.isAppLocked {
                    securityManager.authenticate()
                }
            }
        }
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
            
            // Bills
            DefaultCategoryData(name: L10n.Category.electricityBill, icon: "bolt", colorHex: "#FFEB3B", type: .expense),
            DefaultCategoryData(name: L10n.Category.waterBill, icon: "drop", colorHex: "#2196F3", type: .expense),
            DefaultCategoryData(name: L10n.Category.internetBill, icon: "wifi", colorHex: "#00BCD4", type: .expense)
        ]
        
        // Perform heavy database operations in background
        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            
            // Check recurring transactions
            RecurringRuleService.checkAndGenerateTransactions(modelContext: context)
            
            // Check budget rollovers
            BudgetRolloverService.checkAndProcessBudgetRollovers(
                modelContext: context,
                rates: rates,
                preferredCurrency: preferredCurrency
            )
            
            // Seed default categories if needed
            DefaultDataService.seedDefaultCategories(modelContext: context, data: defaultCategories)
        }
        
        // Setup notification service on main thread as it deals with UI/State
        let mainContext = sharedModelContainer.mainContext
        BudgetNotificationService.shared.configure(modelContext: mainContext)
        BudgetNotificationService.shared.loadNotifications()

        BudgetNotificationService.shared.setupNotificationCategories()
    }
}
