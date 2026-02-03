import SwiftUI
import SwiftData

/// A reusable component for displaying transactions grouped by date
/// with edit/delete capabilities and daily aggregate totals.
struct TransactionListView: View {
    let transactions: [Transaction]
    let onEdit: (Transaction) -> Void
    let onDelete: (Transaction) -> Void
    
    /// Groups transactions by date using shared TransactionProcessor
    private var dailySections: [DailyTransactionSection] {
        TransactionProcessor.groupByDay(transactions)
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

/// Header view for a daily section showing date and aggregate total
struct DailySectionHeader: View {
    let section: DailyTransactionSection
    
    // Cache singleton values for performance
    private let currencyCode: String
    private let incomeColor: Color
    private let expenseColor: Color
    
    init(section: DailyTransactionSection) {
        self.section = section
        self.currencyCode = CurrencyManager.shared.preferredCurrencyCode
        self.incomeColor = ThemeManager.shared.incomeColor
        self.expenseColor = ThemeManager.shared.expenseColor
    }
    
    var body: some View {
        HStack {
            Text(section.date, style: .date)
                .font(.headline)
            Spacer()
            Text(section.dailyTotal.formatted(.currency(code: currencyCode)))
                .font(.subheadline)
                .foregroundStyle(section.dailyTotal >= 0 ? incomeColor : expenseColor)
        }
        .padding(.vertical, 4)
    }
}
