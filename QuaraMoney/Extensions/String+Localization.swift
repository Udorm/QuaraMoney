import Foundation
import Combine
import SwiftUI

/// Manages app language selection and localization
class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    
    /// Available languages
    enum Language: String, CaseIterable, Identifiable {
        case system = "system"
        case english = "en"
        case khmer = "km"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .system: return "System"
            case .english: return "English"
            case .khmer: return "ខ្មែរ (Khmer)"
            }
        }
        
        var locale: Locale {
            switch self {
            case .system: return Locale.current
            case .english: return Locale(identifier: "en")
            case .khmer: return Locale(identifier: "km")
            }
        }
    }
    
    @AppStorage("selectedLanguage") private var selectedLanguageRaw: String = Language.system.rawValue
    
    /// A UUID that changes every time the language changes, used to force view refreshes
    @Published var fontRefreshID = UUID()
    
    var selectedLanguage: Language {
        get { Language(rawValue: selectedLanguageRaw) ?? .system }
        set { 
            guard newValue != selectedLanguage else { return }
            selectedLanguageRaw = newValue.rawValue
            updateBundle()
            // Update font refresh ID to trigger view updates
            fontRefreshID = UUID()
            // Refresh UIKit appearance proxies
            UIFont.setupAppAppearance()
            // Notify observers
            objectWillChange.send()
            // Post notification for any components that need manual refresh
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }
    }
    
    /// The bundle to use for localization
    private(set) var bundle: Bundle = .main
    
    /// Returns true if the current language is Khmer
    var isKhmer: Bool {
        selectedLanguage == .khmer ||
        (selectedLanguage == .system && Locale.preferredLanguages.first?.starts(with: "km") == true)
    }
    
    private init() {
        updateBundle()
    }
    
    private func updateBundle() {
        let languageCode: String
        
        switch selectedLanguage {
        case .system:
            // Use the first preferred language that we support
            let preferredLanguages = Locale.preferredLanguages
            if preferredLanguages.first?.starts(with: "km") == true {
                languageCode = "km"
            } else {
                languageCode = "en"
            }
        case .english:
            languageCode = "en"
        case .khmer:
            languageCode = "km"
        }
        
        if let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            self.bundle = bundle
        } else {
            self.bundle = .main
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the app language changes
    static let languageDidChange = Notification.Name("languageDidChange")
}

// MARK: - Updated String Localization Extension

extension String {
    /// Returns the localized version of the string using LanguageManager's bundle
    var localized: String {
        let bundle = LanguageManager.shared.bundle
        let localized = NSLocalizedString(self, tableName: nil, bundle: bundle, value: self, comment: "")
        return localized
    }
    
    /// Returns the localized version of the string with format arguments
    func localized(with args: CVarArg...) -> String {
        String(format: self.localized, arguments: args)
    }
    
    /// Returns the localized version with a comment for translators
    func localized(comment: String) -> String {
        let bundle = LanguageManager.shared.bundle
        return NSLocalizedString(self, tableName: nil, bundle: bundle, value: self, comment: comment)
    }
}

// MARK: - Localization Keys

/// Centralized localization keys for type-safe access
enum L10n {
    
    // MARK: - Common
    enum Common {
        static var cancel: String { "common.cancel".localized }
        static var save: String { "common.save".localized }
        static var done: String { "common.done".localized }
        static var add: String { "common.add".localized }
        static var edit: String { "common.edit".localized }
        static var delete: String { "common.delete".localized }
        static var ok: String { "common.ok".localized }
        static var back: String { "common.back".localized }
        static var close: String { "common.close".localized }
        static var create: String { "common.create".localized }
        static var preview: String { "common.preview".localized }
        static var seeAll: String { "common.seeAll".localized }
        static var error: String { "common.error".localized }
        static var advancedOptions: String { "common.advancedOptions".localized }
        static var next: String { "common.next".localized }
        static var search: String { "common.search".localized }
        static var select: String { "common.select".localized }
        static var selectAll: String { "common.selectAll".localized }
        static var deselectAll: String { "common.deselectAll".localized }
    }
    
    // MARK: - Tab Bar
    enum Tab {
        static var home: String { "tab.home".localized }
        static var wallets: String { "tab.wallets".localized }
        static var analysis: String { "tab.analysis".localized }
        static var more: String { "tab.more".localized }
    }
    
    // MARK: - Home
    enum Home {
        static var title: String { "home.title".localized }
        static var noTransactions: String { "home.noTransactions".localized }
    }
    
