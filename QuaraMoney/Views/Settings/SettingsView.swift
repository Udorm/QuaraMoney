import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false
    @ObservedObject private var currencyManager = CurrencyManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    @AppStorage("useSidebarOniPad") private var useSidebarOniPad: Bool = true
    @State private var showPopulateConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var isPopulating = false
    @State private var isDeleting = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        Form {
            Section(L10n.Settings.general) {
                // Language Picker
                Picker(L10n.Settings.language, selection: Binding(
                    get: { languageManager.selectedLanguage },
                    set: { languageManager.selectedLanguage = $0 }
                )) {
                    ForEach(LanguageManager.Language.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                
                Picker(L10n.Settings.defaultCurrency, selection: $currencyManager.preferredCurrencyCode) {
                    ForEach(currencyManager.availableCurrencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                
                NavigationLink(destination: ThemeSettingsView()) {
                    HStack {
                        Text(L10n.Settings.themeColors)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(ThemeManager.shared.incomeColor)
                                .frame(width: 12, height: 12)
                            Circle()
                                .fill(ThemeManager.shared.expenseColor)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
                
                NavigationLink(destination: CSVImportView(modelContext: modelContext)) {
                    Label(L10n.Settings.importCSV, systemImage: "square.and.arrow.down")
                }
                
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Toggle(L10n.Settings.useSidebarOniPad, isOn: $useSidebarOniPad)
                }
            }
            
            Section(L10n.Settings.exchangeRates) {
                Button(L10n.Settings.refreshRates) {
                    Task {
                        await currencyManager.fetchRates()
                    }
                }
                
                List {
                    ForEach(currencyManager.availableCurrencies, id: \.self) { code in
                        if code != "USD" { // USD is 1.0
                            HStack {
                                Text(code)
                                Spacer()
                                Text((currencyManager.rates[code] ?? 0.0).formatted(.number.precision(.fractionLength(2))))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            
            Section(L10n.Settings.dataManagement) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    if isDeleting {
                        HStack {
                            Text(L10n.Status.deleting)
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text(L10n.Settings.deleteAllTransactions)
                    }
                }
                .disabled(isPopulating || isDeleting)
                
                Button {
                    showPopulateConfirmation = true
                } label: {
                    if isPopulating {
                        HStack {
                            Text(L10n.Status.populating)
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text(L10n.Settings.populateSampleData)
                    }
                }
                .disabled(isPopulating || isDeleting)
                
                Button(L10n.Settings.resetOnboarding) {
                    isOnboardingCompleted = false
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
