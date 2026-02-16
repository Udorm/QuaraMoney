import SwiftUI

struct FinancialSummaryCards: View {
    let income: Decimal
    let expense: Decimal
    
    var net: Decimal {
        income - expense
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Net Total Section
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Analysis.net)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                    Text(net.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode).presentation(.narrow)))
                        .font(.app(.title2, weight: .bold))
                        .foregroundStyle(net >= 0 ? Color.primary : .red)
                }
                
                Spacer()
                
                Image(systemName: "leaf.fill")
                    .font(.app(.title2))
                    .foregroundStyle(Color.accentColor)
                    .padding(10)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Circle())
            }
            
            Divider()
            
            // Income & Expense Row
            HStack(spacing: 0) {
                // Income
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "arrow.down.left")
                            .font(.app(.caption, weight: .bold))
                            .foregroundStyle(ThemeManager.shared.incomeColor)
                        Text(L10n.Transaction.TransactionType.income)
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(income.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode).presentation(.narrow)))
                        .font(.app(.headline))
                        .foregroundStyle(ThemeManager.shared.incomeColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                    .frame(height: 30) // Vertical divider
                    .padding(.horizontal, 16)
                
                // Expense
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "arrow.up.right")
                            .font(.app(.caption, weight: .bold))
                            .foregroundStyle(ThemeManager.shared.expenseColor)
                        Text(L10n.Transaction.TransactionType.expense)
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(expense.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode).presentation(.narrow)))
                        .font(.app(.headline))
                        .foregroundStyle(ThemeManager.shared.expenseColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    List {
        Section {
            FinancialSummaryCards(income: 5000, expense: 3200)
        }
    }
}
