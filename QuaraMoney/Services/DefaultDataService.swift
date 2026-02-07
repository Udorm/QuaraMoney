
import Foundation
import SwiftData

struct DefaultDataService {
    @MainActor
    static func seedDefaultCategories(modelContext: ModelContext) {
        // defined keys in Localizable.strings:
        // "category.foodAndDrink" = "Food and drink";
        // "category.housing" = "Housing";
        // "category.waterBill" = "Water bill";
        // "category.electricityBill" = "Electricity bill";
        // "category.internetBill" = "Internet bill";
        // "category.subscriptions" = "Subscriptions";
        // "category.transportation" = "Transportation";
        // "category.personalLifestyle" = "Personal & lifestyle";
        // "category.health" = "Health";
        // "category.financial" = "Financial";
        // "category.others" = "Others";
        // "category.salary" = "Salary";
        // "category.investments" = "Investments";
        // "category.services" = "Services";
        // "category.leisure" = "Leisure";
        // "category.education" = "Education";
        // "category.tech" = "Tech";

        do {
            // Check if categories already exist
            let descriptor = FetchDescriptor<Category>()
            let existingCount = try modelContext.fetchCount(descriptor)
            
            guard existingCount == 0 else { return }
            
            // Create default categories
            let categories = [
                // Income
                Category(name: L10n.Category.salary, icon: "dollarsign.circle", colorHex: "#4CAF50", type: .income),
                Category(name: L10n.Category.investments, icon: "chart.line.uptrend.xyaxis", colorHex: "#2196F3", type: .income),
                Category(name: L10n.Category.others, icon: "gift", colorHex: "#FFC107", type: .income),
                
                // Expense
                Category(name: L10n.Category.foodAndDrink, icon: "fork.knife", colorHex: "#FF5722", type: .expense),
                Category(name: L10n.Category.housing, icon: "house", colorHex: "#795548", type: .expense),
                Category(name: L10n.Category.transportation, icon: "car", colorHex: "#03A9F4", type: .expense),
                Category(name: L10n.Category.personalLifestyle, icon: "tshirt", colorHex: "#E91E63", type: .expense),
                Category(name: L10n.Category.health, icon: "heart", colorHex: "#F44336", type: .expense),
                Category(name: L10n.Category.education, icon: "book", colorHex: "#9C27B0", type: .expense),
                Category(name: L10n.Category.tech, icon: "laptopcomputer", colorHex: "#607D8B", type: .expense),
                Category(name: L10n.Category.leisure, icon: "gamecontroller", colorHex: "#673AB7", type: .expense),
                Category(name: L10n.Category.subscriptions, icon: "arrow.triangle.2.circlepath", colorHex: "#3F51B5", type: .expense),
                Category(name: L10n.Category.financial, icon: "building.columns", colorHex: "#009688", type: .expense),
                
                // Bills
                Category(name: L10n.Category.electricityBill, icon: "bolt", colorHex: "#FFEB3B", type: .expense),
                Category(name: L10n.Category.waterBill, icon: "drop", colorHex: "#2196F3", type: .expense),
                Category(name: L10n.Category.internetBill, icon: "wifi", colorHex: "#00BCD4", type: .expense)
            ]
            
            for category in categories {
                modelContext.insert(category)
            }
            
            try modelContext.save()
            
        } catch {
            print("Failed to seed default categories: \(error)")
        }
    }
}