    // MARK: - Wallet
    enum Wallet {
        static var title: String { "wallet.title".localized }
        static var add: String { "wallet.add".localized }
        static var totalBalance: String { "wallet.totalBalance".localized }
        static var netWorth: String { "wallet.netWorth".localized }
        static var selectWallet: String { "wallet.selectWallet".localized }
        static var name: String { "wallet.name".localized }
        static var currency: String { "wallet.currency".localized }
        static var color: String { "wallet.color".localized }
        static var icon: String { "wallet.icon".localized }
        static var emptyState: String { "wallet.emptyState".localized }
        static var customRange: String { "wallet.customRange".localized }
        static var archive: String { "wallet.archive".localized }
        static var unarchive: String { "wallet.unarchive".localized }
        static var archivedWallets: String { "wallet.archivedWallets".localized }
        static func deleteRelatedTransactionsWarning(_ count: Int) -> String { "wallet.deleteRelatedTransactionsWarning".localized(with: count) }
        static var archiveInstead: String { "wallet.archiveInstead".localized }
        static var deleteAnyway: String { "wallet.deleteAnyway".localized }
        static var restore: String { "wallet.restore".localized }
        static var archived: String { "wallet.archived".localized }
        static var noArchivedWallets: String { "wallet.noArchivedWallets".localized }
        static var new: String { "wallet.new".localized }
        static var edit: String { "wallet.edit".localized }
        static var details: String { "wallet.details".localized }
        static var appearance: String { "wallet.appearance".localized }
        
        enum Status {
            static var title: String { "filter.status".localized }
            static var active: String { "status.active".localized }
            static var archived: String { "status.archived".localized }
            static var activeWallets: String { "status.activeWallets".localized }
            static var archivedWallets: String { "status.archivedWallets".localized }
        }
    }
    
    // MARK: - Transaction
    enum Transaction {
        static var add: String { "transaction.add".localized }
        static var amount: String { "transaction.amount".localized }
        static var note: String { "transaction.note".localized }
        static var rate: String { "transaction.rate".localized }
        static var date: String { "transaction.date".localized }
        static var type: String { "transaction.type".localized }
        static var category: String { "transaction.category".localized }
        static var scanReceipt: String { "transaction.scanReceipt".localized }
        
        
        enum TransactionType {
            static var income: String { "transaction.type.income".localized }
            static var expense: String { "transaction.type.expense".localized }
            static var transfer: String { "transaction.type.transfer".localized }
            static var adjustment: String { "transaction.type.adjustment".localized }
        }
    }
    
    // MARK: - Category
    enum Category {
        static var title: String { "category.title".localized }
        static var add: String { "category.add".localized }
        static var select: String { "category.select".localized }
        static var name: String { "category.name".localized }
        static var selectColor: String { "category.selectColor".localized }
        static var selectIcon: String { "category.selectIcon".localized }
        static var noAvailable: String { "category.noAvailable".localized }
        
        // Predefined
        static var foodAndDrink: String { "category.foodAndDrink".localized }
        static var housing: String { "category.housing".localized }
        static var waterBill: String { "category.waterBill".localized }
        static var electricityBill: String { "category.electricityBill".localized }
        static var internetBill: String { "category.internetBill".localized }
        static var subscriptions: String { "category.subscriptions".localized }
        static var transportation: String { "category.transportation".localized }
        static var personalLifestyle: String { "category.personalLifestyle".localized }
        static var health: String { "category.health".localized }
        static var financial: String { "category.financial".localized }
        static var others: String { "category.others".localized }
        static var salary: String { "category.salary".localized }
        static var investments: String { "category.investments".localized }
        
        static var services: String { "category.services".localized }
        static var leisure: String { "category.leisure".localized }
        static var education: String { "category.education".localized }
        static var tech: String { "category.tech".localized }
        static var debtAndLoans: String { "category.debtAndLoans".localized }
    }
    

    
    // MARK: - Budget
    enum Budget {
        static var title: String { "budget.title".localized }
        static var new: String { "budget.new".localized }
        static var edit: String { "budget.edit".localized }
        static var details: String { "budget.details".localized }
        static var insights: String { "budget.insights".localized }
        static var name: String { "budget.name".localized }

