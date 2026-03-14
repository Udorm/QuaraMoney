import SwiftUI

struct NetWorthCard: View {
    let wallets: [Wallet]
    @ObservedObject private var currencyManager = CurrencyManager.shared
    
    var totalNetWorth: Decimal {
        wallets.reduce(0) { total, wallet in
            total + currencyManager.convert(
                amount: wallet.balance,
                from: wallet.currencyCode,
                to: currencyManager.preferredCurrencyCode
            )
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.Wallet.netWorth)
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            
            Text(totalNetWorth.formattedAmount(for: currencyManager.preferredCurrencyCode))
                .font(.app(.title2, weight: .bold))
                .contentTransition(.numericText())
                .foregroundStyle(totalNetWorth >= 0 ? Color.primary : ThemeManager.shared.expenseColor)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Net worth, \(totalNetWorth.formattedAmount(for: currencyManager.preferredCurrencyCode))")
    }
}

#Preview {
    NetWorthCard(wallets: [])
}
