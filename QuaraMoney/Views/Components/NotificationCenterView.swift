import SwiftUI

struct NotificationCenterView: View {
    @ObservedObject var notificationService = BudgetNotificationService.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if notificationService.inAppNotifications.isEmpty {
                    ContentUnavailableView(
                        "No Notifications",
                        systemImage: "bell.slash",
                        description: Text("Budget alerts will appear here")
                    )
                } else {
                    List {
                        ForEach(notificationService.inAppNotifications) { notification in
                            NotificationRowView(notification: notification)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        notificationService.clearNotification(notification)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    if !notification.isRead {
                                        Button {
                                            notificationService.markAsRead(notification)
                                        } label: {
                                            Label("Read", systemImage: "envelope.open")
                                        }
                                        .tint(.blue)
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                
                if !notificationService.inAppNotifications.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                notificationService.markAllAsRead()
                            } label: {
                                Label("Mark All Read", systemImage: "envelope.open")
                            }
                            
                            Button(role: .destructive) {
                                notificationService.clearAllNotifications()
                            } label: {
                                Label("Clear All", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .onAppear {
            notificationService.loadNotifications()
        }
    }
}

// MARK: - Notification Row View

struct NotificationRowView: View {
    let notification: BudgetNotification
    
    var body: some View {
        HStack(spacing: 12) {
            // Alert type icon
            ZStack {
                Circle()
                    .fill(Color(hex: notification.alertType.color)?.opacity(0.15) ?? Color.gray.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: notification.alertType.icon)
                    .font(.title3)
                    .foregroundStyle(Color(hex: notification.alertType.color) ?? .gray)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(notification.alertType.rawValue)
                        .font(.headline)
                        .foregroundStyle(notification.isRead ? .secondary : .primary)
                    
                    Spacer()
                    
                    Text(notification.timeAgo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(notification.alertType.message(budgetName: notification.budgetName))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                // Progress indicator
                HStack(spacing: 8) {
                    ProgressView(value: min(notification.progress, 1.0))
                        .tint(Color(hex: notification.alertType.color) ?? .blue)
                    
                    Text("\(notification.progressPercent)%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color(hex: notification.alertType.color) ?? .gray)
                }
            }
            
            // Unread indicator
            if !notification.isRead {
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Notification Bell Button (for navigation bar)

struct NotificationBellButton: View {
    @ObservedObject var notificationService = BudgetNotificationService.shared
    @State private var showNotificationCenter = false
    
    var body: some View {
        Button {
            showNotificationCenter = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.title3)
                
                if notificationService.unreadCount > 0 {
                    Text("\(min(notificationService.unreadCount, 99))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.red)
                        .clipShape(Circle())
                        .offset(x: 8, y: -8)
                }
            }
        }
        .sheet(isPresented: $showNotificationCenter) {
            NotificationCenterView()
        }
        .onAppear {
            notificationService.loadNotifications()
        }
    }
}

#Preview {
    NotificationCenterView()
}
