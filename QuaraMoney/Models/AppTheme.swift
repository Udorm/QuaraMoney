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
        "Finance": ["banknote", "creditcard", "wallet.pass", "chart.pie", "chart.bar", "indianrupeesign.circle", "dollarsign.circle", "eurosign.circle", "yensign.circle", "sterlingsign.circle", "bitcoinsign.circle", "signature", "receipt", "building.columns"],
        "Essentials": ["house", "cart", "bag", "basket", "gift", "shippingbox", "crown", "tshirt", "lightbulb", "faucet", "drop", "leaf", "snow", "umbrella", "key", "lock"],
        "Food & Drink": ["fork.knife", "cup.and.saucer", "wineglass", "carrot", "birthday.cake", "takeoutbag.and.cup.and.fork.knife", "fish", "mug", "popcorn", "cookie", "birthday.cake", "flame"],
        "Transport": ["car", "bus", "tram", "train.side.front.car", "airplane", "fuelpump", "bicycle", "figure.walk", "sailboat", "ferry", "car.ferry", "cablecar", "scooter"],
        "Services": ["cross.case", "pills", "bandage", "stethoscope", "bolt", "drop", "flame", "wifi", "hammer", "wrench.and.screwdriver", "gear", "scissors", "comb", "paintbrush"],
        "Leisure": ["gamecontroller", "theatermasks", "ticket", "popcorn", "dumbbell", "figure.run", "tent", "camera", "music.note", "guitars", "pianokeys", "paintpalette", "party.popper", "balloon", "beach.umbrella", "binoculars"],
        "Education": ["book", "graduationcap", "pencil.and.ruler", "backpack", "studentdesk", "text.book.closed", "books.vertical", "highlighter", "paperclip", "folder"],
        "Tech": ["desktopcomputer", "laptopcomputer", "iphone", "ipad", "headphones", "printer", "keyboard", "mouse", "applewatch", "tv", "camera.macro", "video", "mic"],
        "Misc": ["list.bullet", "star", "heart", "flag", "tag", "paperclip", "briefcase", "hammer", "globe", "map", "location", "clock", "alarm", "hourglass", "calendar", "bell", "bookmark", "person", "person.2", "person.3", "pawprint", "leaf.arrow.circlepath", "trash"]
    ]
    
    // Flattened list for simple pickers if needed
    static var allIcons: [String] {
        icons.flatMap { $0.value }
    }
}
