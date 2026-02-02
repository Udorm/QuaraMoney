import SwiftUI
import SwiftData
import Charts

struct BudgetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let budget: Budget
    let transactions: [Transaction]
    
    @State private var showEditBudget = false
    @State private var transactionToEdit: Transaction?
    
    private var preferredCurrency: String {
        CurrencyManager.shared.preferredCurrencyCode
    }
    
    /// Transactions relevant to this budget (filtered by category, month, year, expense type)
    private var relevantTransactions: [Transaction] {
        guard let categoryId = budget.category?.id else { return [] }
        
        let calendar = Calendar.current
        
        return transactions.filter { txn in
            guard txn.type == .expense,
                  let txnCategoryId = txn.category?.id,
                  txnCategoryId == categoryId else {
                return false
            }
            
            let txnMonth = calendar.component(.month, from: txn.date)
            let txnYear = calendar.component(.year, from: txn.date)
            
            return txnMonth == budget.month && txnYear == budget.year
        }.sorted { $0.date > $1.date }
    }
    
    /// Total spending converted to preferred currency
    private var totalSpent: Decimal {
        relevantTransactions.reduce(Decimal.zero) { total, txn in
            let converted = CurrencyManager.shared.convert(
                amount: txn.amount,
                from: txn.currencyCode,
                to: preferredCurrency
            )
            return total + converted
        }
    }
    
    /// Budget limit converted to preferred currency
    private var budgetLimitConverted: Decimal {
        CurrencyManager.shared.convert(
            amount: budget.amountLimit,
            from: budget.currencyCode,
            to: preferredCurrency
        )
    }
    
    /// Remaining amount
    private var remaining: Decimal {
        budgetLimitConverted - totalSpent
    }
    
    /// Progress ratio (0.0 to 1.0+)
    private var progress: Double {
        guard budgetLimitConverted > 0 else { return 0 }
        return Double(truncating: totalSpent as NSNumber) / Double(truncating: budgetLimitConverted as NSNumber)
    }
    
    private var isOverBudget: Bool {
        totalSpent > budgetLimitConverted
    }
    
    private var progressColor: Color {
        if isOverBudget {
            return ThemeManager.shared.expenseColor
        } else if progress > 0.8 {
            return .orange
        } else {
            return ThemeManager.shared.incomeColor
        }
    }
    
    var body: some View {
        List {
            // MARK: - Header Section with Donut Chart
            Section {
                VStack(spacing: 24) {
                    // Header Info
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(budget.category?.name ?? "Unknown Category")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("\(Calendar.current.monthSymbols[budget.month - 1]) \(String(budget.year))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if let category = budget.category {
                            Image(systemName: category.icon)
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(progressColor.gradient)
                                .clipShape(Circle())
                                .shadow(color: progressColor.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                    }
                    .padding(.horizontal, 4)
                    
                    // Donut Chart
                    ZStack {
                        Chart {
                            if isOverBudget {
                                SectorMark(
                                    angle: .value("Spent", 100),
                                    innerRadius: .ratio(0.65),
                                    angularInset: 2
                                )
                                .foregroundStyle(ThemeManager.shared.expenseColor.gradient)
                            } else {
                                SectorMark(
                                    angle: .value("Spent", totalSpent),
                                    innerRadius: .ratio(0.65),
                                    angularInset: 2
                                )
                                .foregroundStyle(progressColor.gradient)
                                .cornerRadius(4)
                                
                                SectorMark(
                                    angle: .value("Remaining", max(0, remaining)),
                                    innerRadius: .ratio(0.65),
                                    angularInset: 2
                                )
                                .foregroundStyle(Color(.systemGray5))
                                .cornerRadius(4)
                            }
                        }
                        .frame(height: 220)
                        
                        // Center Label
                        VStack(spacing: 4) {
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(isOverBudget ? ThemeManager.shared.expenseColor : .primary)
                            
                            Text(isOverBudget ? "Over Budget" : "Used")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
            
            // MARK: - Summary Section
            Section("Summary") {
                HStack {
                    Text("Budget Limit")
                    Spacer()
                    Text(budgetLimitConverted.formatted(.currency(code: preferredCurrency)))
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Spent")
                    Spacer()
                    Text(totalSpent.formatted(.currency(code: preferredCurrency)))
                        .foregroundStyle(isOverBudget ? ThemeManager.shared.expenseColor : .primary)
                }
                
                HStack {
                    Text("Remaining")
                    Spacer()
                    Text(remaining.formatted(.currency(code: preferredCurrency)))
                        .foregroundStyle(remaining >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor)
                        .fontWeight(.medium)
                }
                
                if budget.currencyCode != preferredCurrency {
                    HStack {
                        Text("Original Budget")
                        Spacer()
                        Text(budget.amountLimit.formatted(.currency(code: budget.currencyCode)))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            
            // MARK: - Transactions Section (using shared component)
            if relevantTransactions.isEmpty {
                Section("Transactions (0)") {
                    Text("No transactions yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            } else {
                TransactionListView(
                    transactions: relevantTransactions,
                    onEdit: { txn in
                        transactionToEdit = txn
                    },
                    onDelete: { txn in
                        deleteTransaction(txn)
                    }
                )
            }
        }
        .navigationTitle("Budget Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditBudget = true
                } label: {
                    Text("Edit")
                }
            }
        }
        .sheet(isPresented: $showEditBudget) {
            EditBudgetView(budget: budget)
        }
        .sheet(item: $transactionToEdit) { txn in
            AddTransactionView(
                viewModel: AddTransactionViewModel(
                    dataService: SwiftDataService(modelContext: modelContext),
                    transaction: txn
                ),
                isNewTransaction: false
            )
        }
    }
    
    private func deleteTransaction(_ transaction: Transaction) {
        withAnimation {
            modelContext.delete(transaction)
        }
    }
}

#Preview {
    @Previewable @State var budget = Budget(amountLimit: 500, currencyCode: "USD", category: nil, month: 2, year: 2026)
    
    NavigationStack {
        BudgetDetailView(budget: budget, transactions: [])
    }
    .modelContainer(for: [Budget.self, Transaction.self, Category.self], inMemory: true)
}
