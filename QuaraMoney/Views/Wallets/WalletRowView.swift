import SwiftUI

struct WalletRowView: View {
    let wallet: Wallet
    /// Bumped by the parent on `.dataDidUpdate` so the row re-renders and recomputes
    /// the (`@Transient`-cached) balance after transactions change elsewhere.
    var refreshToken: Int = 0

    // Cache theme color for performance
    private let expenseColor: Color

    init(wallet: Wallet, refreshToken: Int = 0) {
        self.wallet = wallet
        self.refreshToken = refreshToken
        self.expenseColor = ThemeManager.shared.expenseColor
    }
    
    var body: some View {
        HStack {
            Image(systemName: wallet.icon)
                .font(.app(.title2))
                .foregroundStyle(Color(hex: wallet.colorHex) ?? .blue)
                .frame(width: 40, height: 40)
                .background(Color(hex: wallet.colorHex)?.opacity(0.1) ?? .blue.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading) {
                Text(wallet.name)
                    .font(.app(.headline))
                Text(wallet.currencyCode)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(wallet.balance.formattedAmount(for: wallet.currencyCode))
                .font(.app(.body))
                .monospacedDigit()
                .foregroundStyle(wallet.balance >= 0 ? Color.primary : expenseColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(wallet.name) wallet, balance \(wallet.balance.formattedAmount(for: wallet.currencyCode))")
    }
}
