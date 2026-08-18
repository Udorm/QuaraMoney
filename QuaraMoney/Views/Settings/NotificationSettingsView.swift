import SwiftUI
import UserNotifications

/// Daily-reminder settings, split out of the main Settings list.
///
/// Also closes the dead end the inline toggle had: with notifications denied at
/// the iOS level, flipping the switch snapped straight back
/// (`NotificationManager.requestPermission` clears `isDailyReminderEnabled` when
/// the system refuses) and nothing on screen explained why.
struct NotificationSettingsView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    @Environment(\.scenePhase) private var scenePhase

    /// Denied at the iOS level — the toggle can never turn on from in here.
    private var isBlocked: Bool { notificationManager.authorizationStatus == .denied }

    var body: some View {
        Form {
            if isBlocked {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("settings.notifications.blockedTitle".localized)
                            .appFont(.subheadline, weight: .semibold)
                        Text("settings.notifications.blockedBody".localized)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)

                    Button {
                        openSystemSettings()
                    } label: {
                        Label("settings.notifications.openSettings".localized,
                              systemImage: "arrow.up.right.square")
                    }
                }
            }

            Section {
                Toggle(isOn: $notificationManager.isDailyReminderEnabled) {
                    Label {
                        Text("settings.dailyReminder".localized)
                    } icon: {
                        ListIconView(systemImage: "bell.fill", color: .red)
                    }
                }
                .disabled(isBlocked)
                .onChange(of: notificationManager.isDailyReminderEnabled) { _, newValue in
                    if newValue { notificationManager.requestPermission() }
                }

                if notificationManager.isDailyReminderEnabled {
                    DatePicker(selection: notificationManager.reminderDateBinding,
                               displayedComponents: .hourAndMinute) {
                        Label {
                            Text("settings.reminderTime".localized)
                        } icon: {
                            ListIconView(systemImage: "clock.fill", color: .orange)
                        }
                    }
                }
            } footer: {
                Text("settings.notifications.footer".localized)
                    .sectionFooter()
            }
        }
        .navigationTitle("settings.notifications".localized)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { notificationManager.checkPermissionStatus() }
        // Returning from iOS Settings is the only way the authorization can
        // change while this screen is open.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { notificationManager.checkPermissionStatus() }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}
