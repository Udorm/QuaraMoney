import SwiftUI
import SwiftData

struct EventDetailView: View {
    let event: Event
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingAddTransaction = false
    @State private var transactionToEdit: Transaction?
    @State private var showingEditEvent = false
    
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
    
    private var eventColor: Color {
        Color(hex: event.colorHex) ?? .blue
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - Header Card
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(eventColor.opacity(0.1))
                            .frame(width: 80, height: 80)
                        Image(systemName: event.icon)
                            .font(.system(size: 32))
                            .foregroundStyle(eventColor)
                    }
                    
                    VStack(spacing: 8) {
                        Text(event.title)
                            .font(.app(.title2, weight: .bold))
                            .multilineTextAlignment(.center)
                        
                        if let location = event.location {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .font(.app(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                        
                        Text(formatDateRange(start: event.startDate, end: event.endDate))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(20)
                    }
                    
                    if let notes = event.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.app(.body))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // MARK: - Stats Section
                if let budget = event.totalBudget {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Budget Overview")
                            .font(.app(.headline))
                            .padding(.horizontal)
                        
                        VStack(spacing: 16) {
                            // Progress Bar
                            BudgetProgressView(
                                budget: budget,
                                spent: spentAmount,
                                currencyCode: displayCurrency
                            )
                            
                            Divider()
                            
                            // Stats Grid
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                StatItemView(
                                    title: "Spent",
                                    value: spentAmount.formatted(.currency(code: displayCurrency)),
                                    color: .primary
                                )
                                
                                StatItemView(
                                    title: "Remaining",
                                    value: (budget - spentAmount).formatted(.currency(code: displayCurrency)),
                                    color: spentAmount > budget ? .red : .green
                                )
                                
                                StatItemView(
                                    title: "Budget",
                                    value: budget.formatted(.currency(code: displayCurrency)),
                                    color: .secondary
                                )
                                
                                if let days = daysElapsed, days > 0 {
                                    StatItemView(
                                        title: "Daily Avg",
                                        value: (spentAmount / Decimal(days)).formatted(.currency(code: displayCurrency)),
                                        color: .secondary
                                    )
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }
                } else {
                    // Just total spent if no budget
                    VStack(spacing: 8) {
                        Text("Total Spent")
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                        Text(spentAmount.formatted(.currency(code: displayCurrency)))
                            .font(.app(.title, weight: .bold))
                            .foregroundStyle(eventColor)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)
                }
                
                // MARK: - Transactions List
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Transactions")
                            .font(.app(.headline))
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    if transactions.isEmpty {
                        Text("No transactions yet")
                            .font(.app(.body))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(transactions) { transaction in
                                TransactionRowView(transaction: transaction)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        transactionToEdit = transaction
                                    }
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Button {
                        showingEditEvent = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    
                    Button {
                        showingAddTransaction = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditEvent) {
            AddEventView(eventToEdit: event)
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
    }
    
    private func formatDateRange(start: Date, end: Date?) -> String {
        if let end = end {
            if Calendar.current.isDate(start, inSameDayAs: end) {
                return start.formatted(date: .long, time: .shortened) + " - " + end.formatted(date: .omitted, time: .shortened)
            } else {
                return start.formatted(date: .abbreviated, time: .omitted) + " - " + end.formatted(date: .abbreviated, time: .omitted)
            }
        }
        return start.formatted(date: .long, time: .shortened)
    }
    
    private var daysElapsed: Int? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: event.startDate)
        let end = event.endDate ?? Date() // If active, calculate till today
        let components = calendar.dateComponents([.day], from: start, to: end)
        return max(1, components.day ?? 1)
    }
}

struct StatItemView: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Reuse BudgetProgressView but make sure it fits the new style
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
        if progress > 0.9 { return .orange }
        return .green
    }
    
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 12)
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(progressColor)
                        .frame(width: min(CGFloat(progress) * geometry.size.width, geometry.size.width), height: 12)
                }
            }
            .frame(height: 12)
            
            HStack {
                Text(L10n.Event.spent(Int(min(progress, 1.0) * 100)))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.app(.caption, weight: .bold))
                    .foregroundStyle(progressColor)
            }
        }
    }
}
