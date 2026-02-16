
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
                    type: item.type,
                    isSystem: false
                )
                modelContext.insert(category)
            }
            
            try modelContext.save()
            
        } catch {
            print("Failed to seed default categories: \(error)")
        }
    }
    
    nonisolated static func ensureCategoryExists(modelContext: ModelContext, name: String, icon: String, colorHex: String, type: TransactionType) {
        do {
            // Check if category with this name and type already exists
            var descriptor = FetchDescriptor<Category>(
                predicate: #Predicate { $0.name == name && $0.type == type }
            )
            descriptor.fetchLimit = 1
            
            if try modelContext.fetchCount(descriptor) == 0 {
                let category = Category(
                    name: name,
                    icon: icon,
                    colorHex: colorHex,
                    type: type,
                    isSystem: false
                )
                modelContext.insert(category)
                try modelContext.save()
                print("Created missing category: \(name)")
            }
        } catch {
            print("Failed to ensure category exists: \(error)")
        }
    }
    
    nonisolated static func ensureSystemCategoryExists(modelContext: ModelContext, name: String, icon: String, colorHex: String, type: TransactionType) {
        do {
            // Check if category with this name and type already exists
            var descriptor = FetchDescriptor<Category>(
                predicate: #Predicate { $0.name == name && $0.type == type }
            )
            descriptor.fetchLimit = 1
            
            if let existing = try modelContext.fetch(descriptor).first {
                if !existing.isSystem {
                    existing.isSystem = true
                    try modelContext.save()
                    print("Marked existing category as system: \(name)")
                }
            } else {
                let category = Category(
                    name: name,
                    icon: icon,
                    colorHex: colorHex,
                    type: type,
                    isSystem: true
                )
                modelContext.insert(category)
                try modelContext.save()
                print("Created system category: \(name)")
            }
        } catch {
            print("Failed to ensure system category exists: \(error)")
        }
    }
}
