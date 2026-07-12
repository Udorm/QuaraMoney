import SwiftUI

/// Protocol for periods that have localized display names
protocol LocalizableDisplayName {
    var displayName: String { get }
}

extension FilterPeriod: LocalizableDisplayName {}
extension AnalysisPeriod: LocalizableDisplayName {}

/// NOTE: SwiftUI Menu uses UIKit's UIMenu under the hood.
/// iOS does NOT allow custom fonts in UIMenu items - this is a platform limitation.
/// The menu text will use the system font regardless of any .font() modifiers applied.
/// This is the same behavior in all iOS apps using native Menu components.
struct FilterMenuView<Period: Hashable & Identifiable & CaseIterable & LocalizableDisplayName>: View {
    @Binding var selectedPeriod: Period
    @Binding var selectedWallet: Wallet?
    var wallets: [Wallet]
    var showWalletFilter: Bool = true
    
    // Action to trigger when custom period is selected
    var onCustomPeriodSelect: () -> Void
    
    // Check if filter is active for UI state
    var isFilterActive: Bool {
        // We assume the first case is the default "This Month" or similar standard
        let isDefaultPeriod = selectedPeriod as AnyHashable == Array(Period.allCases).first as AnyHashable
        // If wallet filter is hidden, only check period. If shown, check both.
        let isWalletActive = showWalletFilter ? (selectedWallet != nil) : false
        return !isDefaultPeriod || isWalletActive
    }
    
    var body: some View {
        Menu {
            Section("filter.period".localized) {
                ForEach(Array(Period.allCases)) { period in
                    Button {
                        if period.displayName == L10n.Period.custom {
                            onCustomPeriodSelect()
                        } else {
                            selectedPeriod = period
                        }
                    } label: {
                        Label(period.displayName, systemImage: (selectedPeriod as AnyHashable) == (period as AnyHashable) ? "checkmark" : getIcon(for: period))
                    }
                }
            }
            
            if showWalletFilter {
                Section("filter.wallet".localized) {
                    Button {
                        selectedWallet = nil
                    } label: {
                        Label("filter.allWallets".localized, systemImage: selectedWallet == nil ? "checkmark" : "square.stack.3d.up")
                    }
                    
                    ForEach(wallets) { wallet in
                        Button {
                            selectedWallet = wallet
                        } label: {
                            Label(wallet.name, systemImage: selectedWallet?.id == wallet.id ? "checkmark" : (wallet.icon.isEmpty ? "creditcard" : wallet.icon))
                        }
                    }
                }
            }
        } label: {
            Image(systemName: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .appFont(.title3)
                .foregroundStyle(isFilterActive ? .blue : .primary)
        }
    }
    
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
