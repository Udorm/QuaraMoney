import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false
    @ObservedObject private var currencyManager = CurrencyManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    @AppStorage("useSidebarOniPad") private var useSidebarOniPad: Bool = true
    @AppStorage("appTheme") private var selectedTheme: QuaraMoneyApp.AppTheme = .system
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var securityManager = SecurityManager.shared
    @State private var showPopulateConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var isPopulating = false
    @State private var isDeleting = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Form {
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

                NavigationLink(destination: ThemeSettingsView()) {
                    Label {
                        LabeledContent {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(ThemeManager.shared.incomeColor)
                                    .frame(width: 10, height: 10)
                                Circle()
                                    .fill(ThemeManager.shared.expenseColor)
                                    .frame(width: 10, height: 10)
                            }
                        } label: {
                            Text(L10n.Settings.themeColors)
                        }
                    } icon: {
                        ListIconView(systemImage: "paintpalette.fill", color: .pink)
                    }
                }

                if UIDevice.current.userInterfaceIdiom == .pad {
                    Toggle(isOn: $useSidebarOniPad) {
                        Label {
                            Text(L10n.Settings.useSidebarOniPad)
                        } icon: {
                            ListIconView(systemImage: "sidebar.left", color: Color(.systemGray))
                        }
                    }
                }
            }

            Section("Appearance") {
                Picker(selection: $selectedTheme) {
                    ForEach(QuaraMoneyApp.AppTheme.allCases) { theme in
                        Label(theme.rawValue, systemImage: theme.icon)
                            .tag(theme)
                    }
                } label: {
                    Label {
                        Text("App Theme")
                    } icon: {
                        ListIconView(systemImage: "circle.lefthalf.filled", color: Color(.systemIndigo))
                    }
                }
            }

            Section("Currency") {
                NavigationLink(destination: CurrencySelectionView()) {
                    Label {
                        LabeledContent {
                            Text(currencyManager.preferredCurrencyCode)
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(L10n.Settings.defaultCurrency)
                        }
                    } icon: {
                        ListIconView(systemImage: "dollarsign.circle.fill", color: .green)
                    }
                }

                if currencyManager.preferredCurrencyCode != "USD" {
                    Label {
                        LabeledContent {
                            Group {
                                if let rate = currencyManager.rates[currencyManager.preferredCurrencyCode] {
                                    Text("1 USD ≈ \(rate.formatted(.number.precision(.fractionLength(2)))) \(currencyManager.preferredCurrencyCode)")
                                } else {
                                    Text("Fetching...")
                                        .task { await currencyManager.fetchRates() }
                                }
                            }
                            .foregroundStyle(.secondary)
                        } label: {
                            Text("Exchange Rate")
                        }
                    } icon: {
                        ListIconView(systemImage: "arrow.2.squarepath", color: .teal)
                    }
                }
            }

            Section("Notifications") {
                Toggle(isOn: $notificationManager.isDailyReminderEnabled) {
                    Label {
                        Text("Daily Reminder")
                    } icon: {
                        ListIconView(systemImage: "bell.fill", color: .red)
                    }
                }
                .onChange(of: notificationManager.isDailyReminderEnabled) { _, newValue in
                    if newValue { notificationManager.requestPermission() }
                }

                if notificationManager.isDailyReminderEnabled {
                    DatePicker(selection: notificationManager.reminderDateBinding, displayedComponents: .hourAndMinute) {
                        Label {
                            Text("Time")
                        } icon: {
                            ListIconView(systemImage: "clock.fill", color: .orange)
                        }
                    }
                }
            }

            Section("Cloud Sync") {
                NavigationLink(destination: CloudSyncSettingsView()) {
                    Label {
                        Text("Cloud Sync & Account")
                    } icon: {
                        ListIconView(systemImage: "icloud.fill", color: .cyan)
                    }
                }
            }

            Section("Security") {
                Toggle(isOn: $securityManager.isAppLockEnabled) {
                    Label {
                        Text("App Lock")
                    } icon: {
                        ListIconView(systemImage: "lock.fill", color: Color(.systemGray2))
                    }
                }
            }

            Section("AI Scanning") {
                Label {
                    SecureField("Gemini API Key", text: Binding(
                        get: { securityManager.getAPIKey() ?? "" },
                        set: { newValue in
                            if newValue.isEmpty {
                                securityManager.deleteAPIKey()
                            } else {
                                _ = securityManager.saveAPIKey(newValue)
                            }
                        }
                    ))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                } icon: {
                    ListIconView(systemImage: "sparkles", color: .purple)
                }

                Text("Enter your Gemini API Key to enable smart receipt scanning. If left empty, the app will use standard on-device OCR.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.Settings.dataManagement) {
                NavigationLink(destination: ExportOptionsView()) {
                    Label {
                        Text("Export Transactions")
                    } icon: {
                        ListIconView(systemImage: "square.and.arrow.up.fill", color: .blue)
                    }
                }

                NavigationLink(destination: CSVImportView(modelContext: modelContext)) {
                    Label {
                        Text(L10n.Settings.importCSV)
                    } icon: {
                        ListIconView(systemImage: "square.and.arrow.down.fill", color: .teal)
                    }
                }

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

            Section {
                Text(L10n.Settings.version)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(.secondary)
                    .font(.app(.footnote))
            }
        }
        .navigationTitle(L10n.Settings.title)
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
                            .font(.app(.headline))
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
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    } catch {
                        errorMessage = "Error populating data: \(error.localizedDescription)"
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
                Task {
                    let service = SampleDataService(modelContext: modelContext)
                    do {
                        try await service.deleteAllTransactions()
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    } catch {
                        errorMessage = "Error deleting transactions: \(error.localizedDescription)"
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
}
