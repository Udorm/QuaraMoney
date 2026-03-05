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
    
    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            Wallet.self,
            Category.self,
            Event.self,
            EventMember.self,
            EventLedgerTransaction.self,
            EventLedgerParticipant.self,
            EventSettlementSnapshot.self,
            EventSettlementTransfer.self,
            EventWalletExportRecord.self,
            RecurringRule.self,
            Transaction.self,
            Budget.self,
            Debt.self,
            SavingsGoal.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    
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
            .environment(\.font, defaultAppFont)
            // Force view recreation when language changes
            .id(languageManager.fontRefreshID)
            .environmentObject(languageManager)
            .preferredColorScheme(selectedTheme.colorScheme)
            .task {
                // Deferred from init() — runs after first frame renders
                UIFont.setupAppAppearance()
                // Pre-warm common font sizes on background thread for smoother scrolling
                UIFont.prewarmFontCache()
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
            
            // Check recurring transactions
            await RecurringRuleService.checkAndGenerateTransactions(modelContext: context)
            
            // Check budget rollovers
            BudgetRolloverService.checkAndProcessBudgetRollovers(
                modelContext: context,
                rates: rates,
                preferredCurrency: preferredCurrency
            )
            
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
            
            try? context.save()
        }
        // Defer notification setup to avoid blocking the main thread at launch
        Task { @MainActor in
            // Let the UI settle before loading notifications
            try? await Task.sleep(for: .seconds(2))
            let mainContext = sharedModelContainer.mainContext
            BudgetNotificationService.shared.configure(modelContext: mainContext)
            BudgetNotificationService.shared.loadNotifications()
            BudgetNotificationService.shared.setupNotificationCategories()
        }
    }
}
