import SwiftUI
import SwiftData

struct EventListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Event.startDate) private var events: [Event]
    
    @State private var showingAddEvent = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(events) { event in
                    NavigationLink(destination: EventDetailView(event: event)) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(event.title)
                                    .font(.app(.headline))
                                Text(event.startDate.formatted(date: .long, time: .omitted))
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let budget = event.totalBudget {
                                Text("\(L10n.Event.budget): \(budget.formatted(.currency(code: "USD")))") // Currency assumption for budget
                                    .font(.app(.caption2))
                                    .padding(4)
                                    .background(.secondary.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteEvent)
            }
            .navigationTitle(L10n.Event.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddEvent = true }) {
                        Label(L10n.Event.add, systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddEvent) {
                AddEventView()
            }
            .overlay {
                if events.isEmpty {
                    AppEmptyStateView(
                        L10n.Event.noEvent,
                        systemImage: "party.popper",
                        description: L10n.Event.emptyState
                    )
                }
            }
        }
    }
    
    private func deleteEvent(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(events[index])
        }
    }
}