        static var notifications: String { "budget.notifications".localized }
        static var rollover: String { "budget.rollover".localized }
        static var dailyAverage: String { "budget.dailyAverage".localized }
        static var dailyBudget: String { "budget.dailyBudget".localized }
        static var projectedTotal: String { "budget.projectedTotal".localized }
        static var emptyState: String { "budget.emptyState".localized }
        static var emptyDescription: String { "budget.emptyDescription".localized }
        static var recurringOnly: String { "budget.recurringOnly".localized }
        static var totalSpent: String { "budget.totalSpent".localized }
        static var totalBudgeted: String { "budget.totalBudgeted".localized }
        static func onTrackCount(_ onTrack: Int, _ over: Int) -> String { "budget.onTrackCount".localized(with: onTrack, over) }
        static func percentUsed(_ percent: Int) -> String { "budget.percentUsed".localized(with: percent) }
        static func overBy(_ amount: String) -> String { "budget.overBy".localized(with: amount) }
        static func leftOf(_ amount: String) -> String { "budget.leftOf".localized(with: amount) }
        static func daysLeft(_ days: Int) -> String { "budget.daysLeft".localized(with: days) }
        static var ended: String { "budget.ended".localized }
        static var nameOptional: String { "budget.nameOptional".localized }
        static var nameHint: String { "budget.nameHint".localized }
        static var whatToBudget: String { "budget.whatToBudget".localized }
        static var allExpenses: String { "budget.allExpenses".localized }
        static var limit: String { "budget.limit".localized }
        static var usePercentage: String { "budget.usePercentage".localized }
        static var ofIncome: String { "budget.ofIncome".localized }
        static var periodType: String { "budget.periodType".localized }
        static var startDate: String { "budget.startDate".localized }
        static var endDate: String { "budget.endDate".localized }
        static var recurring: String { "budget.recurring".localized }
        static var rolloverDescription: String { "budget.rolloverDescription".localized }
        static var resetDescription: String { "budget.resetDescription".localized }
        static var linkSavings: String { "budget.linkSavings".localized }
        static var selectCategories: String { "budget.selectCategories".localized }
        static var category: String { "budget.category".localized }
        static var summary: String { "budget.summary".localized }
        static var original: String { "budget.original".localized }
        static var used: String { "budget.used".localized }
        static var remaining: String { "budget.remaining".localized }
        static var overBudgetLabel: String { "budget.overBudgetLabel".localized }
        static var rolloverTitle: String { "budget.rolloverTitle".localized }
        static var linkedSavings: String { "budget.linkedSavings".localized }
        static var alerts: String { "budget.alerts".localized }
        static var enabled: String { "budget.enabled".localized }

        static var disabled: String { "budget.disabled".localized }
        static var noTransactions: String { "budget.noTransactions".localized }
        static var currentPeriod: String { "budget.currentPeriod".localized }
        static var rolloverAmountLabel: String { "budget.rolloverAmountLabel".localized }
        
        static func transactions(_ count: Int) -> String { "budget.transactions".localized(with: count) }
        static func alertAt(_ percent: Int) -> String { "budget.alertAt".localized(with: percent) }
        
        enum Target {
            static var category: String { "budget.target.category".localized }

            static var specificCategories: String { "budget.target.specificCategories".localized }
            static var total: String { "budget.target.total".localized }
            static var type: String { "budget.target.type".localized }
        }
        
        enum Filter {
            static var active: String { "budget.filter.active".localized }
            static var upcoming: String { "budget.filter.upcoming".localized }
            static var past: String { "budget.filter.past".localized }
            static var all: String { "budget.filter.all".localized }
        }
    }
    
    // MARK: - Period
    enum Period {
        static var daily: String { "period.daily".localized }
        static var weekly: String { "period.weekly".localized }
        static var monthly: String { "period.monthly".localized }
        static var quarterly: String { "period.quarterly".localized }
        static var yearly: String { "period.yearly".localized }
        static var custom: String { "period.custom".localized }
    }
    
    // MARK: - Filter
    enum Filter {
        static var title: String { "filter.title".localized }
        static var thisMonth: String { "filter.thisMonth".localized }
        static var lastMonth: String { "filter.lastMonth".localized }
        static var thisYear: String { "filter.thisYear".localized }
        static var day: String { "filter.day".localized }
        static var week: String { "filter.week".localized }
        static var month: String { "filter.month".localized }
        static var sixMonths: String { "filter.sixMonths".localized }
        static var year: String { "filter.year".localized }
        static var lastYear: String { "filter.lastYear".localized }
    }
    
    // MARK: - Analysis
    enum Analysis {
        static var title: String { "analysis.title".localized }
        static var net: String { "analysis.net".localized }
    }
    
    // MARK: - Event
    enum Event {
        static var title: String { "event.title".localized }
        static var new: String { "event.new".localized }
        static var add: String { "event.add".localized }
        static var name: String { "event.name".localized }
        static var budget: String { "event.budget".localized }
        static var budgetOptional: String { "event.budgetOptional".localized }
        static var notes: String { "event.notes".localized }
        static var select: String { "event.select".localized }
        static var emptyState: String { "event.emptyState".localized }
        static var details: String { "event.details".localized }
        static var budgetNotes: String { "event.budgetNotes".localized }
        static var noEvent: String { "event.noEvent".localized }
        
        static func overBudget(_ amount: String) -> String {
            "event.overBudget".localized(with: amount)
        }

        static func remaining(_ amount: String) -> String {
            "event.remaining".localized(with: amount)
        }
        static func spent(_ percent: Int) -> String {
            "event.spent".localized(with: percent)
        }
    }
    


