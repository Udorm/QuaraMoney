import SwiftUI
import SwiftData

/// A reusable component for displaying transactions grouped by date
/// with edit/delete capabilities and daily aggregate totals.
struct TransactionListView: View {
    let transactions: [Transaction]
    let onEdit: (Transaction) -> Void
    let onDelete: (Transaction) -> Void
    
    /// Groups transactions by date
    private var dailySections: [DailySection] {
        let targetCurrency = CurrencyManager.shared.preferredCurrencyCode
        
        // Group by day
        let grouped = Dictionary(grouping: transactions) { txn -> Date in
            Calendar.current.startOfDay(for: txn.date)
        }
        
        let sortedKeys = grouped.keys.sorted(by: >)
        
        return sortedKeys.map { date in
            let txns = grouped[date] ?? []
            
            // Calculate daily net flow (income positive, expense negative)
            let dailyFlow = txns.reduce(Decimal.zero) { result, txn in
                let amountInTarget = CurrencyManager.shared.convert(
                    amount: txn.amount,
                    from: txn.currencyCode,
                    to: targetCurrency
                )
                
                if txn.type == .income { return result + amountInTarget }
                if txn.type == .expense { return result - amountInTarget }
                return result // transfer is neutral
            }
            
            return DailySection(date: date, transactions: txns, dailyTotal: dailyFlow)
        }
    }
    
    var body: some View {
        if transactions.isEmpty {
            Text("No transactions")
                .foregroundStyle(.secondary)
        } else {
            ForEach(dailySections) { section in
                Section(header: DailySectionHeader(section: section)) {
                    ForEach(section.transactions) { txn in
                        Button {
                            onEdit(txn)
                        } label: {
                            TransactionRowView(transaction: txn)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                onDelete(txn)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            Button {
                                onEdit(txn)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                onEdit(txn)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                onDelete(txn)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Types

/// Represents a group of transactions for a single day
struct DailySection: Identifiable {
    let id = UUID()
    let date: Date
    let transactions: [Transaction]
    let dailyTotal: Decimal
}

/// Header view for a daily section showing date and aggregate total
struct DailySectionHeader: View {
    let section: DailySection
    
    var body: some View {
        HStack {
            Text(section.date, style: .date)
                .font(.headline)
            Spacer()
            Text(section.dailyTotal.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode)))
                .font(.subheadline)
                .foregroundStyle(section.dailyTotal >= 0 ? .green : .red)
        }
        .padding(.vertical, 4)
    }
}
