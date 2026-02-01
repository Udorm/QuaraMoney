import SwiftUI

struct AppTheme {
    static let colors: [String] = [
        "#FF3B30", // Red
        "#FF9500", // Orange
        "#FFCC00", // Yellow
        "#4CD964", // Green
        "#5AC8FA", // Light Blue
        "#007AFF", // Blue
        "#5856D6", // Purple
        "#FF2D55", // Pink
        "#8E8E93", // Gray
        "#C69C6D", // Brown
        "#34C759", // Mint
        "#AF52DE", // Indigo
        "#FF2C55", // Hot Pink
        "#5E5CE6", // Violet
        "#32ADE6", // Teal
        "#30B0C7", // Cyan
        "#A2845E"  // Olive
    ]
    
    static let icons: [String: [String]] = [
        "Finance": ["banknote", "creditcard", "wallet.pass", "chart.pie", "chart.bar", "indianrupeesign.circle", "dollarsign.circle", "eurosign.circle"],
        "Essentials": ["house", "cart", "bag", "basket", "gift", "shippingbox", "crown", "tshirt"],
        "Food & Drink": ["fork.knife", "cup.and.saucer", "wineglass", "carrot", "birthday.cake", "takeoutbag.and.cup.and.fork.knife", "fish"],
        "Transport": ["car", "bus", "tram", "train.side.front.car", "airplane", "fuelpump", "bicycle", "figure.walk"],
        "Services": ["cross.case", "pills", "bandage", "stethoscope", "bolt", "drop", "flame", "wifi"],
        "Leisure": ["gamecontroller", "theatermasks", "ticket", "popcorn", "dumbbell", "figure.run", "tent", "camera"],
        "Education": ["book", "graduationcap", "pencil.and.ruler", "backpack", "studentdesk", "text.book.closed"],
        "Tech": ["desktopcomputer", "laptopcomputer", "iphone", "ipad", "headphones", "printer", "keyboard"],
        "Misc": ["list.bullet", "star", "heart", "flag", "tag", "paperclip", "briefcase", "hammer"]
    ]
    
    // Flattened list for simple pickers if needed
    static var allIcons: [String] {
        icons.flatMap { $0.value }
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        let length = hexSanitized.count

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0

        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0

        } else {
            return nil
        }

        self.init(red: r, green: g, blue: b, opacity: a)
    }
    
    func toHex() -> String? {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return nil
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)
        
        if components.count >= 4 {
            a = Float(components[3])
        }
        
        if a != 1.0 {
            return String(format: "#%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }
}
