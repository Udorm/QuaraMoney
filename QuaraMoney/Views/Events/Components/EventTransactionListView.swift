import SwiftUI

struct EventTransactionListView: View {
    let transactions: [EventLedgerTransaction]
    let linksByTransactionId: [UUID: [EventLedgerParticipant]]
    let memberById: [UUID: EventMember]
    let event: Event
    let onSelect: (EventLedgerTransaction) -> Void
    let onDelete: (EventLedgerTransaction) -> Void
    
    // Group transactions by date
    private var groupedTransactions: [(Date, [EventLedgerTransaction])] {
        let groups = Dictionary(grouping: transactions) { transaction in
            Calendar.current.startOfDay(for: transaction.date)
        }
        return groups.sorted { $0.key > $1.key }
    }
    
    // Helper to resolve name directly (simplified per user request)
    private func payerName(for transaction: EventLedgerTransaction) -> String {
        let payerIsBudgetPool = transaction.paidByMemberId.map { memberById[$0]?.isBudgetPool ?? false } ?? false
        
        if transaction.paidSource == .eventWallet || transaction.paidByMemberId == nil || payerIsBudgetPool {
            return "Event Wallet"
        }
        
        guard let payerId = transaction.paidByMemberId else { return "Unknown" }
        return memberById[payerId]?.name ?? "Unknown"
    }
    
    var body: some View {
        if transactions.isEmpty {
            Section {
                ContentUnavailableView(
                    "No Expenses Yet",
                    systemImage: "creditcard",
                    description: Text("Start tracking by adding an expense.")
                )
                .listRowBackground(Color.clear)
            }
        } else {
            ForEach(groupedTransactions, id: \.0) { date, txs in
                let dailyTotalMinor = txs.reduce(0) { sum, txn in
                    sum + (txn.kind == .contribution ? txn.amountMinor : -txn.amountMinor)
                }
                let dailyTotal = MoneyMinorUnitConverter.fromMinorUnits(dailyTotalMinor, currencyCode: event.currencyCode)
                
                Section(header: EventDailySectionHeader(date: date, total: dailyTotal, currencyCode: event.currencyCode)) {
                    ForEach(txs) { transaction in
                        Button {
                            onSelect(transaction)
                        } label: {
                            TransactionRowView(
                                eventTransaction: transaction,
                                paidByName: payerName(for: transaction),
                                participantCount: linksByTransactionId[transaction.id]?.count ?? 0,
                                currencyCode: event.currencyCode
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                HapticManager.shared.impact(style: .medium)
                                onDelete(transaction)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            Button {
                                onSelect(transaction)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                onSelect(transaction)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                HapticManager.shared.impact(style: .medium)
                                onDelete(transaction)
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

/// Mimics DailySectionHeader exactly as used in Home screen / TransactionListView
private struct EventDailySectionHeader: View {
    let date: Date
    let total: Decimal
    let currencyCode: String
    
    var body: some View {
        HStack {
            Text(date, style: .date)
                .font(.app(.headline))
                .textCase(nil) // Ensure natural casing
            Spacer()
            Text(total.formatted(.currency(code: currencyCode)))
                .font(.app(.subheadline))
                .foregroundStyle(total >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor)
        }
        .padding(.vertical, 4)
    }
}
