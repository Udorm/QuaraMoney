import SwiftUI

struct WalletRowView: View {
    let wallet: Wallet
    
    var body: some View {
        HStack {
            Image(systemName: wallet.icon)
                .font(.title2)
                .foregroundStyle(Color(hex: wallet.colorHex) ?? .blue)
                .frame(width: 40, height: 40)
                .background(Color(hex: wallet.colorHex)?.opacity(0.1) ?? .blue.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading) {
                Text(wallet.name)
                    .font(.headline)
                Text(wallet.currencyCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(wallet.balance.formatted(.currency(code: wallet.currencyCode)))
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(wallet.balance >= 0 ? Color.primary : ThemeManager.shared.expenseColor)
        }
    }
}


