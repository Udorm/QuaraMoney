import Foundation
import UserNotifications
import SwiftData
import Combine

/// Service for managing budget alerts - both local push notifications and in-app notifications
@MainActor
class BudgetNotificationService: ObservableObject {
    static let shared = BudgetNotificationService()
    
    @Published var inAppNotifications: [BudgetNotification] = []
    @Published var unreadCount: Int = 0
    
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // MARK: - Configuration
    
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        cancellables.removeAll()
        NotificationCenter.default.publisher(for: .dataDidUpdate)
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluateStore() }
            .store(in: &cancellables)
    }

    func evaluateStore() {
        guard let modelContext else { return }
        do {
            let budgets = try modelContext.fetch(FetchDescriptor<Budget>()).filter { $0.deletedAt == nil }
            let transactions = try modelContext.fetch(FetchDescriptor<Transaction>()).filter { $0.deletedAt == nil }
            let spending = BudgetCalculator.spendingByBudgetCurrency(for: budgets, transactions: transactions)
            checkBudgetsAndTriggerAlerts(budgets: budgets, spending: spending)
            if modelContext.hasChanges {
                try SyncMutationTracker.withSaveSource("BudgetNotificationService.evaluateStore") {
                    try modelContext.save()
                }
            }
        } catch {
            ErrorService.shared.handlePersistenceError(error, context: "BudgetNotificationService.evaluateStore")
        }
    }
    
    // MARK: - Permission Request
    
    func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            #if DEBUG
            print("Notification permission error: \(error)")
            #endif
            return false
        }
    }
    
    func checkNotificationPermission() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }
    
    // MARK: - Budget Checking
    
    /// Check all budgets and trigger alerts if needed
    func checkBudgetsAndTriggerAlerts(budgets: [Budget], spending: [UUID: Decimal]) {
        for budget in budgets where budget.isActive {
            let spent = spending[budget.id] ?? 0
            let limit = budget.effectiveLimit
            
            guard limit > 0 else { continue }
            
            let progress = Double(truncating: spent as NSNumber) / Double(truncating: limit as NSNumber)
            
            let periodKey = budget.periodKey()
            if budget.lastAlertPeriodKey != periodKey, budget.lastAlertThreshold != 0 {
                budget.lastAlertThreshold = 0
            }
            let progressPercent = Int(progress * 100)
            let threshold = budget.alertMode.thresholds.sorted(by: >).first {
                progressPercent >= $0 && budget.lastAlertThreshold < $0
            }
            if let threshold {
                let alertType: BudgetAlertType = threshold == 100 ? .exceeded : .warning80
                triggerAlert(for: budget, type: alertType, progress: progress, periodKey: periodKey)
            }
            
        }
    }
    
    // MARK: - Alert Triggering
    
    /// Trigger both local and in-app notification
    private func triggerAlert(for budget: Budget, type: BudgetAlertType, progress: Double, periodKey: String? = nil) {
        let notification = BudgetNotification(
            budgetId: budget.id,
            budgetName: budget.displayName,
            alertType: type,
            progress: progress,
            timestamp: Date(),
            periodKey: periodKey ?? budget.periodKey()
        )
        
        // Add to in-app notifications
        addInAppNotification(notification)
        
        // Schedule local notification
        Task {
            guard await scheduleLocalNotification(notification) else { return }
            if budget.lastAlertThreshold != type.threshold {
                budget.recordAlertTriggered(threshold: type.threshold)
            }
            if budget.lastAlertPeriodKey != notification.periodKey {
                budget.lastAlertPeriodKey = notification.periodKey
            }
            budget.updatedAt = Date()
            budget.needsSync = true
            do {
                try SyncMutationTracker.withSaveSource("BudgetNotificationService.persistAlertDedupe") {
                    try modelContext?.save()
                }
            }
            catch { ErrorService.shared.handlePersistenceError(error, context: "BudgetNotificationService.persistAlertDedupe") }
        }
    }
    
    // MARK: - In-App Notifications
    
    private func addInAppNotification(_ notification: BudgetNotification) {
        inAppNotifications.insert(notification, at: 0)
        
        // Keep only last 50 notifications
        if inAppNotifications.count > 50 {
            inAppNotifications = Array(inAppNotifications.prefix(50))
        }
        
        updateUnreadCount()
        
        // Save to UserDefaults for persistence
        saveNotifications()
    }
    
    func markAsRead(_ notification: BudgetNotification) {
        if let index = inAppNotifications.firstIndex(where: { $0.id == notification.id }) {
            inAppNotifications[index].isRead = true
            updateUnreadCount()
            saveNotifications()
        }
    }
    
    func markAllAsRead() {
        for index in inAppNotifications.indices {
            inAppNotifications[index].isRead = true
        }
        updateUnreadCount()
        saveNotifications()
    }
    
    func clearNotification(_ notification: BudgetNotification) {
        inAppNotifications.removeAll { $0.id == notification.id }
        updateUnreadCount()
        saveNotifications()
    }
    
    func clearAllNotifications() {
        inAppNotifications.removeAll()
        unreadCount = 0
        saveNotifications()
    }
    
    private func updateUnreadCount() {
        unreadCount = inAppNotifications.filter { !$0.isRead }.count
    }
    
    // MARK: - Local Notifications
    
    private func scheduleLocalNotification(_ notification: BudgetNotification) async -> Bool {
        let center = UNUserNotificationCenter.current()
        
        let content = UNMutableNotificationContent()
        content.title = notification.alertType.rawValue
        content.body = notification.alertType.message(budgetName: notification.budgetName)
        content.sound = .default
        content.badge = NSNumber(value: unreadCount + 1)
        
        // Add category for actions
        content.categoryIdentifier = "BUDGET_ALERT"
        
        // User info for deep linking
        content.userInfo = [
            "budgetId": notification.budgetId.uuidString,
            "alertType": notification.alertType.rawValue
        ]
        
        // Create request with unique identifier
        let request = UNNotificationRequest(
            identifier: Self.requestIdentifier(budgetID: notification.budgetId,
                                               periodKey: notification.periodKey,
                                               threshold: notification.alertType.threshold),
            content: content,
            trigger: nil // Deliver immediately
        )
        
        do {
            try await center.add(request)
            return true
        } catch {
            #if DEBUG
            print("Failed to schedule notification: \(error)")
            #endif
            return false
        }
    }

    nonisolated static func requestIdentifier(budgetID: UUID, periodKey: String, threshold: Int) -> String {
        "budgetAlert_\(budgetID.uuidString)_\(periodKey)_\(threshold)"
    }
    
    // MARK: - Scheduled Reminders
    
    /// Schedule daily budget summary notification
    func scheduleDailySummary(at hour: Int = 20, minute: Int = 0) async {
        let center = UNUserNotificationCenter.current()
        
        // Remove existing daily summary
        center.removePendingNotificationRequests(withIdentifiers: ["daily_budget_summary"])
        
        let content = UNMutableNotificationContent()
        content.title = L10n.Notifications.dailySummaryTitle
        content.body = L10n.Notifications.dailySummaryBody
        content.sound = .default
        content.categoryIdentifier = "DAILY_SUMMARY"
        
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: "daily_budget_summary",
            content: content,
            trigger: trigger
        )
        
        do {
            try await center.add(request)
        } catch {
            #if DEBUG
            print("Failed to schedule daily summary: \(error)")
            #endif
        }
    }
    
    func cancelDailySummary() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily_budget_summary"])
    }
    
    // MARK: - Persistence
    
    private func saveNotifications() {
        do {
            let encoded = try JSONEncoder().encode(inAppNotifications)
            UserDefaults.standard.set(encoded, forKey: "BudgetNotifications")
        } catch {
            ErrorService.shared.handleError(error, context: "saveNotifications")
        }
    }
    
    func loadNotifications() {
        // Decode JSON off the main thread to avoid blocking UI
        Task.detached(priority: .utility) {
            let notifications: [BudgetNotification]
            if let data = UserDefaults.standard.data(forKey: "BudgetNotifications") {
                do {
                    notifications = try JSONDecoder().decode([BudgetNotification].self, from: data)
                } catch {
                    notifications = []
                    await ErrorService.shared.handleError(error, context: "loadNotifications")
                }
            } else {
                notifications = []
            }
            await MainActor.run { [notifications] in
                self.inAppNotifications = notifications
                self.updateUnreadCount()
            }
        }
    }
    
    // MARK: - Notification Actions Setup
    
    func setupNotificationCategories() {
        let center = UNUserNotificationCenter.current()
        
        // Budget alert actions
        let viewAction = UNNotificationAction(
            identifier: "VIEW_BUDGET",
            title: L10n.Notifications.viewBudget,
            options: [.foreground]
        )
        
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: L10n.Notifications.dismiss,
            options: []
        )
        
        let budgetCategory = UNNotificationCategory(
            identifier: "BUDGET_ALERT",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Daily summary actions
        let summaryViewAction = UNNotificationAction(
            identifier: "VIEW_SUMMARY",
            title: L10n.Notifications.viewAnalysis,
            options: [.foreground]
        )
        
        let summaryCategory = UNNotificationCategory(
            identifier: "DAILY_SUMMARY",
            actions: [summaryViewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        // One call owns the entire category set, so the recurring "due" category
        // (Post / Skip / Review) must be registered here too — registering it
        // separately would clobber these budget categories.
        center.setNotificationCategories([budgetCategory, summaryCategory, RecurringNotificationService.dueCategory])
    }
}

// MARK: - Budget Notification Model

struct BudgetNotification: Identifiable, Codable {
    let id: UUID
    let budgetId: UUID
    let budgetName: String
    let alertType: BudgetAlertType
    let progress: Double
    let timestamp: Date
    var periodKey: String = ""
    var isRead: Bool
    
    init(budgetId: UUID, budgetName: String, alertType: BudgetAlertType, progress: Double, timestamp: Date, periodKey: String = "") {
        self.id = UUID()
        self.budgetId = budgetId
        self.budgetName = budgetName
        self.alertType = alertType
        self.progress = progress
        self.timestamp = timestamp
        self.periodKey = periodKey.isEmpty ? budgetId.uuidString : periodKey
        self.isRead = false
    }
    
    var progressPercent: Int {
        Int(progress * 100)
    }
    
    var timeAgo: String {
        timestamp.formatted(
            .relative(presentation: .numeric, unitsStyle: .abbreviated)
                .locale(.app)
        )
    }
}
