import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false
    private var currencyManager = CurrencyManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    @AppStorage("useSidebarOniPad") private var useSidebarOniPad: Bool = true
    @AppStorage("appTheme") private var selectedTheme: QuaraMoneyApp.AppTheme = .system
    @AppStorage("useCompactTransactionEntry") private var useCompactTransactionEntry = false
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var securityManager = SecurityManager.shared
    @State private var showPopulateConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var isPopulating = false
    @State private var isDeleting = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        @Bindable var securityManager = securityManager

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

            Section {
                Toggle(isOn: $useCompactTransactionEntry) {
                    Label {
                        Text("settings.compactEntry".localized)
                    } icon: {
                        ListIconView(systemImage: "rectangle.compress.vertical", color: .mint)
                    }
                }
            } footer: {
                Text("settings.compactEntry.footer".localized)
            }

            Section("settings.appearance".localized) {
                Picker(selection: $selectedTheme) {
                    ForEach(QuaraMoneyApp.AppTheme.allCases) { theme in
                        Label(theme.displayName, systemImage: theme.icon)
                            .tag(theme)
                    }
                } label: {
                    Label {
                        Text("settings.appTheme".localized)
                    } icon: {
                        ListIconView(systemImage: "circle.lefthalf.filled", color: Color(.systemIndigo))
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
            }

            Section("settings.currency".localized) {
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
                                    Text("settings.exchangeRateValue".localized(with: rate.formatted(.number.precision(.fractionLength(2))), currencyManager.preferredCurrencyCode))
                                } else {
                                    Text("settings.fetchingRate".localized)
                                        .task { await currencyManager.fetchRates() }
                                }
                            }
                            .foregroundStyle(.secondary)
                        } label: {
                            Text("settings.exchangeRate".localized)
                        }
                    } icon: {
                        ListIconView(systemImage: "arrow.2.squarepath", color: .teal)
                    }
                }
            }

            Section("settings.notifications".localized) {
                Toggle(isOn: $notificationManager.isDailyReminderEnabled) {
                    Label {
                        Text("settings.dailyReminder".localized)
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
                            Text("settings.reminderTime".localized)
                        } icon: {
                            ListIconView(systemImage: "clock.fill", color: .orange)
                        }
                    }
                }
            }


            Section("settings.security".localized) {
                Toggle(isOn: $securityManager.isAppLockEnabled) {
                    Label {
                        Text("settings.appLock".localized)
                    } icon: {
                        ListIconView(systemImage: "lock.fill", color: Color(.systemGray2))
                    }
                }
            }

            Section("settings.aiScanning.title".localized) {
                NavigationLink(destination: ReceiptScanningSettingsView()) {
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
            }

            Section(L10n.Settings.dataManagement) {
                NavigationLink(destination: ExportOptionsView()) {
                    Label {
                        Text("settings.exportTransactions".localized)
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
            // one mis-tap away from routine data tools.
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
            }

            Section {
                Text(L10n.Settings.version)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(.secondary)
                    .appFont(.footnote)
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
}
