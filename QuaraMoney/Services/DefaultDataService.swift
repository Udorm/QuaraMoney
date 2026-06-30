
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
            let descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.deletedAt == nil })
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
            #if DEBUG
            print("Failed to seed default categories: \(error)")
            #endif
        }
    }
    
    nonisolated static func ensureCategoryExists(modelContext: ModelContext, name: String, icon: String, colorHex: String, type: TransactionType) {
        do {
            // Check if category with this name and type already exists.
            // SwiftData can't lower a captured enum (`$0.type == type`) into a
            // predicate — it throws `unsupportedPredicate` — so filter by name in
            // the fetch and match `type` in Swift.
            let descriptor = FetchDescriptor<Category>(
                predicate: #Predicate { $0.name == name && $0.deletedAt == nil }
            )

            let exists = try modelContext.fetch(descriptor).contains { $0.type == type }
            if !exists {
                let category = Category(
                    name: name,
                    icon: icon,
                    colorHex: colorHex,
                    type: type,
                    isSystem: false
                )
                modelContext.insert(category)
                #if DEBUG
                print("Created missing category: \(name)")
                #endif
            }
        } catch {
            #if DEBUG
            print("Failed to ensure category exists: \(error)")
            #endif
        }
    }
    
    nonisolated static func ensureSystemCategoryExists(modelContext: ModelContext, name: String, icon: String, colorHex: String, type: TransactionType) {
        do {
            // Check if category with this name and type already exists.
            // SwiftData can't lower a captured enum (`$0.type == type`) into a
            // predicate — it throws `unsupportedPredicate` — so filter by name in
            // the fetch and match `type` in Swift.
            let descriptor = FetchDescriptor<Category>(
                predicate: #Predicate { $0.name == name && $0.deletedAt == nil }
            )

            if let existing = try modelContext.fetch(descriptor).first(where: { $0.type == type }) {
                if !existing.isSystem {
                    existing.isSystem = true
                    #if DEBUG
                    print("Marked existing category as system: \(name)")
                    #endif
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
                #if DEBUG
                print("Created system category: \(name)")
                #endif
            }
        } catch {
            #if DEBUG
            print("Failed to ensure system category exists: \(error)")
            #endif
        }
    }
}
