import SwiftUI

struct MoreView: View {
    @State private var showBudgetWizard = false
    @State private var showNotifications = false
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Wallets Section
                Section {
                    NavigationLink(destination: WalletListView()) {
                        Label {
                            Text("Wallets")
                        } icon: {
                            Image(systemName: "wallet.pass.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                } header: {
                    Text("Wallets")
                }
                
                // MARK: - Planning Tools Section
                Section {
                    NavigationLink(destination: BudgetInsightsView()) {
                        Label {
                            Text("Budget Insights")
                        } icon: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundStyle(.purple)
                        }
                    }
                    
                    Button {
                        showBudgetWizard = true
                    } label: {
                        Label {
                            Text("Budget Setup Wizard")
                        } icon: {
                            Image(systemName: "wand.and.stars")
                                .foregroundStyle(.pink)
                        }
                    }
                } header: {
                    Text("Planning Tools")
                }
                
                // MARK: - Features Section
                Section {
                    NavigationLink(destination: RecurringRuleListView()) {
                        Label {
                            Text("Subscriptions")
                        } icon: {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    NavigationLink(destination: EventListView()) {
                        Label {
                            Text("Events")
                        } icon: {
                            Image(systemName: "party.popper")
                                .foregroundStyle(.purple)
                        }
                    }
                } header: {
                    Text("Features")
                }
                
                // MARK: - Management Section
                Section {
                    NavigationLink(destination: CategoryListView()) {
                        Label {
                            Text("Categories")
                        } icon: {
                            Image(systemName: "tag.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    NavigationLink(destination: CategoryGroupListView()) {
                        Label {
                            Text("Category Groups")
                        } icon: {
                            Image(systemName: "folder.fill.badge.gearshape")
                                .foregroundStyle(.cyan)
                        }
                    }
                } header: {
                    Text("Management")
                }
                
                // MARK: - App Section
                Section {
                    NavigationLink(destination: SettingsView()) {
                        Label {
                            Text("Settings")
                        } icon: {
                            Image(systemName: "gear")
                                .foregroundStyle(.gray)
                        }
                    }
                } header: {
                    Text("App")
                }
            }
            .navigationTitle("More")
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
