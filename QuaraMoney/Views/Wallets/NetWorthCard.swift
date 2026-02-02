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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.blue)
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Circle())
                
                Text("Total Net Worth")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            
            Text(totalNetWorth.formatted(.currency(code: currencyManager.preferredCurrencyCode)))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .foregroundStyle(totalNetWorth >= 0 ? Color.primary : ThemeManager.shared.expenseColor)
        }
        .padding(20)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.vertical, 8)
    }
}

#Preview {
    NetWorthCard(wallets: [])
}
