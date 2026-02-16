
import SwiftUI
import SwiftData

struct ExportOptionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Wallet.name) private var wallets: [Wallet]
    
    // Selection State
    @State private var selectedWallets: Set<Wallet> = []
    @State private var dateRange: ExportDateRange = .allTime
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    
    // Export State
    @State private var isExporting = false
    @State private var showShareSheet = false
    @State private var exportURL: URL?
    @State private var showError = false
    @State private var errorMessage = ""
    
    enum ExportDateRange: String, CaseIterable, Identifiable {
        case allTime = "All Time"
        case thisMonth = "This Month"
        case lastMonth = "Last Month"
        case thisYear = "This Year"
        case custom = "Custom Range"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        Form {
            Section("Data Selection") {
                // Wallet Selection
                NavigationLink {
                    WalletSelectionList(wallets: wallets, selectedWallets: $selectedWallets)
                } label: {
                    HStack {
                        Text("Wallets")
                        Spacer()
                        if selectedWallets.isEmpty {
                            Text("All Wallets")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(selectedWallets.count) Selected")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .id(selectedWallets.hashValue) // Force refresh if needed
                
                // Date Selection
                Picker("Time Period", selection: $dateRange) {
                    ForEach(ExportDateRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                
                if dateRange == .custom {
                    DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)
                }
            }
            
            Section {
                Button {
                    performExport()
                } label: {
                    if isExporting {
                        HStack {
                            Text("Generating CSV...")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("Export to CSV")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .disabled(isExporting)
            } footer: {
               Text("Exported file includes date, time, amount, currency, category, type, note, and wallet information.")
            }
        }
        .navigationTitle("Export Data")
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
            }
        }
        .alert("Export Failed", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func performExport() {
        isExporting = true
        
        Task {
            // Calculate Dates
            let (start, end) = calculateDateRange()
            
            if let url = CSVExportService.shared.exportData(
                modelContext: modelContext,
                wallets: selectedWallets,
                startDate: start,
                endDate: end
            ) {
                exportURL = url
                showShareSheet = true
            } else {
                errorMessage = "Could not generate CSV file."
                showError = true
            }
            
            isExporting = false
        }
    }
    
    private func calculateDateRange() -> (Date?, Date?) {
        let calendar = Calendar.current
        let now = Date()
        
        switch dateRange {
        case .allTime:
            return (nil, nil)
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start!)
            return (start, end)
        case .lastMonth:
            let start = calendar.date(byAdding: .month, value: -1, to: calendar.date(from: calendar.dateComponents([.year, .month], from: now))!)
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start!)
            return (start, end)
        case .thisYear:
            let start = calendar.date(from: calendar.dateComponents([.year], from: now))
             return (start, nil) // Until now
        case .custom:
            return (customStartDate, customEndDate)
        }
    }
}

// Simple multi-selection list
struct WalletSelectionList: View {
    let wallets: [Wallet]
    @Binding var selectedWallets: Set<Wallet>
    
    var body: some View {
        List {
            Button {
                if selectedWallets.isEmpty {
                     // If currently "All" (empty), selecting "All" does nothing or deselects specific?
                     // Let's treat empty as All.
                } else {
                    selectedWallets.removeAll()
                }
            } label: {
                HStack {
                    Text("All Wallets")
                    Spacer()
                    if selectedWallets.isEmpty {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            Section {
                ForEach(wallets) { wallet in
                    Button {
                        if selectedWallets.isEmpty {
                            // If switching from All to Specific, add all others first? No, standard is start fresh or toggle.
                            // Easier: If empty (All), and you click one, you enter "Specific" mode with just that one?
                            // Or better: Empty = All. Non-Empty = Specific.
                            // If I click a wallet, I select it.
                            selectedWallets.insert(wallet)
                        } else {
                            if selectedWallets.contains(wallet) {
                                selectedWallets.remove(wallet)
                            } else {
                                selectedWallets.insert(wallet)
                            }
                        }
                    } label: {
                        HStack {
                            Label(wallet.name, systemImage: wallet.icon)
                            Spacer()
                            if selectedWallets.contains(wallet) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("Select Wallets")
    }
}
