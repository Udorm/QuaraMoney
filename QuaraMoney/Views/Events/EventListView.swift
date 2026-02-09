import SwiftUI
import SwiftData

struct EventListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Event.startDate) private var events: [Event]
    
    @State private var showingAddEvent = false
    
    // Group events
    private var ongoingEvents: [Event] {
        let now = Date()
        return events.filter { event in
            // If end date exists, check range. Else assume 1 day or check if start date is today? 
            // Better logic: if end date is set, start <= now <= end. 
            // If no end date, maybe check if start is today (same day).
            if let end = event.endDate {
                return event.startDate <= now && now <= end
            }
            return Calendar.current.isDateInToday(event.startDate)
        }
    }
    
    private var upcomingEvents: [Event] {
        let now = Date()
        return events.filter { event in
            event.startDate > now
        }
    }
    
    private var pastEvents: [Event] {
        let now = Date()
        return events.filter { event in
            if let end = event.endDate {
                return end < now
            }
            return event.startDate < now && !Calendar.current.isDateInToday(event.startDate)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if !ongoingEvents.isEmpty {
                    Section("Ongoing") {
                        ForEach(ongoingEvents) { event in
                            EventRowView(event: event)
                        }
                        .onDelete { indexSet in
                            deleteEvents(at: indexSet, source: ongoingEvents)
                        }
                    }
                }
                
                if !upcomingEvents.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcomingEvents) { event in
                            EventRowView(event: event)
                        }
                        .onDelete { indexSet in
                            deleteEvents(at: indexSet, source: upcomingEvents)
                        }
                    }
                }
                
                if !pastEvents.isEmpty {
                    Section("Past") {
                        ForEach(pastEvents) { event in
                            EventRowView(event: event)
                        }
                        .onDelete { indexSet in
                            deleteEvents(at: indexSet, source: pastEvents)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
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
    
    private func deleteEvents(at offsets: IndexSet, source: [Event]) {
        for index in offsets {
            modelContext.delete(source[index])
        }
    }
}

struct EventRowView: View {
    let event: Event
    
    private var eventColor: Color {
        Color(hex: event.colorHex) ?? .blue
    }
    
    var body: some View {
        NavigationLink(destination: EventDetailView(event: event)) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(eventColor.opacity(0.1))
                        .frame(width: 40, height: 40)
                    Image(systemName: event.icon)
                        .foregroundStyle(eventColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.app(.headline))
                    
                    HStack {
                        if let location = event.location {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .font(.app(.caption2))
                        }
                        
                        Text(formatDateRange(start: event.startDate, end: event.endDate))
                            .font(.app(.caption2))
                    }
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if let budget = event.totalBudget {
                    VStack(alignment: .trailing) {
                        Text(budget.formatted(.currency(code: "USD"))) // Using default for now
                            .font(.app(.caption, weight: .bold))
                            .foregroundStyle(eventColor)
                        
                        Text("Budget")
                            .font(.app(.caption2))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func formatDateRange(start: Date, end: Date?) -> String {
        if let end = end {
            if Calendar.current.isDate(start, inSameDayAs: end) {
                return start.formatted(date: .abbreviated, time: .shortened) + " - " + end.formatted(date: .omitted, time: .shortened)
            } else {
                return start.formatted(date: .abbreviated, time: .omitted) + " - " + end.formatted(date: .abbreviated, time: .omitted)
            }
        }
        return start.formatted(date: .abbreviated, time: .shortened)
    }
}
