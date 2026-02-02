import SwiftUI
import SwiftData

struct RecurringRuleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecurringRule.nextDueDate) private var rules: [RecurringRule]
    
    @State private var showingAddRule = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(rules) { rule in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(rule.name)
                                .font(.headline)
                            Text(rule.frequency.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text(rule.amount.formatted(.currency(code: rule.currencyCode)))
                                .font(.body)
                                .fontWeight(.semibold)
                            
                            Text("Next: \(rule.nextDueDate.formatted(date: .numeric, time: .omitted))")
                                .font(.caption2)
                                .foregroundStyle(rule.nextDueDate <= Date() ? .red : .secondary)
                        }
                    }
                }
                .onDelete(perform: deleteRule)
            }
            .navigationTitle("Subscriptions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        Text("Preview")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                        
                        Button(action: { showingAddRule = true }) {
                            Label("Add Subscription", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddRule) {
               AddRecurringRuleView()
            }
            .overlay {
                if rules.isEmpty {
                    ContentUnavailableView(
                        "No Subscriptions",
                        systemImage: "calendar.badge.clock",
                        description: Text("Add recurring bills to track them automatically.")
                    )
                }
            }
        }
    }
    
    private func deleteRule(at offsets: IndexSet) {
        for index in offsets {
            let rule = rules[index]
            modelContext.delete(rule)
        }
    }
}