    // MARK: - Savings
    enum Savings {
        static var title: String { "savings.title".localized }
        static var selectGoal: String { "savings.selectGoal".localized }
        static var new: String { "savings.new".localized }
        static var edit: String { "savings.edit".localized }
        static var goalName: String { "savings.goalName".localized }
        static var targetAmount: String { "savings.targetAmount".localized }
        static var totalSaved: String { "savings.totalSaved".localized }
        static var totalTarget: String { "savings.totalTarget".localized }
        static var addContribution: String { "savings.addContribution".localized }
        static var targetDate: String { "savings.targetDate".localized }
        static var daysRemaining: String { "savings.daysRemaining".localized }
        static var remaining: String { "savings.remaining".localized }
        static var monthlyNeeded: String { "savings.monthlyNeeded".localized }
        static var status: String { "savings.status".localized }
        static var suggestedMonthly: String { "savings.suggestedMonthly".localized }
        static var timeline: String { "savings.timeline".localized }
        static var timelineDescription: String { "savings.timelineDescription".localized }
        static var markActive: String { "savings.markActive".localized }
        static var emptyState: String { "savings.emptyState".localized }
        
        static var activeGoals: String { "savings.activeGoals".localized }
        static var completedGoals: String { "savings.completedGoals".localized }
        static var noGoals: String { "savings.noGoals".localized }
        static var noGoalsDescription: String { "savings.noGoalsDescription".localized }
        static var quickStart: String { "savings.quickStart".localized }
        static var wallet: String { "savings.wallet".localized }
        static var walletDescription: String { "savings.walletDescription".localized }
        static var automation: String { "savings.automation".localized }
        static var autoContribute: String { "savings.autoContribute".localized }
        static var autoContributeDescription: String { "savings.autoContributeDescription".localized }
        static var enterContributionAmount: String { "savings.enterContributionAmount".localized }
        
        static var progress: String { "savings.progress".localized }
        static var complete: String { "savings.complete".localized }
        
        enum Status {
            static var reached: String { "savings.status.reached".localized }
            static var pastDate: String { "savings.status.pastDate".localized }
            static var today: String { "savings.status.today".localized }
            static var noDate: String { "savings.status.noDate".localized }
            static func daysLeft(_ count: Int) -> String { "savings.status.daysLeft".localized(with: count) }
            static func weeksLeft(_ count: Int) -> String { "savings.status.weeksLeft".localized(with: count) }
            static func monthsLeft(_ count: Int) -> String { "savings.status.monthsLeft".localized(with: count) }
        }
        
        enum Template {
            enum EmergencyFund {
                static var title: String { "savings.template.emergencyFund.title".localized }
                static var desc: String { "savings.template.emergencyFund.desc".localized }
            }
            enum Vacation {
                static var title: String { "savings.template.vacation.title".localized }
                static var desc: String { "savings.template.vacation.desc".localized }
            }
            enum CarPurchase {
                static var title: String { "savings.template.carPurchase.title".localized }
                static var desc: String { "savings.template.carPurchase.desc".localized }
            }
            enum HomePurchase {
                static var title: String { "savings.template.homePurchase.title".localized }
                static var desc: String { "savings.template.homePurchase.desc".localized }
            }
            enum Retirement {
                static var title: String { "savings.template.retirement.title".localized }
                static var desc: String { "savings.template.retirement.desc".localized }
            }
            enum Education {
                static var title: String { "savings.template.education.title".localized }
                static var desc: String { "savings.template.education.desc".localized }
            }
            enum Wedding {
                static var title: String { "savings.template.wedding.title".localized }
                static var desc: String { "savings.template.wedding.desc".localized }
            }
            enum DebtPayoff {
                static var title: String { "savings.template.debtPayoff.title".localized }
                static var desc: String { "savings.template.debtPayoff.desc".localized }
            }
            enum Electronics {
                static var title: String { "savings.template.electronics.title".localized }
                static var desc: String { "savings.template.electronics.desc".localized }
            }
            enum Custom {
                static var title: String { "savings.template.custom.title".localized }
                static var desc: String { "savings.template.custom.desc".localized }
            }
        }
    }
    
    // MARK: - Recurring
    enum Recurring {
        static var title: String { "recurring.title".localized }
        static var new: String { "recurring.new".localized }
        static var add: String { "recurring.add".localized }
        static var name: String { "recurring.name".localized }
        static var emptyState: String { "recurring.emptyState".localized }
        static var createWalletFirst: String { "recurring.createWalletFirst".localized }
        
        static func next(_ date: String) -> String {
            "recurring.next".localized(with: date)
        }
        
        static var frequency: String { "recurring.frequency".localized }
        static var assignments: String { "recurring.assignments".localized }
        static var preview: String { "recurring.preview".localized }
        static var emptyTitle: String { "recurring.emptyTitle".localized }
    }
    
