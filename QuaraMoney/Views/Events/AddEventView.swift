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
                Section(L10n.Event.details) {
                    TextField(L10n.Event.name, text: $title)
                    DatePicker(L10n.Budget.startDate, selection: $startDate, displayedComponents: [.date])
                }
                
                Section(L10n.Event.budgetNotes) {
                    TextField(L10n.Event.budgetOptional, text: $budgetString)
                        .keyboardType(.decimalPad)
                    
                    TextField(L10n.Event.notes, text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(L10n.Event.new)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.add) {
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
