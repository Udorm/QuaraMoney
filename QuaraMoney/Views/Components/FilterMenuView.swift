import SwiftUI

struct FilterMenuView<Period: Hashable & Identifiable & RawRepresentable & CaseIterable>: View where Period.RawValue == String {
    @Binding var selectedPeriod: Period
    @Binding var selectedWallet: Wallet?
    var wallets: [Wallet]
    var showWalletFilter: Bool = true
    
    // Action to trigger when custom period is selected
    var onCustomPeriodSelect: () -> Void
    
    // Check if filter is active for UI state
    var isFilterActive: Bool {
        // We assume the first case is the default "This Month" or similar standard
        let isDefaultPeriod = selectedPeriod == Array(Period.allCases).first
        // If wallet filter is hidden, only check period. If shown, check both.
        let isWalletActive = showWalletFilter ? (selectedWallet != nil) : false
        return !isDefaultPeriod || isWalletActive
    }
    
    var body: some View {
        Menu {
            Section("Period") {
                ForEach(Array(Period.allCases)) { period in
                    Button {
                        if period.rawValue == "Custom" {
                            onCustomPeriodSelect()
                        } else {
                            selectedPeriod = period
                        }
                    } label: {
                        HStack {
                            Text(period.rawValue)
                            Spacer()
                            if selectedPeriod == period {
                                Image(systemName: "checkmark")
                            } else {
                                Image(systemName: getIcon(for: period))
                            }
                        }
                    }
                }
            }
            
            if showWalletFilter {
                Section("Wallet") {
                    Button {
                        selectedWallet = nil
                    } label: {
                        HStack {
                            Text("All Wallets")
                            Spacer()
                            if selectedWallet == nil {
                                Image(systemName: "checkmark")
                            } else {
                                Image(systemName: "square.stack.3d.up")
                            }
                        }
                    }
                    
                    ForEach(wallets) { wallet in
                        Button {
                            selectedWallet = wallet
                        } label: {
                            HStack {
                                Text(wallet.name)
                                Spacer()
                                if selectedWallet?.id == wallet.id {
                                    Image(systemName: "checkmark")
                                } else {
                                    // Use wallet icon if available, fallback to creditcard
                                    Image(systemName: wallet.icon.isEmpty ? "creditcard" : wallet.icon)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.title3)
                .foregroundStyle(isFilterActive ? .blue : .primary)
        }
    }
    
    private func getIcon(for period: Period) -> String {
        switch period.rawValue {
        case "This Month": return "calendar"
        case "Last Month": return "clock.arrow.circlepath"
        case "This Year": return "calendar.badge.clock"
        case "All Time": return "infinity"
        case "Custom": return "calendar.badge.plus"
        default: return "calendar"
        }
    }
}
