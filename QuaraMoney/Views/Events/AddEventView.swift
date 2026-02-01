import SwiftUI
import SwiftData

struct AddEventView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var startDate: Date = Date()
    @State private var budgetString: String = ""
    @State private var notes: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Event Details") {
                    TextField("Event Name", text: $title)
                    DatePicker("Start Date", selection: $startDate, displayedComponents: [.date])
                }
                
                Section("Budget & Notes") {
                    TextField("Total Budget (Optional)", text: $budgetString)
                        .keyboardType(.decimalPad)
                    
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveEvent()
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
    
    private func saveEvent() {
        let event = Event(title: title, startDate: startDate)
        if let budget = Decimal(string: budgetString) {
            event.totalBudget = budget
        }
        event.notes = notes.isEmpty ? nil : notes
        
        modelContext.insert(event)
    }
}
