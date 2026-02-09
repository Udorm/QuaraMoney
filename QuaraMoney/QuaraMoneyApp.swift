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
            .onAppear {
                // Setup UIKit appearances after window appears to ensure font is loaded
                UIFont.setupAppAppearance()
            }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func setupServices() {
        let context = sharedModelContainer.mainContext
        
        // Check recurring transactions
        let recurringService = RecurringRuleService(modelContext: context)
        recurringService.checkAndGenerateTransactions()
        
        // Check budget rollovers
        let rolloverService = BudgetRolloverService(modelContext: context)
        rolloverService.checkAndProcessBudgetRollovers()
        
        // Setup notification service
        BudgetNotificationService.shared.configure(modelContext: context)
        BudgetNotificationService.shared.loadNotifications()

        BudgetNotificationService.shared.setupNotificationCategories()
        
        // Seed default categories if needed
        DefaultDataService.seedDefaultCategories(modelContext: context)
    }
}
