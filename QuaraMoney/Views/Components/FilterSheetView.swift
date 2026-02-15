import SwiftUI

/// A custom filter sheet that supports custom fonts and provides intuitive UX.
/// Features:
/// - Full row tapping (not just the text)
/// - Deferred apply - changes only apply when "Done" is tapped
/// - Inline custom date pickers (no separate sheet)
/// - Consistent reusable component for all filter UIs
struct FilterSheetView<Period: Hashable & Identifiable & CaseIterable & LocalizableDisplayName, Content: View>: View {
    // Bindings to actual values (applied on Done)
    @Binding var selectedPeriod: Period
    @Binding var selectedWallet: Wallet?
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    @Binding var isPresented: Bool
    
    var wallets: [Wallet]
    var showWalletFilter: Bool = true
    var showPeriodFilter: Bool = true // New property
    var extraContent: Content
    
    // Local state for pending selections (not applied until Done)
    @State private var pendingPeriod: Period
    @State private var pendingWallet: Wallet?
    @State private var pendingStartDate: Date
    @State private var pendingEndDate: Date
    
    // Track if custom period is selected to show date pickers
    private var isCustomPeriodSelected: Bool {
        pendingPeriod.displayName == L10n.Period.custom
    }
    
    init(
        selectedPeriod: Binding<Period>,
        selectedWallet: Binding<Wallet?>,
        customStartDate: Binding<Date>,
        customEndDate: Binding<Date>,
        isPresented: Binding<Bool>,
        wallets: [Wallet],
        showWalletFilter: Bool = true,
        showPeriodFilter: Bool = true, // New parameter
        @ViewBuilder extraContent: () -> Content
    ) {
        self._selectedPeriod = selectedPeriod
        self._selectedWallet = selectedWallet
        self._customStartDate = customStartDate
        self._customEndDate = customEndDate
        self._isPresented = isPresented
        self.wallets = wallets
        self.showWalletFilter = showWalletFilter
        self.showPeriodFilter = showPeriodFilter
        self.extraContent = extraContent()
        
        // Initialize pending state with current values
        self._pendingPeriod = State(initialValue: selectedPeriod.wrappedValue)
        self._pendingWallet = State(initialValue: selectedWallet.wrappedValue)
        self._pendingStartDate = State(initialValue: customStartDate.wrappedValue)
        self._pendingEndDate = State(initialValue: customEndDate.wrappedValue)
    }
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Period Section
                if showPeriodFilter {
                    Section {
                        ForEach(Array(Period.allCases)) { period in
                            PeriodRow(
                                period: period,
                                isSelected: (pendingPeriod as AnyHashable) == (period as AnyHashable),
                                icon: getIcon(for: period)
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    pendingPeriod = period
                                }
                            }
                        }
                    } header: {
                        Text("filter.period".localized)
                            .font(.app(.caption))
                    }
                }
                
                // MARK: - Custom Date Range Section (shown when Custom is selected)
                if isCustomPeriodSelected {
                    Section {
                        DatePicker(
                            "filter.startDate".localized,
                            selection: $pendingStartDate,
                            displayedComponents: .date
                        )
                        .font(.app(.body))
                        
                        DatePicker(
                            "filter.endDate".localized,
                            selection: $pendingEndDate,
                            in: pendingStartDate...,
                            displayedComponents: .date
                        )
                        .font(.app(.body))
                    } header: {
                        Text(L10n.Wallet.customRange)
                            .font(.app(.caption))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // MARK: - Wallet Section
                if showWalletFilter {
                    Section {
                        // All Wallets option
                        WalletRow(
                            name: "filter.allWallets".localized,
                            icon: "square.stack.3d.up",
                            iconColor: .secondary,
                            isSelected: pendingWallet == nil
                        ) {
                            pendingWallet = nil
                        }
                        
                        // Individual wallets
                        ForEach(wallets) { wallet in
                            WalletRow(
                                name: wallet.name,
                                icon: wallet.icon.isEmpty ? "creditcard" : wallet.icon,
                                iconColor: Color(hex: wallet.colorHex) ?? .blue,
                                isSelected: pendingWallet?.id == wallet.id
                            ) {
                                pendingWallet = wallet
                            }
                        }
                    } header: {
                        Text("filter.wallet".localized)
                            .font(.app(.caption))
                    }
                }
                extraContent
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.Filter.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        applyChanges()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Apply Changes
    
    private func applyChanges() {
        selectedPeriod = pendingPeriod
        selectedWallet = pendingWallet
        customStartDate = pendingStartDate
        customEndDate = pendingEndDate
        isPresented = false
    }
    
    // MARK: - Icon Helper
    
    private func getIcon(for period: Period) -> String {
        let name = period.displayName
        if name == L10n.Filter.thisMonth { return "calendar" }
        if name == L10n.Filter.lastMonth { return "clock.arrow.circlepath" }
        if name == L10n.Filter.thisYear { return "calendar.badge.clock" }
        if name == L10n.Period.custom { return "calendar.badge.plus" }
        if name == L10n.Filter.day { return "sun.max" }
        if name == L10n.Filter.week { return "calendar" }
        if name == L10n.Filter.month { return "calendar" }
        if name == L10n.Filter.sixMonths { return "calendar.badge.clock" }
        if name == L10n.Filter.year { return "calendar.badge.plus" }
        if name == L10n.Filter.lastYear { return "calendar.badge.clock" }
        return "calendar"
    }
}

// MARK: - Period Row Component

private struct PeriodRow<Period: LocalizableDisplayName>: View {
    let period: Period
    let isSelected: Bool
    let icon: String
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(isSelected ? .blue : .secondary)
                .frame(width: 24)
            
            Text(period.displayName)
                .font(.app(.body))
                .foregroundStyle(.primary)
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark")
                //    .foregroundStyle(.blue)
                //    .fontWeight(.semibold)
                // User didn't ask to remove checkmark but standard lists use blue checkmark.
                // Keeping as is.
                     .foregroundStyle(.blue)
                     .fontWeight(.semibold)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Wallet Row Component

struct WalletRow: View {
    let name: String
    let icon: String
    let iconColor: Color
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 24)
            
            Text(name)
                .font(.app(.body))
                .foregroundStyle(.primary)
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
                    .fontWeight(.semibold)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Filter Sheet Button (Toolbar Button)

/// A toolbar button that opens the filter sheet.
/// Use this in your toolbar to provide consistent filter access.
struct FilterSheetButton<Period: Hashable & Identifiable & CaseIterable & LocalizableDisplayName, Content: View>: View {
    @Binding var selectedPeriod: Period
    @Binding var selectedWallet: Wallet?
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    var wallets: [Wallet]
    var showWalletFilter: Bool = true
    var showPeriodFilter: Bool = true // New property
    var defaultPeriod: Period? = nil
    let extraContent: () -> Content
    
    @State private var showFilterSheet = false
    
    // Check if filter is active for UI state
    private var isFilterActive: Bool {
        // If period filter is hidden, we don't consider period changes for active state
        let isPeriodActive: Bool
        
        if showPeriodFilter {
            // Use provided default period or fallback to first case
            let defaultP = defaultPeriod ?? Array(Period.allCases).first
            
            // Check if current period is the default
            if let defaultP = defaultP {
                 isPeriodActive = (selectedPeriod as AnyHashable) != (defaultP as AnyHashable)
            } else {
                 isPeriodActive = false
            }
        } else {
            isPeriodActive = false
        }
        
        let isWalletActive = showWalletFilter ? (selectedWallet != nil) : false
        let isCustomPeriod = showPeriodFilter && selectedPeriod.displayName == L10n.Period.custom
        
        return isPeriodActive || isWalletActive || isCustomPeriod
    }
    
    var body: some View {
        Button {
            showFilterSheet = true
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .symbolVariant(isFilterActive ? .fill : .none)
                .font(.app(.title3))
                // Only show blue if filter is active (not default)
                // User req: "The filter button should not show the blue shine that indicate that not default option are selected when the default option are selected"
                .foregroundStyle(isFilterActive ? .blue : .primary)
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheetView(
                selectedPeriod: $selectedPeriod,
                selectedWallet: $selectedWallet,
                customStartDate: $customStartDate,
                customEndDate: $customEndDate,
                isPresented: $showFilterSheet,
                wallets: wallets,
                showWalletFilter: showWalletFilter,
                showPeriodFilter: showPeriodFilter, // Pass it
                extraContent: extraContent
            )
        }
    }
    
    init(
        selectedPeriod: Binding<Period>,
        selectedWallet: Binding<Wallet?>,
        customStartDate: Binding<Date>,
        customEndDate: Binding<Date>,
        wallets: [Wallet],
        defaultPeriod: Period? = nil,
        showWalletFilter: Bool = true,
        showPeriodFilter: Bool = true, // New parameter
        @ViewBuilder extraContent: @escaping () -> Content
    ) {
        self._selectedPeriod = selectedPeriod
        self._selectedWallet = selectedWallet
        self._customStartDate = customStartDate
        self._customEndDate = customEndDate
        self.wallets = wallets
        self.defaultPeriod = defaultPeriod
        self.showWalletFilter = showWalletFilter
        self.showPeriodFilter = showPeriodFilter
        self.extraContent = extraContent
    }
}

// MARK: - Generic Support

extension FilterSheetButton where Content == EmptyView {
    init(
        selectedPeriod: Binding<Period>,
        selectedWallet: Binding<Wallet?>,
        customStartDate: Binding<Date>,
        customEndDate: Binding<Date>,
        wallets: [Wallet],
        defaultPeriod: Period? = nil,
        showWalletFilter: Bool = true,
        showPeriodFilter: Bool = true // New parameter
    ) {
        self._selectedPeriod = selectedPeriod
        self._selectedWallet = selectedWallet
        self._customStartDate = customStartDate
        self._customEndDate = customEndDate
        self.wallets = wallets
        self.defaultPeriod = defaultPeriod
        self.showWalletFilter = showWalletFilter
        self.showPeriodFilter = showPeriodFilter
        self.extraContent = { EmptyView() }
    }
}
