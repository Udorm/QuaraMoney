import SwiftUI

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
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
                
                Section {
                    NavigationLink(destination: CategoryListView()) {
                        Label {
                            Text("Categories")
                        } icon: {
                            Image(systemName: "tag.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    NavigationLink(destination: BudgetListView()) {
                        Label {
                            Text("Budgets")
                        } icon: {
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                } header: {
                    Text("Management")
                }
                
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
        }
    }
}
