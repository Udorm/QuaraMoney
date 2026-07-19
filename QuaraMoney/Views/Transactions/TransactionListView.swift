import SwiftUI
import SwiftData

/// A reusable component for displaying transactions grouped by date
/// with edit/delete capabilities and daily aggregate totals.
struct TransactionListView: View {
    let transactions: [Transaction]
    var sortOption: TransactionSortOption = .newestFirst
    var listHeader: String? = nil // Optional top-level header
    var unconvertedTransactionIDs: Set<UUID> = []
    let onEdit: (Transaction) -> Void
    let onDelete: (Transaction) -> Void
    
    /// Groups transactions by date using shared TransactionProcessor
    private var dailySections: [DailyTransactionSection] {
        TransactionProcessor.groupByDayObjects(
            transactions,
            rates: CurrencyManager.shared.rates,
            targetCurrency: CurrencyManager.shared.preferredCurrencyCode,
            sortAscending: sortOption == .oldestFirst
        )
    }
    
    var body: some View {
        if transactions.isEmpty {
            Text(L10n.Budget.noTransactions)
                .foregroundStyle(.secondary)
        } else if sortOption == .highestAmount || sortOption == .lowestAmount {
            if let listHeader, !listHeader.isEmpty {
                Section(header:
                    Text(listHeader)
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                ) {
                    ForEach(transactions) { txn in
                        Button {
                            onEdit(txn)
                        } label: {
                            TransactionRowView(transaction: txn, showsUnconvertedHint: unconvertedTransactionIDs.contains(txn.id))
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
                                    .appFont(.body)
                            }
                            Button(role: .destructive) {
                                HapticManager.shared.impact(style: .medium)
                                onDelete(txn)
                            } label: {
                                Label(L10n.Common.delete, systemImage: "trash")
                                    .appFont(.body)
                            }
                        }
                    }
                }
            } else {
                ForEach(transactions) { txn in
                    Button {
                        onEdit(txn)
                    } label: {
                        TransactionRowView(transaction: txn, showsUnconvertedHint: unconvertedTransactionIDs.contains(txn.id))
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
                                .appFont(.body)
                        }
                        Button(role: .destructive) {
                            HapticManager.shared.impact(style: .medium)
                            onDelete(txn)
                        } label: {
                            Label(L10n.Common.delete, systemImage: "trash")
                                .appFont(.body)
                        }
                    }
                }
            }
        } else {
            ForEach(Array(dailySections.enumerated()), id: \.element.id) { index, section in
                Section(header: 
                    VStack(alignment: .leading, spacing: 4) {
                        if index == 0, let listHeader, !listHeader.isEmpty {
                            Text(listHeader)
                                .appFont(.subheadline)
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
                            TransactionRowView(transaction: txn, showsUnconvertedHint: unconvertedTransactionIDs.contains(txn.id))
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
                                    .appFont(.body)
                            }
                            Button(role: .destructive) {
                                HapticManager.shared.impact(style: .medium)
                                onDelete(txn)
                            } label: {
                                Label(L10n.Common.delete, systemImage: "trash")
                                    .appFont(.body)
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
            Text(section.date.appFormatted(date: .abbreviated))
                .appFont(.headline)
            Spacer()
            Text(section.dailyTotal.formattedAmount(for: currencyCode))
                .appFont(.subheadline)
                .foregroundStyle(section.dailyTotal >= 0 ? incomeColor : expenseColor)
        }
        .padding(.vertical, 4)
    }
}
