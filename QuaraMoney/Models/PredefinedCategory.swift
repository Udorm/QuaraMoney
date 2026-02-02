import Foundation
import SwiftData

struct PredefinedCategory {
    let name: String
    let icon: String
    let colorHex: String
    let type: TransactionType
    
    static let defaults: [PredefinedCategory] = [
        PredefinedCategory(name: "Food and drink", icon: "fork.knife", colorHex: "#FF9500", type: .expense), // Orange
        PredefinedCategory(name: "Housing", icon: "house.fill", colorHex: "#007AFF", type: .expense), // Blue
        PredefinedCategory(name: "Water bill", icon: "drop.fill", colorHex: "#5AC8FA", type: .expense), // Light Blue
        PredefinedCategory(name: "Electricity bill", icon: "bolt.fill", colorHex: "#FFCC00", type: .expense), // Yellow
        PredefinedCategory(name: "Internet bill", icon: "wifi", colorHex: "#5856D6", type: .expense), // Purple
        PredefinedCategory(name: "Subscriptions", icon: "play.tv.fill", colorHex: "#FF2D55", type: .expense), // Pink
        PredefinedCategory(name: "Transportation", icon: "car.fill", colorHex: "#34C759", type: .expense), // Green
        PredefinedCategory(name: "Personal & lifestyle", icon: "figure.walk", colorHex: "#AF52DE", type: .expense), // Indigo
        PredefinedCategory(name: "Health", icon: "heart.fill", colorHex: "#FF3B30", type: .expense), // Red
        PredefinedCategory(name: "Financial", icon: "banknote.fill", colorHex: "#8E8E93", type: .expense), // Gray
        PredefinedCategory(name: "Others", icon: "circle.grid.2x2.fill", colorHex: "#A2845E", type: .expense), // Olive
        // Also adding Income for completeness
        PredefinedCategory(name: "Salary", icon: "dollarsign.circle.fill", colorHex: "#34C759", type: .income),
        PredefinedCategory(name: "Investments", icon: "chart.line.uptrend.xyaxis", colorHex: "#007AFF", type: .income)
    ]
}
