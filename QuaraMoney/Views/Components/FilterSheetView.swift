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
    @Binding var selectedWalletIds: Set<UUID>
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    @Binding var isPresented: Bool

    var wallets: [Wallet]
    var showWalletFilter: Bool = true
    var showPeriodFilter: Bool = true
    var onApply: (() -> Void)?
    var extraContent: Content

    // Local state for pending selections (not applied until Done)
    @State private var pendingPeriod: Period
    @State private var pendingWalletIds: Set<UUID>
    @State private var pendingStartDate: Date
    @State private var pendingEndDate: Date

    // Track if custom period is selected to show date pickers
    private var isCustomPeriodSelected: Bool {
        pendingPeriod.displayName == L10n.Period.custom
    }

    init(
        selectedPeriod: Binding<Period>,
        selectedWalletIds: Binding<Set<UUID>>,
        customStartDate: Binding<Date>,
        customEndDate: Binding<Date>,
        isPresented: Binding<Bool>,
        wallets: [Wallet],
        showWalletFilter: Bool = true,
        showPeriodFilter: Bool = true,
        onApply: (() -> Void)? = nil,
        @ViewBuilder extraContent: () -> Content
    ) {
        self._selectedPeriod = selectedPeriod
        self._selectedWalletIds = selectedWalletIds
        self._customStartDate = customStartDate
        self._customEndDate = customEndDate
        self._isPresented = isPresented
        self.wallets = wallets
        self.showWalletFilter = showWalletFilter
        self.showPeriodFilter = showPeriodFilter
        self.onApply = onApply
        self.extraContent = extraContent()

        // Initialize pending state with current values
        self._pendingPeriod = State(initialValue: selectedPeriod.wrappedValue)
        self._pendingWalletIds = State(initialValue: selectedWalletIds.wrappedValue)
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
                            SelectableRow(
                                title: period.displayName,
                                icon: getIcon(for: period),
                                isSelected: (pendingPeriod as AnyHashable) == (period as AnyHashable)
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    pendingPeriod = period
                                }
                            }
                        }
                    } header: {
                        Text("filter.period".localized)
                            .appFont(.caption)
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
                        .appFont(.body)
                        
                        DatePicker(
                            "filter.endDate".localized,
                            selection: $pendingEndDate,
                            in: pendingStartDate...,
                            displayedComponents: .date
                        )
                        .appFont(.body)
                    } header: {
                        Text(L10n.Wallet.customRange)
                            .appFont(.caption)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // MARK: - Wallet Section
                if showWalletFilter {
                    Section {
                        // All Wallets option
                        SelectableRow(
                            title: "filter.allWallets".localized,
                            icon: "square.stack.3d.up",
                            isSelected: pendingWalletIds.isEmpty,
                            selectionStyle: .circleCheckmark
                        ) {
                            pendingWalletIds = []
                        }

                        // Individual wallets
                        ForEach(wallets) { wallet in
                            SelectableRow(
                                title: wallet.name,
                                icon: wallet.icon.isEmpty ? "creditcard" : wallet.icon,
                                iconColor: Color(hex: wallet.colorHex) ?? .blue,
                                isSelected: pendingWalletIds.contains(wallet.id),
                                selectionStyle: .circleCheckmark
                            ) {
                                if pendingWalletIds.contains(wallet.id) {
                                    pendingWalletIds.remove(wallet.id)
                                } else {
                                    pendingWalletIds.insert(wallet.id)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("filter.wallet".localized)
                                .appFont(.caption)
                            Spacer()
                            if !pendingWalletIds.isEmpty {
                                Text("analysis.pro.filter.nSelected".localized(with: pendingWalletIds.count))
                                    .appFont(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
        selectedWalletIds = pendingWalletIds
        customStartDate = pendingStartDate
        customEndDate = pendingEndDate
        onApply?()
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

// MARK: - Filter Sheet Button (Toolbar Button)

/// A toolbar button that opens the filter sheet.
/// Use this in your toolbar to provide consistent filter access.
struct FilterSheetButton<Period: Hashable & Identifiable & CaseIterable & LocalizableDisplayName, Content: View>: View {
    @Binding var selectedPeriod: Period
    @Binding var selectedWalletIds: Set<UUID>
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    var wallets: [Wallet]
    var showWalletFilter: Bool = true
    var showPeriodFilter: Bool = true
    var defaultPeriod: Period? = nil
    var onApply: (() -> Void)?
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

        let isWalletActive = showWalletFilter ? !selectedWalletIds.isEmpty : false
        let isCustomPeriod = showPeriodFilter && selectedPeriod.displayName == L10n.Period.custom

        return isPeriodActive || isWalletActive || isCustomPeriod
    }

    var body: some View {
        Button {
            showFilterSheet = true
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .symbolVariant(isFilterActive ? .fill : .none)
                .appFont(.title3)
                // Only show blue if filter is active (not default)
                // User req: "The filter button should not show the blue shine that indicate that not default option are selected when the default option are selected"
                .foregroundStyle(isFilterActive ? .blue : .primary)
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheetView(
                selectedPeriod: $selectedPeriod,
                selectedWalletIds: $selectedWalletIds,
                customStartDate: $customStartDate,
                customEndDate: $customEndDate,
                isPresented: $showFilterSheet,
                wallets: wallets,
                showWalletFilter: showWalletFilter,
                showPeriodFilter: showPeriodFilter,
                onApply: onApply,
                extraContent: extraContent
            )
        }
    }

    init(
        selectedPeriod: Binding<Period>,
        selectedWalletIds: Binding<Set<UUID>>,
        customStartDate: Binding<Date>,
        customEndDate: Binding<Date>,
        wallets: [Wallet],
        defaultPeriod: Period? = nil,
        showWalletFilter: Bool = true,
        showPeriodFilter: Bool = true,
        onApply: (() -> Void)? = nil,
        @ViewBuilder extraContent: @escaping () -> Content
    ) {
        self._selectedPeriod = selectedPeriod
        self._selectedWalletIds = selectedWalletIds
        self._customStartDate = customStartDate
        self._customEndDate = customEndDate
        self.wallets = wallets
        self.defaultPeriod = defaultPeriod
        self.showWalletFilter = showWalletFilter
        self.showPeriodFilter = showPeriodFilter
        self.onApply = onApply
        self.extraContent = extraContent
    }
}

// MARK: - Generic Support

extension FilterSheetButton where Content == EmptyView {
    init(
        selectedPeriod: Binding<Period>,
        selectedWalletIds: Binding<Set<UUID>>,
        customStartDate: Binding<Date>,
        customEndDate: Binding<Date>,
        wallets: [Wallet],
        defaultPeriod: Period? = nil,
        showWalletFilter: Bool = true,
        showPeriodFilter: Bool = true,
        onApply: (() -> Void)? = nil
    ) {
        self._selectedPeriod = selectedPeriod
        self._selectedWalletIds = selectedWalletIds
        self._customStartDate = customStartDate
        self._customEndDate = customEndDate
        self.wallets = wallets
        self.defaultPeriod = defaultPeriod
        self.showWalletFilter = showWalletFilter
        self.showPeriodFilter = showPeriodFilter
        self.onApply = onApply
        self.extraContent = { EmptyView() }
    }
}
