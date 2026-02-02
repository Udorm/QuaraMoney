import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false
    @ObservedObject private var currencyManager = CurrencyManager.shared
    @State private var showPopulateConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var isPopulating = false
    @State private var isDeleting = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        Form {
            Section("General") {
                Picker("Default Currency", selection: $currencyManager.preferredCurrencyCode) {
                    ForEach(currencyManager.availableCurrencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                
                NavigationLink(destination: ThemeSettingsView()) {
                    HStack {
                        Text("Theme & Colors")
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
                    Label("Import from CSV", systemImage: "square.and.arrow.down")
                }
            }
            
            Section("Exchange Rates (Base: USD)") {
                Button("Refresh Rates") {
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
            
            Section("Data Management") {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    if isDeleting {
                        HStack {
                            Text("Deleting...")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("Delete All Transactions")
                    }
                }
                .disabled(isPopulating || isDeleting)
                
                Button {
                    showPopulateConfirmation = true
                } label: {
                    if isPopulating {
                        HStack {
                            Text("Populating...")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("Populate Sample Data")
                    }
                }
                .disabled(isPopulating || isDeleting)
                
                Button("Reset Onboarding") {
                    isOnboardingCompleted = false
                }
            }
            
            Section {
                 Text("QuaraMoney v1.0")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .navigationTitle("Settings")
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
                        Text("Populating Data...")
                            .font(.headline)
                    }
                    .padding(24)
                    .background(.thickMaterial)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                }
            }
        }
        .alert("Populate Sample Data?", isPresented: $showPopulateConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Populate", role: .destructive) {
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
            Text("This will delete all existing data and replace it with sample wallets, categories, and transactions. This action cannot be undone.")
        }
        .alert("Delete All Transactions?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
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
            Text("Are you sure you want to delete all transactions? Wallets and Categories will be kept. This action cannot be undone.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
}