    // MARK: - Frequency
    enum Frequency {
        static var daily: String { "frequency.daily".localized }
        static var weekly: String { "frequency.weekly".localized }
        static var monthly: String { "frequency.monthly".localized }
        static var yearly: String { "frequency.yearly".localized }
    }
    
    // MARK: - Settings
    enum Settings {
        static var title: String { "settings.title".localized }
        static var general: String { "settings.general".localized }
        static var defaultCurrency: String { "settings.defaultCurrency".localized }
        static var themeColors: String { "settings.themeColors".localized }
        static var importCSV: String { "settings.importCSV".localized }
        static var exchangeRates: String { "settings.exchangeRates".localized }
        static var refreshRates: String { "settings.refreshRates".localized }
        static var dataManagement: String { "settings.dataManagement".localized }
        static var deleteAllTransactions: String { "settings.deleteAllTransactions".localized }

        static var populateSampleData: String { "settings.populateSampleData".localized }
        static var resetOnboarding: String { "settings.resetOnboarding".localized }
        static var version: String { "settings.version".localized }
        static var language: String { "settings.language".localized }
        static var useSidebarOniPad: String { "settings.useSidebarOniPad".localized }
    }
    
    // MARK: - Onboarding
    enum Onboarding {
        static var getStarted: String { "onboarding.getStarted".localized }
        static var welcomeTitle: String { "onboarding.welcomeTitle".localized }
        static var welcomeDescription: String { "onboarding.welcomeDescription".localized }
        static var selectCurrency: String { "onboarding.selectCurrency".localized }
        static var currencyDescription: String { "onboarding.currencyDescription".localized }
        static var personalizeColors: String { "onboarding.personalizeColors".localized }
        static var themeDescription: String { "onboarding.themeDescription".localized }
        static var incomeColor: String { "onboarding.incomeColor".localized }
        static var expenseColor: String { "onboarding.expenseColor".localized }
        static var finalTitle: String { "onboarding.finalTitle".localized }
        static var finalDescription: String { "onboarding.finalDescription".localized }
        
        // Legacy/Merged keys
        static var welcome: String { "onboarding.welcome".localized }
        static var tagline: String { "onboarding.tagline".localized }
        static var colorDescription: String { "onboarding.colorDescription".localized }
        static var allSet: String { "onboarding.allSet".localized }
    }
    
    // MARK: - Notifications
    enum Notifications {
        static var title: String { "notifications.title".localized }
        static var emptyTitle: String { "notifications.emptyTitle".localized }
        static var emptyDescription: String { "notifications.emptyDescription".localized }
        static var read: String { "notifications.read".localized }
        static var markAllRead: String { "notifications.markAllRead".localized }
        static var clearAll: String { "notifications.clearAll".localized }
        static var dailySummaryTitle: String { "notifications.dailySummaryTitle".localized }
        static var dailySummaryBody: String { "notifications.dailySummaryBody".localized }
        static var viewBudget: String { "notifications.viewBudget".localized }
        static var viewAnalysis: String { "notifications.viewAnalysis".localized }
        static var dismiss: String { "notifications.dismiss".localized }
    }
    
    // MARK: - Alerts
    enum Alert {
        enum PopulateData {
            static var title: String { "alert.populateData.title".localized }
            static var message: String { "alert.populateData.message".localized }
            static var confirm: String { "alert.populateData.confirm".localized }
        }
        
        enum Budget {
            static func info50(_ name: String) -> String { "alert.budget.info50".localized(with: name) }
            static func warning80(_ name: String) -> String { "alert.budget.warning80".localized(with: name) }
            static func exceeded(_ name: String) -> String { "alert.budget.exceeded".localized(with: name) }
            static func projectedOverspend(_ name: String) -> String { "alert.budget.projectedOverspend".localized(with: name) }
        }
        
        enum DeleteTransactions {
            static var title: String { "alert.deleteTransactions.title".localized }
            static var message: String { "alert.deleteTransactions.message".localized }
        }
    }
    
    // MARK: - Theme
    enum Theme {
        static var title: String { "theme.title".localized }
        static var incomeColor: String { "theme.incomeColor".localized }
        static var expenseColor: String { "theme.expenseColor".localized }
        static var resetDefaults: String { "theme.resetDefaults".localized }
    }
    
    // MARK: - CSV
    enum CSV {
        static var title: String { "csv.title".localized }
        static var selectFile: String { "csv.selectFile".localized }
        static var selectCategory: String { "csv.selectCategory".localized }
    }
    
    // MARK: - More
    enum More {
        static var title: String { "more.title".localized }
        static var planningTools: String { "more.planningTools".localized }
        static var features: String { "more.features".localized }
        static var management: String { "more.management".localized }
        static var app: String { "more.app".localized }
        static var budgetWizard: String { "more.budgetWizard".localized }
        
        static var categories: String { "category.title".localized }
        static var recurringRules: String { "recurring.title".localized }
    }
    
