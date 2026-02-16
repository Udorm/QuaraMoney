import SwiftUI
import SwiftData

/// A reusable component for displaying transactions grouped by date
/// with edit/delete capabilities and daily aggregate totals.
struct TransactionListView: View {
    let transactions: [Transaction]
    var listHeader: String? = nil // Optional top-level header
    let onEdit: (Transaction) -> Void
    let onDelete: (Transaction) -> Void
    
    /// Groups transactions by date using shared TransactionProcessor
    private var dailySections: [DailyTransactionSection] {
        TransactionProcessor.groupByDayObjects(
            transactions,
            rates: CurrencyManager.shared.rates,
            targetCurrency: CurrencyManager.shared.preferredCurrencyCode
        )
    }
    
    var body: some View {
        if transactions.isEmpty {
            Text(L10n.Budget.noTransactions)
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(dailySections.enumerated()), id: \.element.id) { index, section in
                Section(header: 
                    VStack(alignment: .leading, spacing: 4) {
                        if index == 0, let listHeader, !listHeader.isEmpty {
                            Text(listHeader)
                                .font(.app(.subheadline))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 4)
                        }
                        DailySectionHeader(section: section)
                    }
                ) {
                    ForEach(section.transactions) { txn in
                        Button {
                            onEdit(txn)
                        } label: {
                            TransactionRowView(transaction: txn)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                HapticManager.shared.impact(style: .medium)
                                onDelete(txn)
                            } label: {
                                Label(L10n.Common.delete, systemImage: "trash")
                            }
                            
                            Button {
                                onEdit(txn)
                            } label: {
                                Label(L10n.Common.edit, systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                onEdit(txn)
                            } label: {
                                Label(L10n.Common.edit, systemImage: "pencil")
                                    .font(.app(.body))
                            }
                            Button(role: .destructive) {
                                HapticManager.shared.impact(style: .medium)
                                onDelete(txn)
                            } label: {
                                Label(L10n.Common.delete, systemImage: "trash")
                                    .font(.app(.body))
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
                .font(.app(.headline))
            Spacer()
            Text(section.dailyTotal.formatted(.currency(code: currencyCode)))
                .font(.app(.subheadline))
                .foregroundStyle(section.dailyTotal >= 0 ? incomeColor : expenseColor)
        }
        .padding(.vertical, 4)
    }
}
