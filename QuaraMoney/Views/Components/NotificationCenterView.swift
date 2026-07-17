import SwiftUI

struct NotificationCenterView: View {
    @ObservedObject var notificationService = BudgetNotificationService.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if notificationService.inAppNotifications.isEmpty {
                    AppEmptyStateView(
                        L10n.Notifications.emptyTitle,
                        systemImage: "bell.slash",
                        description: L10n.Notifications.emptyDescription
                    )
                } else {
                    List {
                        ForEach(notificationService.inAppNotifications) { notification in
                            NotificationRowView(notification: notification)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        notificationService.clearNotification(notification)
                                    } label: {
                                        Label(L10n.Common.delete, systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    if !notification.isRead {
                                        Button {
                                            notificationService.markAsRead(notification)
                                        } label: {
                                            Label(L10n.Notifications.read, systemImage: "envelope.open")
                                        }
                                        .tint(.blue)
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle(L10n.Notifications.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.Common.close) { dismiss() }
                }
                
                if !notificationService.inAppNotifications.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                notificationService.markAllAsRead()
                            } label: {
                                Label(L10n.Notifications.markAllRead, systemImage: "envelope.open")
                            }
                            
                            Button(role: .destructive) {
                                notificationService.clearAllNotifications()
                            } label: {
                                Label(L10n.Notifications.clearAll, systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
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
                    .fill(Color(hex: notification.alertType.color)?.opacity(0.15) ?? Color(.secondarySystemBackground))
                    .frame(width: 44, height: 44)
                
                Image(systemName: notification.alertType.icon)
                    .appFont(.title3)
                    .foregroundStyle(Color(hex: notification.alertType.color) ?? Color(.systemGray))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(notification.alertType.rawValue)
                        .appFont(.headline)
                        .foregroundStyle(notification.isRead ? .secondary : .primary)
                    
                    Spacer()
                    
                    Text(notification.timeAgo)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(notification.alertType.message(budgetName: notification.budgetName))
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                // Progress indicator
                HStack(spacing: 8) {
                    ProgressView(value: min(notification.progress, 1.0))
                        .tint(Color(hex: notification.alertType.color) ?? .blue)
                    
                    Text("\(notification.progressPercent)%")
                        .appFont(.caption, weight: .medium)
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
                    .appFont(.title3)
                
                if notificationService.unreadCount > 0 {
                    Text("\(min(notificationService.unreadCount, 99))")
                        .appFont(.caption2, weight: .bold)
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