    // MARK: - Debt
    enum Debt {
        static var title: String { "debt.title".localized }
        static var owedToMe: String { "debt.owedToMe".localized }
        static var iOwe: String { "debt.iOwe".localized }
        static var add: String { "debt.add".localized }
        static var recordPayment: String { "debt.recordPayment".localized }
        static var markCompleted: String { "debt.markCompleted".localized }
        static var remaining: String { "debt.remaining".localized }
        static var paid: String { "debt.paid".localized }
        static var total: String { "debt.total".localized }
        static var personName: String { "debt.personName".localized }
        static var dueDate: String { "debt.dueDate".localized }
        static var history: String { "debt.history".localized }
        static var recordInitialTransaction: String { "debt.recordInitialTransaction".localized }
        static var initialTransactionHelp: String { "debt.initialTransactionHelp".localized }
        static var partialPayments: String { "debt.partialPayments".localized }
        
        enum SystemCategory {
            static var debt: String { "debt.systemCategory.debt".localized }
            static var debtCollection: String { "debt.systemCategory.debtCollection".localized }
            static var loan: String { "debt.systemCategory.loan".localized }
            static var loanRepayment: String { "debt.systemCategory.loanRepayment".localized }
        }
    }
    

    

    
    // MARK: - Status
    enum Status {
        static var deleting: String { "status.deleting".localized }
        static var populating: String { "status.populating".localized }
        static var populatingData: String { "status.populatingData".localized }
    }
    
    // MARK: - Amount Type
    enum AmountType {
        static var fixed: String { "amountType.fixed".localized }
        static var percentage: String { "amountType.percentage".localized }
    }
    
    // MARK: - Notification Type  
    enum NotificationType {
        static var threshold: String { "notificationType.threshold".localized }
        static var exceeded: String { "notificationType.exceeded".localized }
        static var daily: String { "notificationType.daily".localized }
    }

    // MARK: - Wizard
    enum Wizard {
        static func step(_ current: Int, _ total: Int) -> String { "wizard.step".localized(with: current, total) }
        static var back: String { "wizard.back".localized }
        static var continueAction: String { "wizard.continue".localized }
        static var createBudgets: String { "wizard.createBudgets".localized }
        
        static var incomePrompt: String { "wizard.income.prompt".localized }
        static func basedOn(_ template: String) -> String { "wizard.basedOn".localized(with: template) }
        static var assignPrompt: String { "wizard.assign.prompt".localized }
        static func selectedCount(_ count: Int) -> String { "wizard.selected".localized(with: count) }
        static var totalAllocation: String { "wizard.totalAllocation".localized }
        static var budgetsToCreate: String { "wizard.budgetsToCreate".localized }
        
        enum Start {
            static var title: String { "wizard.welcome.title".localized }
            static var subtitle: String { "wizard.welcome.subtitle".localized }
            static var limitsTitle: String { "wizard.feature.limits.title".localized }
            static var limitsDesc: String { "wizard.feature.limits.desc".localized }
            static var alertsTitle: String { "wizard.feature.alerts.title".localized }
            static var alertsDesc: String { "wizard.feature.alerts.desc".localized }
            static var trackTitle: String { "wizard.feature.track.title".localized }
            static var trackDesc: String { "wizard.feature.track.desc".localized }
            static var autoRenewTitle: String { "wizard.feature.autoRenew.title".localized }
            static var autoRenewDesc: String { "wizard.feature.autoRenew.desc".localized }
        }
        
        enum SelectTemplate {
            static var title: String { "wizard.selectTemplate.title".localized }
            static var subtitle: String { "wizard.selectTemplate.subtitle".localized }
        }
        enum EnterIncome {
            static var title: String { "wizard.enterIncome.title".localized }
            static var subtitle: String { "wizard.enterIncome.subtitle".localized }
        }
        enum AssignCategories {
            static var title: String { "wizard.assignCategories.title".localized }
            static var subtitle: String { "wizard.assignCategories.subtitle".localized }
        }
        enum Customize {
            static var title: String { "wizard.customize.title".localized }
            static var subtitle: String { "wizard.customize.subtitle".localized }
        }
        enum Review {
            static var title: String { "wizard.review.title".localized }
            static var subtitle: String { "wizard.review.subtitle".localized }
            static var point1: String { "wizard.review.point1".localized }
            static var point2: String { "wizard.review.point2".localized }
            static var point3: String { "wizard.review.point3".localized }
        }
        enum Complete {
            static var title: String { "wizard.done.title".localized }
            static var subtitle: String { "wizard.done.subtitle".localized }
            static var allSetTitle: String { "wizard.allSet.title".localized }
            static var allSetMessage: String { "wizard.allSet.message".localized }
            static var point1: String { "wizard.allSet.point1".localized }
            static var point2: String { "wizard.allSet.point2".localized }
            static var point3: String { "wizard.allSet.point3".localized }
        }
    }
    
