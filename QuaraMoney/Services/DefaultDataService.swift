
import Foundation
import SwiftData

struct DefaultCategoryData: Sendable {
    let name: String
    let icon: String
    let colorHex: String
    let type: TransactionType
}

struct DefaultDataService {
    nonisolated static func seedDefaultCategories(modelContext: ModelContext, data: [DefaultCategoryData]) {
        do {
            // Check if categories already exist
            let descriptor = FetchDescriptor<Category>()
            let existingCount = try modelContext.fetchCount(descriptor)
            
            guard existingCount == 0 else { return }
            
            // Create default categories from passed data
            for item in data {
                let category = Category(
                    name: item.name,
                    icon: item.icon,
                    colorHex: item.colorHex,
                    type: item.type
                )
                modelContext.insert(category)
            }
            
            try modelContext.save()
            
        } catch {
            print("Failed to seed default categories: \(error)")
        }
    }
}
