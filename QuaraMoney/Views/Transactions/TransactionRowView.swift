import SwiftUI
import SwiftData

struct TransactionRowView: View {
    let transaction: Transaction
    let contextWallet: Wallet?
    
    // Cache theme colors for performance
    private let incomeColor: Color
    private let expenseColor: Color
    
    init(transaction: Transaction, contextWallet: Wallet? = nil) {
        self.transaction = transaction
        self.contextWallet = contextWallet
        self.incomeColor = ThemeManager.shared.incomeColor
        self.expenseColor = ThemeManager.shared.expenseColor
    }
    
    private var isPositive: Bool {
        if transaction.type == .income { return true }
        if transaction.type == .expense { return false }
        if transaction.type == .transfer {
            // If context is provided and matches destination, it's incoming money.
            if let context = contextWallet, let dest = transaction.destinationWallet, dest.id == context.id {
                return true
            }
            // Otherwise (Source or Global), treat as outgoing/neutral
            return false
        }
        return false
    }
    
    var body: some View {
        HStack {
            // Icon
            ZStack {
                Circle()
                    .fill(Color(hex: transaction.category?.colorHex ?? "#8E8E93")?.opacity(0.1) ?? .gray.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: transaction.category?.icon ?? (transaction.type == .income ? "arrow.down.circle.fill" : (transaction.type == .transfer ? "arrow.left.arrow.right" : "arrow.up.circle.fill")))
                    .font(.body)
                    .foregroundStyle(Color(hex: transaction.category?.colorHex ?? "#8E8E93") ?? .gray)
            }
            
            VStack(alignment: .leading) {
                Text(transaction.category?.name ?? (transaction.type == .transfer ? "Transfer" : (transaction.note ?? "Uncategorized")))
                    .font(.body)
                    .fontWeight(.medium)
                
                if let note = transaction.note, !note.isEmpty {
                     Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text("\(isPositive ? "+" : "-")\(transaction.amount.formatted(.currency(code: transaction.currencyCode)))")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(isPositive ? incomeColor : expenseColor)
                
                Text(transaction.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
