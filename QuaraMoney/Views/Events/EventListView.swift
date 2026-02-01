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
                                    .font(.headline)
                                Text(event.startDate.formatted(date: .long, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let budget = event.totalBudget {
                                Text("Budget: \(budget.formatted(.currency(code: "USD")))") // Currency assumption for budget
                                    .font(.caption2)
                                    .padding(4)
                                    .background(.secondary.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteEvent)
            }
            .navigationTitle("Events")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddEvent = true }) {
                        Label("Add Event", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddEvent) {
                AddEventView()
            }
            .overlay {
                if events.isEmpty {
                    ContentUnavailableView(
                        "No Events",
                        systemImage: "party.popper",
                        description: Text("Plan trips, parties, or projects.")
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