    // MARK: - Budget Template
    enum BudgetTemplate {
        enum Conservative {
            static var title: String { "template.conservative.title".localized }
            static var desc: String { "template.conservative.desc".localized }
        }
        enum Balanced {
            static var title: String { "template.balanced.title".localized }
            static var desc: String { "template.balanced.desc".localized }
        }
        enum FiftyThirtyTwenty {
            static var title: String { "template.503020.title".localized }
            static var desc: String { "template.503020.desc".localized }
        }
        enum ZeroBased {
            static var title: String { "template.zeroBased.title".localized }
            static var desc: String { "template.zeroBased.desc".localized }
        }
    }
    
    // MARK: - Budget Category Type
    enum BudgetCategoryType {
        enum Needs {
            static var title: String { "budget.type.needs.title".localized }
            static var desc: String { "budget.type.needs.desc".localized }
        }
        enum Wants {
            static var title: String { "budget.type.wants.title".localized }
            static var desc: String { "budget.type.wants.desc".localized }
        }
        enum Savings {
            static var title: String { "budget.type.savings.title".localized }
            static var desc: String { "budget.type.savings.desc".localized }
        }
    }
    
    // MARK: - Event Additions
    enum EventSettlement {
        static var summary: String { "event.settlement.summary".localized }
        static var mode: String { "event.settlement.mode".localized }
        static var fromWallet: String { "event.settlement.fromWallet".localized }
        static var memberTransfers: String { "event.settlement.memberTransfers".localized }
        static var balances: String { "event.settlement.balances".localized }
        static var exportToWallet: String { "event.settlement.exportToWallet".localized }
        static var totalCost: String { "event.settlement.totalCost".localized }
        static var totalContribution: String { "event.settlement.totalContribution".localized }
        static var remainingPool: String { "event.settlement.remainingPool".localized }
        static var walletPays: String { "event.settlement.walletPays".localized }
        static var wallet: String { "event.settlement.wallet".localized }
        static var settleEvent: String { "event.settlement.settleEvent".localized }
        static var saving: String { "event.settlement.saving".localized }
        static var confirm: String { "event.settlement.confirm".localized }
    }
    
    enum EventTransaction {
        static var paymentAndSplitting: String { "event.transaction.paymentAndSplitting".localized }
        static var contributor: String { "event.transaction.contributor".localized }
        static var selectPayer: String { "event.transaction.selectPayer".localized }
        static var selectParticipants: String { "event.transaction.selectParticipants".localized }
        static var noMembers: String { "event.transaction.noMembers".localized }
        static var noCategories: String { "event.transaction.noCategories".localized }
        static var tabExpense: String { "event.transaction.tabExpense".localized }
        static var tabContribution: String { "event.transaction.tabContribution".localized }
    }
    
    enum EventDetail {
        static var members: String { "event.detail.members".localized }
        static var showAll: String { "event.detail.showAll".localized }
        static var yourSpending: String { "event.detail.yourSpending".localized }
        static var exporting: String { "event.detail.exporting".localized }
        static var export: String { "event.detail.export".localized }
        static var unknownError: String { "event.detail.unknownError".localized }
    }
    
    enum EventMember {
        static var details: String { "event.member.details".localized }
        static var color: String { "event.member.color".localized }
        static var changeIcon: String { "event.member.changeIcon".localized }
        static var removeImage: String { "event.member.removeImage".localized }
        static var addMember: String { "event.member.addMember".localized }
        static var editMember: String { "event.member.editMember".localized }
    }
    
    enum EventAdditional {
        static var appearance: String { "event.appearance".localized }
        static var dateTime: String { "event.dateTime".localized }
        static var listOngoing: String { "event.list.ongoing".localized }
        static var listUpcoming: String { "event.list.upcoming".localized }
        static var listPast: String { "event.list.past".localized }
        static var summaryAddExpense: String { "event.summary.addExpense".localized }
        static var summarySettle: String { "event.summary.settle".localized }
        static var locationSelected: String { "event.location.selected".localized }
        static var locationConfirm: String { "event.location.confirm".localized }
        static var locationPick: String { "event.location.pick".localized }
        static var memberListSearch: String { "event.memberList.search".localized }
        static var memberListYou: String { "event.memberList.you".localized }
    }
    
    enum DebtAdditional {
        static var details: String { "debt.details".localized }
        static var initialTransaction: String { "debt.initialTransaction".localized }
        static var noneTrackOnly: String { "debt.noneTrackOnly".localized }
        static var initialTransactionHelpText: String { "debt.initialTransactionHelpText".localized }
        static var amountFixedWarning: String { "debt.amountFixedWarning".localized }
        static var filterAll: String { "debt.filterAll".localized }
        static var filterActive: String { "debt.filterActive".localized }
        static var filterCompleted: String { "debt.filterCompleted".localized }
        static var noDebts: String { "debt.noDebts".localized }
        static var noDebtsDescription: String { "debt.noDebtsDescription".localized }
        static var noTransactions: String { "debt.noTransactions".localized }
        static var none: String { "debt.none".localized }
    }
    
