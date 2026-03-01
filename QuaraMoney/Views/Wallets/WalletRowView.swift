import SwiftUI

struct WalletRowView: View {
    let wallet: Wallet
    
    // Cache theme color for performance
    private let expenseColor: Color
    
    init(wallet: Wallet) {
        self.wallet = wallet
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
    }
}
