import SwiftUI
import SwiftData

struct BudgetTabView: View {
    @State private var selectedSection: BudgetSection = .budgets
    
    enum BudgetSection: CaseIterable {
        case budgets
        case savings
        
        var displayName: String {
            switch self {
            case .budgets: return L10n.Budget.title
            case .savings: return L10n.Savings.title
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                switch selectedSection {
                case .budgets:
                    BudgetListView()
                case .savings:
                    SavingsGoalListView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Section", selection: $selectedSection) {
                        ForEach(BudgetSection.allCases, id: \.self) { section in
                            Text(section.displayName).tag(section)
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
        .modelContainer(for: [Budget.self, SavingsGoal.self, Transaction.self, Category.self, Wallet.self], inMemory: true)
}
