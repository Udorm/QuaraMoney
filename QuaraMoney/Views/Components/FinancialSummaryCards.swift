import SwiftUI

struct FinancialSummaryCards: View {
    let income: Decimal
    let expense: Decimal
    
    var net: Decimal {
        income - expense
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Row 1: Net (Full Width)
            FinancialCard(
                title: "Net",
                amount: net,
                color: net >= 0 ? .blue : .red, // Blue for positive net to distinguish from income
                icon: "leaf.fill",
                isLarge: true
            )
            
            // Row 2: Income and Expense (Side by Side)
            HStack(spacing: 12) {
                FinancialCard(
                    title: "Income",
                    amount: income,
                    color: ThemeManager.shared.incomeColor,
                    icon: "arrow.down.left", // Matching HomeView icon, Analysis used arrow.down
                    isLarge: false
                )
                
                FinancialCard(
                    title: "Expense",
                    amount: expense,
                    color: ThemeManager.shared.expenseColor,
                    icon: "arrow.up.right", // Matching HomeView icon, Analysis used arrow.up
                    isLarge: false
                )
            }
        }
    }
}

private struct FinancialCard: View {
    let title: String
    let amount: Decimal
    let color: Color
    let icon: String
    let isLarge: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(isLarge ? .title3 : .headline)
                    .foregroundStyle(color)
                    .padding(8)
                    .background(color.opacity(0.1))
                    .clipShape(Circle())
                
                Spacer()
                
                if isLarge {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }
            
            if !isLarge {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            
            Text(amount.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode)))
                .font(.system(isLarge ? .title2 : .headline, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
        
        FinancialSummaryCards(income: 5000, expense: 3200)
            .padding()
    }
}
