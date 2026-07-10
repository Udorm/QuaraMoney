import SwiftUI
import Observation

/// Income/expense accent colors. `@Observable` so views that read only
/// `incomeColor` re-render only when that value changes (property-level
/// tracking), instead of on any published change as with ObservableObject —
/// and so reads from view `init`s (row views cache these) stay cheap.
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    var incomeColorHex: String {
        didSet { UserDefaults.standard.set(incomeColorHex, forKey: "incomeColorHex") }
    }
    var expenseColorHex: String {
        didSet { UserDefaults.standard.set(expenseColorHex, forKey: "expenseColorHex") }
    }

    private init() {
        incomeColorHex = UserDefaults.standard.string(forKey: "incomeColorHex") ?? "#34C759" // Default Green
        expenseColorHex = UserDefaults.standard.string(forKey: "expenseColorHex") ?? "#FF3B30" // Default Red
    }

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
