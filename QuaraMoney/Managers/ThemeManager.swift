import SwiftUI
import Combine

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @AppStorage("incomeColorHex") var incomeColorHex: String = "#34C759" // Default Green
    @AppStorage("expenseColorHex") var expenseColorHex: String = "#FF3B30" // Default Red
    
    var incomeColor: Color {
        Color(hex: incomeColorHex) ?? .green
    }
    
    var expenseColor: Color {
        Color(hex: expenseColorHex) ?? .red
    }
    
    func setIncomeColor(_ color: Color) {
        if let hex = color.toHex() {
            incomeColorHex = hex
        }
    }
    
    func setExpenseColor(_ color: Color) {
        if let hex = color.toHex() {
            expenseColorHex = hex
        }
    }
}
