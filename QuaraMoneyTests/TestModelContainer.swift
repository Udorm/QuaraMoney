@testable import QuaraMoney
import SwiftData
import Foundation

@MainActor
class TestModelContainer {
    static func create() -> ModelContainer {
        let modelTypes: [any PersistentModel.Type] = [
            Wallet.self,
            Category.self,
            Event.self,
            RecurringRule.self,
            Transaction.self,
            Budget.self,
        ]
        let schema = Schema(modelTypes)
        
        // Use in-memory storage for speed and isolation
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create Test ModelContainer: \(error)")
        }
    }
}
