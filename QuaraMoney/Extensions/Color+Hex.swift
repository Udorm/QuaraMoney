import SwiftUI

/// Memoized `Color(hex:)` results.
///
/// Parsing is `trimmingCharacters` + `replacingOccurrences` + a `Scanner` — all
/// String work — and it runs from ~70 sites, including twice per transaction
/// row and once per cell in the category/wallet/color pickers. The distinct hex
/// values in play are the category and wallet palettes: a few dozen at most,
/// so the cache is small and never needs eviction.
///
/// `nil` results are cached too, so a malformed hex isn't re-parsed every frame.
private enum HexColorCache {
    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var colors: [String: Color?] = [:]

    nonisolated static func color(for hex: String) -> Color? {
        lock.lock()
        if let cached = colors[hex] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let parsed = Color(parsingHex: hex)

        lock.lock()
        colors[hex] = parsed
        lock.unlock()
        return parsed
    }
}

extension Color {
    /// Cached hex → `Color`. Callers should keep using this; the uncached parse
    /// lives in `init?(parsingHex:)`.
    init?(hex: String) {
        guard let color = HexColorCache.color(for: hex) else { return nil }
        self = color
    }

    /// The actual parse. Separate from `init?(hex:)` so the cache has something
    /// to call without recursing.
    fileprivate init?(parsingHex hex: String) {
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
