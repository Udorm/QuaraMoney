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
                    Section(L10n.EventAdditional.listOngoing) {
                        ForEach(ongoingEvents) { event in
                            EventRowView(event: event)
                        }
                        .onDelete { indexSet in
                            deleteEvents(at: indexSet, source: ongoingEvents)
                        }
                    }
                }
                
                if !upcomingEvents.isEmpty {
                    Section(L10n.EventAdditional.listUpcoming) {
                        ForEach(upcomingEvents) { event in
                            EventRowView(event: event)
                        }
                        .onDelete { indexSet in
                            deleteEvents(at: indexSet, source: upcomingEvents)
                        }
                    }
                }
                
                if !pastEvents.isEmpty {
                    Section(L10n.EventAdditional.listPast) {
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
        NavigationLink(destination: LazyView(EventDetailViewV2(event: event))) {
            HStack(spacing: 12) {
                // Leading Icon
                ZStack {
                    Circle()
                        .fill(eventColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: event.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(eventColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.app(.headline))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text(formatDateRange(start: event.startDate, end: event.endDate))
                            .font(.app(.subheadline))
                        
                        if let location = event.location, !location.isEmpty {
                            Text(location)
                                .font(.app(.subheadline))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }
    
    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()
    
    private static let yearDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()
    
    private func formatDateRange(start: Date, end: Date?) -> String {
        let currentYear = Calendar.current.component(.year, from: Date())
        let startYear = Calendar.current.component(.year, from: start)
        
        let startFormatter = startYear == currentYear ? Self.shortDateFormatter : Self.yearDateFormatter
        let startStr = startFormatter.string(from: start)
        
        if let end = end {
            if Calendar.current.isDate(start, inSameDayAs: end) {
                return startStr
            } else {
                let endYear = Calendar.current.component(.year, from: end)
                let endFormatter = endYear == currentYear ? Self.shortDateFormatter : Self.yearDateFormatter
                let endStr = endFormatter.string(from: end)
                
                return "\(startStr) – \(endStr)"
            }
        }
        
        return startStr
    }
}