    enum TransactionAdditional {
        static var balanceAdjustment: String { "transaction.balanceAdjustment".localized }
        static var time: String { "transaction.time".localized }
        static var selectCategory: String { "transaction.selectCategory".localized }
        static var searchCategories: String { "transaction.searchCategories".localized }
        static var linkedToDebt: String { "transaction.linkedToDebt".localized }
        static var linkedToLoan: String { "transaction.linkedToLoan".localized }
    }
    
    enum BudgetAnalysis {
        static var performance: String { "budget.performance".localized }
        static var successRate: String { "budget.successRate".localized }
        static var monthlyUtilization: String { "budget.monthlyUtilization".localized }
        static var budgeted: String { "budget.budgeted".localized }
        static var underBudget: String { "budget.underBudget".localized }
        static var overBudget: String { "budget.overBudget".localized }
        static var attentionCategories: String { "budget.attentionCategories".localized }
        static var activeBudgetsStatus: String { "budget.activeBudgetsStatus".localized }
        static var tips: String { "budget.tips".localized }
        static var budgetsMet: String { "budget.budgetsMet".localized }
        static var activeBudgets: String { "budget.activeBudgets".localized }
        static var tipIncrease: String { "budget.tip.increase".localized }
        static var tipIncreaseDesc: String { "budget.tip.increaseDesc".localized }
        static func tipReview(_ name: String) -> String { "budget.tip.review".localized(with: name) }
        static func tipReviewDesc(_ amount: String) -> String { "budget.tip.reviewDesc".localized(with: amount) }
        static var tipGreatJob: String { "budget.tip.greatJob".localized }
        static var tipGreatJobDesc: String { "budget.tip.greatJobDesc".localized }
        static var tipCheckWeekly: String { "budget.tip.checkWeekly".localized }
        static var tipCheckWeeklyDesc: String { "budget.tip.checkWeeklyDesc".localized }
        static var thresholdNone: String { "budget.threshold.none".localized }
    }
    
    enum CSVAdditional {
        static var importing: String { "csv.importing".localized }
        static var pleaseWait: String { "csv.pleaseWait".localized }
        static var importComplete: String { "csv.importComplete".localized }
        static func importedCount(_ count: Int) -> String { "csv.importedCount".localized(with: count) }
        static func skippedCount(_ count: Int) -> String { "csv.skippedCount".localized(with: count) }
        static var processing: String { "csv.processing".localized }
        static var valid: String { "csv.valid".localized }
        static var skipped: String { "csv.skipped".localized }
        static var preview: String { "csv.preview".localized }
        static var adjustMapping: String { "csv.adjustMapping".localized }
        static var noCategory: String { "csv.noCategory".localized }
        static var defaultWallet: String { "csv.defaultWallet".localized }
        static var selectWallet: String { "csv.selectWallet".localized }
        static func importAll(_ count: Int) -> String { "csv.importAll".localized(with: count) }
        static func rowError(_ count: Int) -> String { "csv.rowError".localized(with: count) }
        static var notMapped: String { "csv.notMapped".localized }
    }
    
    enum Export {
        static var dataSelection: String { "export.dataSelection".localized }
        static var wallets: String { "export.wallets".localized }
        static var allWallets: String { "export.allWallets".localized }
        static func selectedCount(_ count: Int) -> String { "export.selectedCount".localized(with: count) }
        static var generating: String { "export.generating".localized }
        static var exportToCSV: String { "export.exportToCSV".localized }
        static var exportData: String { "export.exportData".localized }
        static var selectWallets: String { "export.selectWallets".localized }
    }
    
    enum CategoryAdditional {
        static var details: String { "category.details".localized }
        static var appearance: String { "category.appearance".localized }
        static var expense: String { "category.expense".localized }
        static var income: String { "category.income".localized }
        static var preview: String { "category.preview".localized }
        static var color: String { "category.color".localized }
        static var icon: String { "category.icon".localized }
        static var editCategory: String { "category.editCategory".localized }
        static var newCategory: String { "category.newCategory".localized }
    }

    enum AnalysisAdditional {
        static var periodW: String { "analysis.period.w".localized }
        static var periodM: String { "analysis.period.m".localized }
        static var period6M: String { "analysis.period.6m".localized }
        static var periodY: String { "analysis.period.y".localized }
        static var periodLY: String { "analysis.period.ly".localized }
        static var timePeriod: String { "analysis.timePeriod".localized }
        static var total: String { "analysis.total".localized }
    }
}
