import SwiftUI

struct MoreView: View {
    @State private var showBudgetWizard = false
    @State private var showNotifications = false
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Planning Tools Section
                Section {
                    NavigationLink(destination: BudgetInsightsView()) {
                        Label {
                            Text(L10n.Budget.insights)
                        } icon: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundStyle(.purple)
                        }
                    }
                    
                    Button {
                        showBudgetWizard = true
                    } label: {
                        Label {
                            Text("more.budgetWizard".localized)
                        } icon: {
                            Image(systemName: "wand.and.stars")
                                .foregroundStyle(.pink)
                        }
                    }
                } header: {
                    Text("more.planningTools".localized)
                }
                
                // MARK: - Features Section
                Section {
                    NavigationLink(destination: RecurringRuleListView()) {
                        Label {
                            Text(L10n.Recurring.title)
                        } icon: {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    NavigationLink(destination: EventListView()) {
                        Label {
                            Text(L10n.Event.title)
                        } icon: {
                            Image(systemName: "party.popper")
                                .foregroundStyle(.purple)
                        }
                    }
                } header: {
                    Text("more.features".localized)
                }
                
                // MARK: - Management Section
                Section {
                    NavigationLink(destination: CategoryListView()) {
                        Label {
                            Text(L10n.Category.title)
                        } icon: {
                            Image(systemName: "tag.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    NavigationLink(destination: CategoryGroupListView()) {
                        Label {
                            Text(L10n.CategoryGroup.title)
                        } icon: {
                            Image(systemName: "folder.fill.badge.gearshape")
                                .foregroundStyle(.cyan)
                        }
                    }
                } header: {
                    Text("more.management".localized)
                }
                
                // MARK: - App Section
                Section {
                    NavigationLink(destination: SettingsView()) {
                        Label {
                            Text(L10n.Settings.title)
                        } icon: {
                            Image(systemName: "gear")
                                .foregroundStyle(.gray)
                        }
                    }
                } header: {
                    Text("more.app".localized)
                }
            }
            .navigationTitle(L10n.More.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NotificationBellButton()
                }
            }
            .sheet(isPresented: $showBudgetWizard) {
                BudgetSetupWizardView()
            }
        }
    }
}
