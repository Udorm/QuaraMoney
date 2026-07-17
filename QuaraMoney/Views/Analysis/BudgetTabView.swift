import SwiftUI
import SwiftData

struct BudgetTabView: View {
    @State private var selectedSection: BudgetSection = .budgets
    @State private var budgetSearchText = ""
    @State private var savingsSearchText = ""
    @State private var showAddBudget = false
    @State private var showAddGoal = false
    @State private var showBudgetFilter = false
    
    enum BudgetSection: CaseIterable, Hashable {
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
            TabView(selection: $selectedSection) {
                BudgetListView(
                    searchText: $budgetSearchText,
                    isFilterPresented: $showBudgetFilter
                )
                    .tag(BudgetSection.budgets)

                SavingsGoalListView(searchText: $savingsSearchText)
                    .tag(BudgetSection.savings)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("tab.plan".localized)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: activeSearchText,
                prompt: L10n.Common.search
            )
            .searchToolbarBehavior(.minimize)
            .safeAreaInset(edge: .bottom, alignment: .trailing) {
                Button {
                    HapticManager.shared.impact(style: .light)
                    switch selectedSection {
                    case .budgets:
                        showAddBudget = true
                    case .savings:
                        showAddGoal = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .modifier(CircularFABStyle())
                .controlSize(.large)
                .accessibilityLabel(addButtonAccessibilityLabel)
                .padding(.trailing)
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("common.section".localized, selection: animatedSelection) {
                        ForEach(BudgetSection.allCases, id: \.self) { section in
                            Text(section.displayName).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }

                if selectedSection == .budgets {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showBudgetFilter = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                        }
                        .accessibilityLabel(L10n.Filter.title)
                    }
                }
            }
            .sheet(isPresented: $showAddBudget) {
                AddBudgetView()
            }
            .sheet(isPresented: $showAddGoal) {
                AddSavingsGoalView()
            }
        }
    }

    private var addButtonAccessibilityLabel: String {
        switch selectedSection {
        case .budgets: return L10n.Budget.new
        case .savings: return L10n.Savings.new
        }
    }

    private var activeSearchText: Binding<String> {
        switch selectedSection {
        case .budgets:
            return $budgetSearchText
        case .savings:
            return $savingsSearchText
        }
    }

    private var animatedSelection: Binding<BudgetSection> {
        Binding(
            get: { selectedSection },
            set: { section in
                withAnimation(.smooth(duration: 0.3)) {
                    selectedSection = section
                }
            }
        )
    }
}

#Preview {
    BudgetTabView()
        .modelContainer(for: [Budget.self, SavingsGoal.self, Transaction.self, TransactionLocation.self, Category.self, Wallet.self], inMemory: true)
}
