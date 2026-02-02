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
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Wallet.self,
            Category.self,
            Event.self,
            RecurringRule.self,
            Transaction.self,
            Budget.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            if isOnboardingCompleted {
                ContentView()
                    .onAppear {
                        let context = sharedModelContainer.mainContext
                        let service = RecurringRuleService(modelContext: context)
                        service.checkAndGenerateTransactions()
                    }
            } else {
                OnboardingView()
            }
        }
        .modelContainer(sharedModelContainer)
    }

    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false
}
