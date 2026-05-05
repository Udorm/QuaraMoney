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
                                .font(.app(.headline))
                            Text(rule.frequency.displayName)
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text(rule.amount.formattedAmount(for: rule.currencyCode))
                                .font(.app(.body, weight: .semibold))
                            
                            Text(L10n.Recurring.next(rule.nextDueDate.formatted(date: .numeric, time: .omitted)))
                                .font(.app(.caption2))
                                .foregroundStyle(rule.nextDueDate <= Date() ? .red : .secondary)
                        }
                    }
                }
                .onDelete(perform: deleteRule)
            }
            .navigationTitle(L10n.Recurring.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        Text(L10n.Recurring.preview)
                            .font(.app(.caption, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                        
                        Button(action: { showingAddRule = true }) {
                            Label(L10n.Recurring.add, systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddRule) {
               AddRecurringRuleView()
            }
            .overlay {
                if rules.isEmpty {
                    AppEmptyStateView(
                        L10n.Recurring.emptyTitle,
                        systemImage: "calendar.badge.clock",
                        description: L10n.Recurring.emptyState
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
#Preview {
    NavigationStack {
        RecurringRuleListView()
            .modelContainer(for: [RecurringRule.self], inMemory: true)
    }
}

