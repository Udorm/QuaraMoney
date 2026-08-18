import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false
    private var currencyManager = CurrencyManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    @AppStorage("appTheme") private var selectedTheme: QuaraMoneyApp.AppTheme = .system
    @AppStorage("useCompactTransactionEntry") private var useCompactTransactionEntry = false
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var securityManager = SecurityManager.shared
    @State private var showPopulateConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var isPopulating = false
    @State private var isDeleting = false
    @State private var showCurrencyPicker = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        @Bindable var securityManager = securityManager

        Form {
            // MARK: - General
            // Each row either edits in place (language) or opens a screen that
            // shows its current value on the right, so the list stays one
            // header tall instead of one header per setting.
            Section(L10n.Settings.general) {
                Picker(selection: Binding(
                    get: { languageManager.selectedLanguage },
                    set: { languageManager.selectedLanguage = $0 }
                )) {
                    ForEach(LanguageManager.Language.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                } label: {
                    Label {
                        Text(L10n.Settings.language)
                    } icon: {
                        ListIconView(systemImage: "globe", color: .blue)
                    }
                }

                Button {
                    showCurrencyPicker = true
                } label: {
                    Label {
                        LabeledContent {
                            HStack(spacing: 6) {
                                Text(currencyManager.preferredCurrencyCode)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .appFont(.footnote, weight: .semibold)
                                    .foregroundStyle(.tertiary)
                            }
                        } label: {
                            Text(L10n.Settings.defaultCurrency)
                                .foregroundStyle(.primary)
                        }
                    } icon: {
                        ListIconView(systemImage: "dollarsign.circle.fill", color: .green)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                NavigationLink(destination: LazyView(AppearanceSettingsView())) {
                    Label {
                        LabeledContent {
                            Text(selectedTheme.displayName)
                                .foregroundStyle(.secondary)
                        } label: {
                            Text("settings.appearance".localized)
                        }
                    } icon: {
                        ListIconView(systemImage: "circle.lefthalf.filled", color: Color(.systemIndigo))
                    }
                }

                NavigationLink(destination: LazyView(NotificationSettingsView())) {
                    Label {
                        LabeledContent {
                            Text(reminderSummary)
                                .foregroundStyle(.secondary)
                        } label: {
                            Text("settings.notifications".localized)
                        }
                    } icon: {
                        ListIconView(systemImage: "bell.fill", color: .red)
                    }
                }
            }

            // MARK: - Adding transactions
            // Compact entry sits last so the footer explaining it lands
            // directly under its toggle.
            Section {
                NavigationLink(destination: LazyView(ReceiptScanningSettingsView())) {
                    Label {
                        LabeledContent {
                            Text(securityManager.getAPIKey()?.isEmpty == false
                                 ? "settings.aiScanning.statusCloud".localized
                                 : "settings.aiScanning.statusOnDevice".localized)
                            .foregroundStyle(.secondary)
                        } label: {
                            Text("settings.aiScanning.rowTitle".localized)
                        }
                    } icon: {
                        ListIconView(systemImage: "sparkles", color: .purple)
                    }
                }

                Toggle(isOn: $useCompactTransactionEntry) {
                    Label {
                        Text("settings.compactEntry".localized)
                    } icon: {
                        ListIconView(systemImage: "rectangle.compress.vertical", color: .mint)
                    }
                }
            } header: {
                Text("settings.section.entry".localized)
            } footer: {
                Text("settings.compactEntry.footer".localized)
                    .sectionFooter()
            }

            // MARK: - Data & privacy
            Section("settings.section.dataPrivacy".localized) {
                Toggle(isOn: $securityManager.isAppLockEnabled) {
                    Label {
                        Text("settings.appLock".localized)
                    } icon: {
                        ListIconView(systemImage: "lock.fill", color: Color(.systemGray2))
                    }
                }

                NavigationLink(destination: LazyView(ExportOptionsView())) {
                    Label {
                        Text("settings.exportTransactions".localized)
                    } icon: {
                        ListIconView(systemImage: "square.and.arrow.up.fill", color: .blue)
                    }
                }

                NavigationLink(destination: LazyView(CSVImportView(modelContext: modelContext))) {
                    Label {
                        Text(L10n.Settings.importCSV)
                    } icon: {
                        ListIconView(systemImage: "square.and.arrow.down.fill", color: .teal)
                    }
                }
            }

            #if DEBUG
            // Developer-only tools. Sample data would pollute a synced account
            // and onboarding reset is a debug affordance — never ship these.
            Section("Developer") {
                Button {
                    showPopulateConfirmation = true
                } label: {
                    Label {
                        if isPopulating {
                            HStack {
                                Text(L10n.Status.populating)
                                Spacer()
                                ProgressView()
                            }
                        } else {
                            Text(L10n.Settings.populateSampleData)
                                .foregroundStyle(.primary)
                        }
                    } icon: {
                        ListIconView(systemImage: "chart.bar.doc.horizontal", color: .orange)
                    }
                }
                .disabled(isPopulating || isDeleting)

                Button {
                    isOnboardingCompleted = false
                } label: {
                    Label {
                        Text(L10n.Settings.resetOnboarding)
                            .foregroundStyle(.primary)
                    } icon: {
                        ListIconView(systemImage: "arrow.counterclockwise", color: Color(.systemOrange))
                    }
                }
            }
            #endif

            // Destructive action isolated in its own section (HIG) so it isn't
            // one mis-tap away from routine data tools. The version rides in
            // this section's footer rather than claiming a section of its own.
            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label {
                        if isDeleting {
                            HStack {
                                Text(L10n.Status.deleting)
                                Spacer()
                                ProgressView()
                            }
                        } else {
                            Text(L10n.Settings.deleteAllTransactions)
                        }
                    } icon: {
                        ListIconView(systemImage: "trash.fill", color: .red)
                    }
                }
                .disabled(isPopulating || isDeleting)
            } footer: {
                Text(L10n.Settings.version)
                    .sectionFooter()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
        }
        .navigationTitle(L10n.Settings.title)
        .sheet(isPresented: $showCurrencyPicker) {
            NavigationStack {
                CurrencySelectionView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(.systemGroupedBackground))
        }
        .disabled(isPopulating)
        .overlay {
            if isPopulating {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.primary)
                        Text(L10n.Status.populatingData)
                            .appFont(.headline)
                    }
                    .padding(24)
                    .background(.thickMaterial)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                }
            }
        }
        .alert(L10n.Alert.PopulateData.title, isPresented: $showPopulateConfirmation) {
            Button(L10n.Common.cancel, role: .cancel) { }
            Button(L10n.Alert.PopulateData.confirm, role: .destructive) {
                isPopulating = true
                Task {
                    let service = SampleDataService(modelContext: modelContext)
                    do {
                        try await service.populate()
                    } catch {
                        errorMessage = "settings.populateError".localized(with: error.localizedDescription)
                        showError = true
                    }
                    isPopulating = false
                }
            }
        } message: {
            Text(L10n.Alert.PopulateData.message)
        }
        .alert(L10n.Alert.DeleteTransactions.title, isPresented: $showDeleteConfirmation) {
            Button(L10n.Common.cancel, role: .cancel) { }
            Button(L10n.Common.delete, role: .destructive) {
                isDeleting = true
                HapticManager.shared.warning()
                Task {
                    let service = SampleDataService(modelContext: modelContext)
                    do {
                        try await service.deleteAllTransactions()
                    } catch {
                        errorMessage = "settings.deleteError".localized(with: error.localizedDescription)
                        showError = true
                    }
                    isDeleting = false
                }
            }
        } message: {
            Text(L10n.Alert.DeleteTransactions.message)
        }
        .alert(L10n.Common.error, isPresented: $showError) {
            Button(L10n.Common.ok, role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    /// Trailing value for the Notifications row: the reminder time, or "Off".
    /// Formatted through `appFormatted` so Khmer gets Khmer digits.
    private var reminderSummary: String {
        guard notificationManager.isDailyReminderEnabled else {
            return "common.off".localized
        }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return startOfDay
            .addingTimeInterval(notificationManager.reminderTime)
            .appFormatted(date: .omitted, time: .shortened)
    }
}
