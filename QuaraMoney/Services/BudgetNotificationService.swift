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
    
    private init() {}
    
    // MARK: - Configuration
    
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Permission Request
    
    func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Notification permission error: \(error)")
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
            
            if let alertType = budget.shouldTriggerAlert(progress: progress) {
                triggerAlert(for: budget, type: alertType, progress: progress)
                budget.recordAlertTriggered(threshold: alertType.threshold)
            }
            
            // Check projected overspend
            if budget.alertOnProjectedOverspend && !budget.isPeriodEnded {
                checkProjectedOverspend(budget: budget, currentSpent: spent)
            }
        }
    }
    
    /// Check if budget is projected to overspend
    private func checkProjectedOverspend(budget: Budget, currentSpent: Decimal) {
        let daysElapsed = budget.totalDays - budget.daysRemaining
        guard daysElapsed > 0 else { return }
        
        let dailyAverage = currentSpent / Decimal(daysElapsed)
        let projectedTotal = dailyAverage * Decimal(budget.totalDays)
        
        if projectedTotal > budget.effectiveLimit && budget.lastAlertThreshold < 100 {
            triggerAlert(for: budget, type: .projectedOverspend, progress: Double(truncating: projectedTotal as NSNumber) / Double(truncating: budget.effectiveLimit as NSNumber))
        }
    }
    
    // MARK: - Alert Triggering
    
    /// Trigger both local and in-app notification
    private func triggerAlert(for budget: Budget, type: BudgetAlertType, progress: Double) {
        let notification = BudgetNotification(
            budgetId: budget.id,
            budgetName: budget.displayName,
            alertType: type,
            progress: progress,
            timestamp: Date()
        )
        
        // Add to in-app notifications
        addInAppNotification(notification)
        
        // Schedule local notification
        Task {
            await scheduleLocalNotification(notification)
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
    
    private func scheduleLocalNotification(_ notification: BudgetNotification) async {
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
            identifier: notification.id.uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule notification: \(error)")
        }
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
            print("Failed to schedule daily summary: \(error)")
        }
    }
    
    func cancelDailySummary() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily_budget_summary"])
    }
    
    // MARK: - Persistence
    
    private func saveNotifications() {
        if let encoded = try? JSONEncoder().encode(inAppNotifications) {
            UserDefaults.standard.set(encoded, forKey: "BudgetNotifications")
        }
    }
    
    func loadNotifications() {
        // Decode JSON off the main thread to avoid blocking UI
        Task.detached(priority: .utility) {
            let notifications: [BudgetNotification]
            if let data = UserDefaults.standard.data(forKey: "BudgetNotifications"),
               let decoded = try? JSONDecoder().decode([BudgetNotification].self, from: data) {
                notifications = decoded
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
        
        center.setNotificationCategories([budgetCategory, summaryCategory])
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
    var isRead: Bool
    
    init(budgetId: UUID, budgetName: String, alertType: BudgetAlertType, progress: Double, timestamp: Date) {
        self.id = UUID()
        self.budgetId = budgetId
        self.budgetName = budgetName
        self.alertType = alertType
        self.progress = progress
        self.timestamp = timestamp
        self.isRead = false
    }
    
    var progressPercent: Int {
        Int(progress * 100)
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
