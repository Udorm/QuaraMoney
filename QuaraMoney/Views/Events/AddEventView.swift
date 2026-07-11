import SwiftUI
import SwiftData

struct AddEventView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var eventToEdit: Event?
    
    @State private var title: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var hasEndDate: Bool = false
    @State private var budgetString: String = ""
    @State private var notes: String = ""
    @State private var location: String = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var showingLocationPicker = false
    @State private var selectedIcon: String = "party.popper"
    @State private var selectedColorHex: String = "007AFF"
    @State private var currencyCode: String = CurrencyManager.shared.preferredCurrencyCode
    
    // Predefined colors
    let colors: [String] = [
        "FF3B30", "FF9500", "FFCC00", "34C759", "00C7BE",
        "30B0C7", "32ADE6", "007AFF", "5856D6", "AF52DE",
        "FF2D55", "A2845E"
    ]
    
    // Predefined icons
    let icons: [String] = [
        "party.popper", "birthday.cake", "gift", "airplane", "car",
        "house", "cart", "creditcard", "graduationcap", "briefcase",
        "gamecontroller", "tv", "music.note", "camera", "photo",
        "map", "figure.walk", "figure.run", "heart", "star"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.Event.details) {
                    TextField(L10n.Event.name, text: $title)
                    
                    HStack {
                        TextField("event.locationOptional".localized, text: $location)
                        Button {
                            showingLocationPicker = true
                        } label: {
                            Image(systemName: "map")
                        }
                    }
                    
                    Picker("transaction.currency".localized, selection: $currencyCode) {
                        ForEach(CurrencyManager.shared.availableCurrencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section(L10n.EventAdditional.appearance) {
                    // Icon Picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 15) {
                            ForEach(icons, id: \.self) { icon in
                                Image(systemName: icon)
                                    .font(.title2)
                                    .foregroundStyle(selectedIcon == icon ? Color(hex: selectedColorHex) ?? .blue : .primary)
                                    .frame(width: 44, height: 44)
                                    .background(selectedIcon == icon ? (Color(hex: selectedColorHex) ?? .blue).opacity(0.1) : Color.clear)
                                    .clipShape(Circle())
                                    .onTapGesture {
                                        selectedIcon = icon
                                    }
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    
                    // Color Picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 15) {
                            ForEach(colors, id: \.self) { colorHex in
                                Circle()
                                    .fill(Color(hex: colorHex) ?? .gray)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: selectedColorHex == colorHex ? 2 : 0)
                                    )
                                    .onTapGesture {
                                        selectedColorHex = colorHex
                                    }
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
                
                Section(L10n.EventAdditional.dateTime) {
                    DatePicker(L10n.Budget.startDate, selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    
                    Toggle("event.endDate".localized, isOn: $hasEndDate)

                    if hasEndDate {
                        DatePicker("event.endDate".localized, selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
                    }
                }
                
                Section(L10n.Event.budgetNotes) {
                    TextField(L10n.Event.budgetOptional, text: $budgetString)
                        .keyboardType(.decimalPad)
                    
                    TextField(L10n.Event.notes, text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(eventToEdit == nil ? L10n.Event.new : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveEvent()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.isEmpty)
                }
            }
            .onAppear {
                if let event = eventToEdit {
                    title = event.title
                    startDate = event.startDate
                    if let end = event.endDate {
                        endDate = end
                        hasEndDate = true
                    }
                    if let budget = event.totalBudget {
                        budgetString = "\(budget)"
                    }
                    notes = event.notes ?? ""
                    location = event.location ?? ""
                    latitude = event.latitude
                    longitude = event.longitude
                    selectedIcon = event.icon
                    selectedColorHex = event.colorHex
                    currencyCode = event.currencyCode
                }
            }
            .sheet(isPresented: $showingLocationPicker) {
                EventLocationPickerView(latitude: $latitude, longitude: $longitude, locationName: $location)
            }
        }
    }
    
    private func saveEvent() {
        let budget = Decimal(string: budgetString)
        
        // Validation: End date should be after start date if enabled
        let finalEndDate = hasEndDate ? endDate : nil
        
        if let event = eventToEdit {
            event.title = title
            event.startDate = startDate
            event.endDate = finalEndDate
            event.totalBudget = budget
            event.notes = notes.isEmpty ? nil : notes
            event.location = location.isEmpty ? nil : location
            event.latitude = latitude
            event.longitude = longitude
            event.icon = selectedIcon
            event.colorHex = selectedColorHex
            event.currencyCode = currencyCode
            if event.ledgerMode != .isolatedV1 {
                event.ledgerMode = .isolatedV1
            }
            // No need to insert, just save context automatically via SwiftData autosave or manual save if needed
        } else {
            let event = Event(
                title: title,
                startDate: startDate,
                endDate: finalEndDate,
                icon: selectedIcon,
                colorHex: selectedColorHex,
                location: location.isEmpty ? nil : location,
                totalBudget: budget,
                currencyCode: currencyCode,
                ledgerMode: .isolatedV1,
                latitude: latitude,
                longitude: longitude
            )
            event.notes = notes.isEmpty ? nil : notes
            modelContext.insert(event)
        }
    }
}
