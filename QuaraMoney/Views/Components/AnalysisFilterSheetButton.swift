import SwiftUI

struct AnalysisFilterSheetButton: View {
    @Binding var selectedTransactionType: AnalysisViewModel.TransactionTypeFilter
    @Binding var selectedWallet: Wallet?
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    
    var wallets: [Wallet]
    
    @State private var showFilterSheet = false
    
    // Check if any filter is active (non-default state)
    var isFilterActive: Bool {
        selectedWallet != nil || selectedTransactionType != .expense
    }
    
    var body: some View {
        Button {
            showFilterSheet = true
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .symbolVariant(isFilterActive ? .fill : .none)
                .font(.app(.title3)) // Match toolbar item size
                .foregroundStyle(isFilterActive ? .blue : .primary)
        }
        .sheet(isPresented: $showFilterSheet) {
            AnalysisFilterSheetView(
                selectedTransactionType: $selectedTransactionType,
                selectedWallet: $selectedWallet,
                customStartDate: $customStartDate,
                customEndDate: $customEndDate,
                wallets: wallets,
                isPresented: $showFilterSheet
            )
            .presentationDetents([.large])
        }
    }
}

struct AnalysisFilterSheetView: View {
    @Binding var selectedTransactionType: AnalysisViewModel.TransactionTypeFilter
    @Binding var selectedWallet: Wallet?
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    
    var wallets: [Wallet]
    @Binding var isPresented: Bool
    
    @State private var pendingTransactionType: AnalysisViewModel.TransactionTypeFilter
    @State private var pendingWallet: Wallet?
    @State private var pendingStartDate: Date
    @State private var pendingEndDate: Date
    
    init(selectedTransactionType: Binding<AnalysisViewModel.TransactionTypeFilter>,
         selectedWallet: Binding<Wallet?>,
         customStartDate: Binding<Date>,
         customEndDate: Binding<Date>,
         wallets: [Wallet],
         isPresented: Binding<Bool>) {
        _selectedTransactionType = selectedTransactionType
        _selectedWallet = selectedWallet
        _customStartDate = customStartDate
        _customEndDate = customEndDate
        self.wallets = wallets
        _isPresented = isPresented
        
        // Initialize pending state
        _pendingTransactionType = State(initialValue: selectedTransactionType.wrappedValue)
        _pendingWallet = State(initialValue: selectedWallet.wrappedValue)
        _pendingStartDate = State(initialValue: customStartDate.wrappedValue)
        _pendingEndDate = State(initialValue: customEndDate.wrappedValue)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("analysis.transactionType".localized) {
                    Picker("analysis.transactionType".localized, selection: $pendingTransactionType) {
                        Text(L10n.Transaction.TransactionType.expense).tag(AnalysisViewModel.TransactionTypeFilter.expense)
                        Text(L10n.Transaction.TransactionType.income).tag(AnalysisViewModel.TransactionTypeFilter.income)
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("filter.wallet".localized) {
                    WalletRow(
                        name: "filter.allWallets".localized,
                        icon: "square.stack.3d.up",
                        iconColor: .secondary,
                        isSelected: pendingWallet == nil
                    ) {
                        withAnimation {
                            pendingWallet = nil
                        }
                    }
                    
                    ForEach(wallets) { wallet in
                        WalletRow(
                            name: wallet.name,
                            icon: wallet.icon.isEmpty ? "creditcard" : wallet.icon,
                            iconColor: Color(hex: wallet.colorHex) ?? .blue,
                            isSelected: pendingWallet?.id == wallet.id
                        ) {
                            withAnimation {
                                pendingWallet = wallet
                            }
                        }
                    }
                }
                
                // Note: Analysis view has its own period picker in the chart, but we might want custom date range here if "Custom" period is selected elsewhere? 
                // However, the original AnalysisView had a separate sheet for custom date. 
                // Let's integrate custom date range here but only show it if needed or as an option?
                // Actually, for AnalysisView, the Start/End date are driven by the AnalysisPeriod. 
                // If we want to allow overriding specific dates, it usually happens when "Custom" period is active.
                // But the Period selection is on the main screen. 
                // Let's keep it simple and focus on Transaction Type and Wallet for now, as that was what the Menu did.
                // Wait, the original code had a separate sheet for Custom Date.
                // We should expose the Custom Date pickers here too, effectively merging the functionality.
                
                Section(L10n.Period.custom) {
                   DatePicker("analysis.startDate".localized, selection: $pendingStartDate, displayedComponents: .date)
                   DatePicker("analysis.endDate".localized, selection: $pendingEndDate, displayedComponents: .date)
                }
            }
            .navigationTitle("filter.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.done) {
                        applyChanges()
                    }
                }
            }
        }
    }
    
    private func applyChanges() {
        selectedTransactionType = pendingTransactionType
        selectedWallet = pendingWallet
        customStartDate = pendingStartDate
        customEndDate = pendingEndDate
        isPresented = false
    }
}
