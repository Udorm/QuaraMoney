import SwiftUI
import SwiftData

struct BudgetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Budget.year, order: .reverse), SortDescriptor(\Budget.month, order: .reverse)]) private var budgets: [Budget]
    @Query private var transactions: [Transaction]
    @State private var showAddBudget = false
    
    private var preferredCurrency: String {
        CurrencyManager.shared.preferredCurrencyCode
    }
    
    var body: some View {
        Group {
            if budgets.isEmpty {
                ContentUnavailableView(
                    "No Budgets",
                    systemImage: "chart.bar",
                    description: Text("Set up a budget to track your spending habits.")
                )
            } else {
                List {
                    ForEach(budgets) { budget in
                        NavigationLink(destination: BudgetDetailView(budget: budget, transactions: transactions)) {
                            BudgetRowView(
                                budget: budget,
                                spent: calculateSpending(for: budget),
                                budgetLimitConverted: convertBudgetLimit(for: budget)
                            )
                        }
                    }
                    .onDelete(perform: deleteBudgets)
                }
            }
        }
        .navigationTitle("Budgets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddBudget = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddBudget) {
            AddBudgetView()
        }
    }
    
    /// Calculate spending for a budget by filtering transactions and converting to preferred currency
    private func calculateSpending(for budget: Budget) -> Decimal {
        guard let categoryId = budget.category?.id else { return 0 }
        
        let calendar = Calendar.current
        
        // Filter transactions for this budget's category, month, year, and expense type
        let relevantTransactions = transactions.filter { txn in
            guard txn.type == .expense,
                  let txnCategoryId = txn.category?.id,
                  txnCategoryId == categoryId else {
                return false
            }
            
            let txnMonth = calendar.component(.month, from: txn.date)
            let txnYear = calendar.component(.year, from: txn.date)
            
            return txnMonth == budget.month && txnYear == budget.year
        }
        
        // Convert each transaction to preferred currency and sum
        return relevantTransactions.reduce(Decimal.zero) { total, txn in
            let converted = CurrencyManager.shared.convert(
                amount: txn.amount,
                from: txn.currencyCode,
                to: preferredCurrency
            )
            return total + converted
        }
    }
    
    /// Convert budget limit to preferred currency
    private func convertBudgetLimit(for budget: Budget) -> Decimal {
        return CurrencyManager.shared.convert(
            amount: budget.amountLimit,
            from: budget.currencyCode,
            to: preferredCurrency
        )
    }
    
    private func deleteBudgets(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(budgets[index])
            }
        }
    }
}

// MARK: - Budget Row View with Progress
struct BudgetRowView: View {
    let budget: Budget
    let spent: Decimal
    let budgetLimitConverted: Decimal
    
    private var preferredCurrency: String {
        CurrencyManager.shared.preferredCurrencyCode
    }
    
    private var progress: Double {
        guard budgetLimitConverted > 0 else { return 0 }
        return Double(truncating: spent as NSNumber) / Double(truncating: budgetLimitConverted as NSNumber)
    }
    
    private var isOverBudget: Bool {
        spent > budgetLimitConverted
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
        VStack(alignment: .leading, spacing: 8) {
            // Top row: Icon, Category, Amount
            HStack {
                if let category = budget.category {
                    Image(systemName: category.icon)
                        .foregroundStyle(progressColor)
                        .frame(width: 30)
                } else {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 30)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(budget.category?.name ?? "Unknown Category")
                        .font(.headline)
                    Text("\(Calendar.current.monthSymbols[budget.month - 1]) \(String(budget.year))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(spent.formatted(.currency(code: preferredCurrency))) / \(budgetLimitConverted.formatted(.currency(code: preferredCurrency)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("\(Int(min(progress, 1.0) * 100))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(progressColor)
                }
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    // Progress fill
                    Capsule()
                        .fill(progressColor.gradient)
                        .frame(width: min(geometry.size.width * CGFloat(min(progress, 1.0)), geometry.size.width), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        BudgetListView()
            .modelContainer(for: [Budget.self, Transaction.self, Category.self], inMemory: true)
    }
}
