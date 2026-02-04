import SwiftUI
import SwiftData

struct BudgetTabView: View {
    @State private var selectedSection: BudgetSection = .budgets
    
    enum BudgetSection: String, CaseIterable {
        case budgets = "Budgets"
        case savings = "Savings"
    }
    
    var body: some View {
        NavigationStack {
            Group {
                switch selectedSection {
                case .budgets:
                    BudgetListContent()
                case .savings:
                    SavingsGoalListContent()
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Section", selection: $selectedSection) {
                        ForEach(BudgetSection.allCases, id: \.self) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
        }
    }
}

#Preview {
    BudgetTabView()
        .modelContainer(for: [Budget.self, SavingsGoal.self, Transaction.self, Category.self, CategoryGroup.self, Wallet.self], inMemory: true)
}
