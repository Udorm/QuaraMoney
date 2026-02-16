
import SwiftUI

struct MoreView: View {
    @State private var showBudgetWizard = false
    
    var body: some View {
        NavigationStack {
            List {
                Section(L10n.More.planningTools) {
                    NavigationLink(destination: BudgetInsightsView()) {
                        Label(L10n.Budget.insights, systemImage: "chart.line.uptrend.xyaxis")
                    }
                    
                    Button {
                        showBudgetWizard = true
                    } label: {
                        Label(L10n.More.budgetWizard, systemImage: "wand.and.stars")
                    }
                }
                
                Section(L10n.More.features) {
                    NavigationLink(destination: EventListView()) {
                        Label(L10n.Event.title, systemImage: "party.popper")
                    }
                    
                    NavigationLink(destination: RecurringRuleListView()) {
                        Label(L10n.More.recurringRules, systemImage: "repeat")
                    }
                }
                
                Section(L10n.More.management) {
                    NavigationLink(destination: DebtListView()) {
                        Label(L10n.Debt.title, systemImage: "person.2.crop.square.stack")
                    }
                    
                    NavigationLink(destination: CategoryListView()) {
                        Label(L10n.More.categories, systemImage: "list.bullet")
                    }
                }
                
                Section(L10n.More.app) {
                    NavigationLink(destination: SettingsView()) {
                        Label(L10n.Settings.title, systemImage: "gear")
                    }
                }
            }
            .navigationTitle(L10n.More.title)
            .sheet(isPresented: $showBudgetWizard) {
                BudgetSetupWizardView()
            }
        }
    }
}
