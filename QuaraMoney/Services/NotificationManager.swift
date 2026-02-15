import SwiftUI
import UserNotifications
import Combine

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isPermissionGranted = false
    @AppStorage("isDailyReminderEnabled") var isDailyReminderEnabled = false {
        didSet {
            if isDailyReminderEnabled {
                scheduleNotification()
            } else {
                cancelNotification()
            }
        }
    }
    
    @AppStorage("dailyReminderTime") var reminderTime: Double = 20 * 3600 { // Default 8 PM
        didSet {
            if isDailyReminderEnabled {
                scheduleNotification()
            }
        }
    }
    
    private init() {
        checkPermissionStatus()
    }
    
    func checkPermissionStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isPermissionGranted = settings.authorizationStatus == .authorized
                // If permission revoked externally, update state
                if !self.isPermissionGranted && self.isDailyReminderEnabled {
                    self.isDailyReminderEnabled = false
                }
            }
        }
    }
    
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.isPermissionGranted = granted
                if granted {
                    self.isDailyReminderEnabled = true // Auto enable on grant
                } else {
                    self.isDailyReminderEnabled = false
                }
            }
        }
    }
    
    private func scheduleNotification() {
        guard isPermissionGranted else {
            requestPermission()
            return // Will retry in callback if granted
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Time to log your expenses! 📝"
        content.body = "Don't forget to record your transactions for today."
        content.sound = .default
        
        // Convert double (seconds from midnight) to DateComponents
        let date = Date(timeIntervalSinceReferenceDate: reminderTime)
        let calendar = Calendar.current
        let hour = Int(reminderTime) / 3600
        let minute = (Int(reminderTime) % 3600) / 60
        
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_reminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().add(request)
    }
    
    private func cancelNotification() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    // Helper to bind DatePicker to Double storage
    var reminderDateBinding: Binding<Date> {
        Binding(
            get: {
                let startOfDay = Calendar.current.startOfDay(for: Date())
                return startOfDay.addingTimeInterval(self.reminderTime)
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                let seconds = (components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60
                self.reminderTime = Double(seconds)
            }
        )
    }
}
