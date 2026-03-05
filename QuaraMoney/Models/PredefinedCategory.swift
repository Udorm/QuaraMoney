import Foundation
import SwiftData

struct PredefinedCategory {
    let nameKey: String
    let icon: String
    let colorHex: String
    let type: TransactionType
    
    /// Returns the localized name for this category
    var name: String {
        return nameKey.localized
    }
    
    static let defaults: [PredefinedCategory] = [
        PredefinedCategory(nameKey: "category.foodAndDrink", icon: "fork.knife", colorHex: "#FF9500", type: .expense), // Orange
        PredefinedCategory(nameKey: "category.housing", icon: "house.fill", colorHex: "#007AFF", type: .expense), // Blue
        PredefinedCategory(nameKey: "category.waterBill", icon: "drop.fill", colorHex: "#5AC8FA", type: .expense), // Light Blue
        PredefinedCategory(nameKey: "category.electricityBill", icon: "bolt.fill", colorHex: "#FFCC00", type: .expense), // Yellow
        PredefinedCategory(nameKey: "category.internetBill", icon: "wifi", colorHex: "#5856D6", type: .expense), // Purple
        PredefinedCategory(nameKey: "category.subscriptions", icon: "play.tv.fill", colorHex: "#FF2D55", type: .expense), // Pink
        PredefinedCategory(nameKey: "category.transportation", icon: "car.fill", colorHex: "#34C759", type: .expense), // Green
        PredefinedCategory(nameKey: "category.personalLifestyle", icon: "figure.walk", colorHex: "#AF52DE", type: .expense), // Indigo
        PredefinedCategory(nameKey: "category.health", icon: "heart.fill", colorHex: "#FF3B30", type: .expense), // Red
        PredefinedCategory(nameKey: "category.financial", icon: "banknote.fill", colorHex: "#8E8E93", type: .expense), // Gray
        PredefinedCategory(nameKey: "category.others", icon: "circle.grid.2x2.fill", colorHex: "#A2845E", type: .expense), // Olive
        // Also adding Income for completeness
        PredefinedCategory(nameKey: "category.salary", icon: "dollarsign.circle.fill", colorHex: "#34C759", type: .income),
        PredefinedCategory(nameKey: "category.investments", icon: "chart.line.uptrend.xyaxis", colorHex: "#007AFF", type: .income),
        // Trip, Saving, Gifts
        PredefinedCategory(nameKey: "category.trip", icon: "airplane", colorHex: "#FF9800", type: .expense),
        PredefinedCategory(nameKey: "category.saving", icon: "banknote.fill", colorHex: "#4CAF50", type: .expense),
        PredefinedCategory(nameKey: "category.giftsAndDonations", icon: "gift.fill", colorHex: "#E91E63", type: .expense)
    ]
}
