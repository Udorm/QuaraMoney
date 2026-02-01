import SwiftUI
import SwiftData

struct BudgetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Budget.year, order: .reverse), SortDescriptor(\Budget.month, order: .reverse)]) private var budgets: [Budget]
    @State private var showAddBudget = false
    
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
                        HStack {
                            if let category = budget.category {
                                Image(systemName: category.icon)
                                    .foregroundStyle(.blue)
                                    .frame(width: 30)
                            } else {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30)
                            }
                            
                            VStack(alignment: .leading) {
                                Text(budget.category?.name ?? "Unknown Category")
                                    .font(.headline)
                                Text("\(Calendar.current.monthSymbols[budget.month - 1]) \(String(budget.year))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(budget.amountLimit.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode)))
                                .font(.subheadline)
                                .fontWeight(.medium)
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
    
    private func deleteBudgets(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(budgets[index])
            }
        }
    }
}

#Preview {
    BudgetListView()
        .modelContainer(for: Budget.self, inMemory: true)
}
