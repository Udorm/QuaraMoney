import Foundation
import SwiftData

protocol DataService {
    func save() throws
    func insert<T: PersistentModel>(_ model: T)
    func delete<T: PersistentModel>(_ model: T)
}

@MainActor
final class SwiftDataService: DataService {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func save() throws {
        try modelContext.save()
    }
    
    func insert<T: PersistentModel>(_ model: T) {
        modelContext.insert(model)
    }
    
    func delete<T: PersistentModel>(_ model: T) {
        modelContext.delete(model)
    }
}
