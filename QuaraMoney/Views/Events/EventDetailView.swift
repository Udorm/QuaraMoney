import SwiftUI
import SwiftData

struct EventDetailView: View {
    let event: Event
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingAddTransaction = false
    @State private var transactionToEdit: Transaction?
    
    @Query private var transactions: [Transaction]
    
    init(event: Event) {
        self.event = event
        let eventId = event.id
        let predicate = #Predicate<Transaction> { txn in
            txn.event?.id == eventId
        }
        _transactions = Query(filter: predicate, sort: \Transaction.date, order: .reverse)
    }
    
    private var displayCurrency: String {
        CurrencyManager.shared.preferredCurrencyCode
    }
    
    private var spentAmount: Decimal {
        CurrencyManager.shared.calculateTotal(
            transactions: transactions,
            targetCurrency: displayCurrency
        )
    }
    
    var body: some View {
        List {
            // Event Info Section (without duplicate title)
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    // Date
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundStyle(.secondary)
                        Text(event.startDate.formatted(date: .long, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                    
                    // Notes
                    if let notes = event.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.body)
                    }
                    
                    // Budget visualization
                    if let budget = event.totalBudget {
                        BudgetProgressView(
                            budget: budget,
                            spent: spentAmount,
                            currencyCode: displayCurrency
                        )
                    }
                }
            }
            
            // Transactions Section with grouping
            TransactionListView(
                transactions: transactions,
                onEdit: { txn in
                    transactionToEdit = txn
                },
                onDelete: { txn in
                    deleteTransaction(txn)
                }
            )
        }
        .navigationTitle(event.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddTransaction = true }) {
                    Label("Add Transaction", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddTransaction) {
            AddTransactionView(
                viewModel: AddTransactionViewModel(
                    dataService: SwiftDataService(modelContext: modelContext),
                    initialEvent: event
                ),
                isNewTransaction: true
            )
        }
        .sheet(item: $transactionToEdit) { txn in
            AddTransactionView(
                viewModel: AddTransactionViewModel(
                    dataService: SwiftDataService(modelContext: modelContext),
                    initialEvent: event,
                    transaction: txn
                ),
                isNewTransaction: false
            )
        }
    }
    
    private func deleteTransaction(_ transaction: Transaction) {
        modelContext.delete(transaction)
        try? modelContext.save()
    }
}

// MARK: - Budget Progress View

/// Displays a visual progress bar comparing spent amount to budget
struct BudgetProgressView: View {
    let budget: Decimal
    let spent: Decimal
    let currencyCode: String
    
    private var progress: Double {
        guard budget > 0 else { return 0 }
        return Double(truncating: spent as NSNumber) / Double(truncating: budget as NSNumber)
    }
    
    private var progressColor: Color {
        if progress > 1.0 { return .red }
        if progress > 0.8 { return .orange }
        return .green
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            
            // Progress bar with labels
            HStack {
                Text("Budget")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(spent.formatted(.currency(code: currencyCode))) / \(budget.formatted(.currency(code: currencyCode)))")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: min(CGFloat(progress) * geometry.size.width, geometry.size.width), height: 8)
                }
            }
            .frame(height: 8)
            
            // Percentage label
            HStack {
                Text("\(Int(min(progress, 1.0) * 100))% spent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if spent > budget {
                    Text("Over budget by \((spent - budget).formatted(.currency(code: currencyCode)))")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("\((budget - spent).formatted(.currency(code: currencyCode))) remaining")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }
}
