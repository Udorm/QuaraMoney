import SwiftUI
import UIKit
import CoreText

// Internal use only
nonisolated private let khmerFontName = "MiSans Khmer VF"

// Cache for font descriptors to avoid repeated CoreText lookups.
// NSCache is thread-safe, so font construction can run off the main actor;
// `nonisolated(unsafe)` because NSCache isn't inferred Sendable (UIFont value type).
nonisolated(unsafe) private let fontCache = NSCache<NSString, UIFont>()

// MARK: - Font Weight Mapping

extension Font.Weight {
    /// Maps SwiftUI Font.Weight to variable font weight axis value (100-900)
    var variableFontValue: CGFloat {
        switch self {
        case .ultraLight: return 100
        case .thin: return 200
        case .light: return 300
        case .regular: return 400
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        case .black: return 900
        default: return 400
        }
    }
}

extension UIFont.Weight {
    /// Maps UIFont.Weight to variable font weight axis value (100-900)
    nonisolated var variableFontValue: CGFloat {
        switch self {
        case .ultraLight: return 100
        case .thin: return 200
        case .light: return 300
        case .regular: return 400
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        case .black: return 900
        default: return 400
        }
    }
}

// MARK: - Font Strategies

extension Font {
    
    /// Returns the appropriate font, strictly adhering to the Design System cascade.
    /// This should be used when you need a `Font` object.
    /// - Parameters:
    ///   - style: The SwiftUI Font TextStyle
    ///   - weight: The weight to apply
    static func app(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        let uiFontWeight = weight.toUIFontWeight()
        let size = textStyleSize(style)
        return Font(UIFont.appWithCascade(ofSize: size, weight: uiFontWeight))
    }
    
    /// Returns a custom sized font adhering to the Design System cascade.
    static func app(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let uiFontWeight = weight.toUIFontWeight()
        return Font(UIFont.appWithCascade(ofSize: size, weight: uiFontWeight))
    }

    /// Helper to determine size from TextStyle (standard iOS sizes)
    static func textStyleSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }
}

// MARK: - View Modifiers (The Explicit API)

extension View {

    /// Applies the Design System font. Use this instead of `.font(...)`.
    /// Guaranteed to respect the font cascade (System for Latin, Khmer for Khmer)
    /// AND to scale with the user's Dynamic Type setting.
    func appFont(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        modifier(AppFontModifier(size: Font.textStyleSize(style), weight: weight, referenceStyle: style.uiTextStyle))
    }

    /// Applies the Design System font with a custom size. Use this instead of `.font(.system(size: ...))`.
    /// Scales with Dynamic Type relative to the body text style.
    func appFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(AppFontModifier(size: size, weight: weight, referenceStyle: .body))
    }
}

/// Resolves the cascade font at a size scaled for the current Dynamic Type
/// setting. Reading `dynamicTypeSize` from the environment means the font is
/// recomputed whenever the user changes their text size. At the default size
/// (`.large`) the scale factor is 1.0, so existing layouts are unchanged.
private struct AppFontModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let size: CGFloat
    let weight: Font.Weight
    let referenceStyle: UIFont.TextStyle

    func body(content: Content) -> some View {
        let traits = UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory)
        let scaledSize = UIFontMetrics(forTextStyle: referenceStyle).scaledValue(for: size, compatibleWith: traits)
        return content.font(Font(UIFont.appWithCascade(ofSize: scaledSize, weight: weight.toUIFontWeight())))
    }
}

// MARK: - Dynamic Type bridging

private extension Font.TextStyle {
    /// The UIKit text style whose Dynamic Type scaling curve best matches.
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .body: return .body
        case .callout: return .callout
        case .subheadline: return .subheadline
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}

private extension DynamicTypeSize {
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

// MARK: - Font.Weight Extension

extension Font.Weight {
    func toUIFontWeight() -> UIFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}

// MARK: - UIKit Integration

extension UIFont {
    
    /// Creates a Khmer font with proper variable font weight support
    nonisolated static func khmerFont(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let cacheKey = "khmer-\(size)-\(weight.rawValue)" as NSString
        if let cached = fontCache.object(forKey: cacheKey) {
            return cached
        }
        
        // Try to create the variable font with weight axis
        guard let baseFont = UIFont(name: khmerFontName, size: size) else {
            // Fallback to system font if Khmer font not available
            return .systemFont(ofSize: size, weight: weight)
        }
        
        // For variable fonts, apply weight via variation axis
        // The "wght" axis tag as UInt32: 0x77676874
        let weightValue = weight.variableFontValue
        let wghtTag: UInt32 = 0x77676874  // "wght" in hex
        
        // Create variation dictionary with UInt32 key (CoreText standard)
        let variationDictionary: [UInt32: Any] = [
            wghtTag: weightValue
        ]
        
        // Create descriptor with variation attributes
        let variationAttributes: [UIFontDescriptor.AttributeName: Any] = [
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variationDictionary
        ]
        
        let descriptor = baseFont.fontDescriptor.addingAttributes(variationAttributes)
        let font = UIFont(descriptor: descriptor, size: size)
        
        fontCache.setObject(font, forKey: cacheKey)
        return font
    }
    
    /// Returns the appropriate font strictly adhering to Design System.
    static func app(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        return appWithCascade(ofSize: size, weight: weight)
    }
    
    /// Creates a font with proper cascade for mixed Khmer/Latin text.
    /// Works like CSS font-family: renders each character with the appropriate font.
    /// - Latin/symbols/numbers: System font (SF Pro) - PRIMARY
    /// - Khmer characters (U+1780–U+17FF): MiSans Khmer VF - FALLBACK
    nonisolated static func appWithCascade(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let cacheKey = "cascade-\(size)-\(weight.rawValue)" as NSString
        if let cached = fontCache.object(forKey: cacheKey) {
            return cached
        }
        
        // System font as PRIMARY for Latin characters
        let systemFont = UIFont.systemFont(ofSize: size, weight: weight)
        
        // Check if Khmer font is available
        guard let _ = UIFont(name: khmerFontName, size: size) else {
            return systemFont
        }
        
        // Get the properly weighted Khmer font as FALLBACK
        let khmerFont = UIFont.khmerFont(ofSize: size, weight: weight)
        let cascadeList = [khmerFont.fontDescriptor]
        
        // Create cascade: System PRIMARY, Khmer FALLBACK
        // This ensures English uses native SF Pro, and Khmer uses MiSans
        let combinedDescriptor = systemFont.fontDescriptor.addingAttributes([
            .cascadeList: cascadeList
        ])
        
        let result = UIFont(descriptor: combinedDescriptor, size: size)
        fontCache.setObject(result, forKey: cacheKey)
        return result
    }
    
    /// Updates global UIKit appearance proxies for navigation bars, tab bars, etc.
    static func setupAppAppearance() {
        // Create fonts with Khmer cascade
        let standardFont = UIFont.appWithCascade(ofSize: 17, weight: .regular)
        let largeFont = UIFont.appWithCascade(ofSize: 34, weight: .bold)
        let tabBarFont = UIFont.appWithCascade(ofSize: 10, weight: .medium)
        let segmentFont = UIFont.appWithCascade(ofSize: 13, weight: .medium)
        let segmentSelectedFont = UIFont.appWithCascade(ofSize: 13, weight: .semibold)
        
        // Navigation Bar
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithDefaultBackground()
        navBarAppearance.titleTextAttributes = [.font: standardFont]
        navBarAppearance.largeTitleTextAttributes = [.font: largeFont]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        
        // Tab Bar Appearance Configuration
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        
        let tabBarAttributes: [NSAttributedString.Key: Any] = [.font: tabBarFont]
        
        // Configure all layouts (Stacked for iPhone, Inline/Compact for iPad/Landscape)
        let layouts = [
            tabBarAppearance.stackedLayoutAppearance,
            tabBarAppearance.inlineLayoutAppearance,
            tabBarAppearance.compactInlineLayoutAppearance
        ]
        
        for layout in layouts {
            layout.normal.titleTextAttributes = tabBarAttributes
            layout.selected.titleTextAttributes = tabBarAttributes
        }
        
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        
        // Legacy/Direct Item Configuration (Reinforcement)
        UITabBarItem.appearance().setTitleTextAttributes(tabBarAttributes, for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes(tabBarAttributes, for: .selected)
        
        // Bar Button Items
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: standardFont], for: .normal)
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: standardFont], for: .highlighted)
        
        // Segmented Control
        UISegmentedControl.appearance().setTitleTextAttributes([.font: segmentFont], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: segmentSelectedFont], for: .selected)
    }
    
    /// Pre-warm the font cache on a background thread after first frame renders.
    /// NSCache is process-scoped and empty after app termination —
    /// this populates common sizes/weights early for smoother scrolling.
    static func prewarmFontCache() {
        Task.detached(priority: .background) {
            let sizes: [CGFloat] = [11, 12, 13, 15, 17, 22, 28, 34]
            let weights: [UIFont.Weight] = [.regular, .medium, .semibold, .bold]
            for size in sizes {
                for weight in weights {
                    // UIFont/descriptor creation is thread-safe for reads.
                    // Avoid dispatching back to MainActor — that causes
                    // micro-stutters during the critical first seconds.
                    _ = UIFont.appWithCascade(ofSize: size, weight: weight)
                }
            }
        }
    }
}

// MARK: - Custom Empty State View (Replacement for ContentUnavailableView)

/// A custom empty state view that supports the app's font cascade.
/// Use this instead of ContentUnavailableView for proper Khmer font support.
/// The app's single empty-state component. Mirrors the layout of the native
/// `ContentUnavailableView` but renders through the `.appFont` cascade so Khmer
/// text uses MiSans instead of the iOS fallback font. Prefer this over
/// `ContentUnavailableView` for primary empty states; the native
/// `ContentUnavailableView.search(text:)` idiom is still fine for search results.
struct AppEmptyStateView<Actions: View>: View {
    let title: String
    let systemImage: String
    let description: String?
    private let actions: Actions

    init(
        _ title: String,
        systemImage: String,
        description: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .appFont(size: 56)
                .foregroundStyle(.secondary)

            Text(title)
                .appFont(.title2, weight: .semibold)
                .multilineTextAlignment(.center)

            if let description = description {
                Text(description)
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            actions
                .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension AppEmptyStateView where Actions == EmptyView {
    /// Convenience for the common case with no action buttons.
    init(_ title: String, systemImage: String, description: String? = nil) {
        self.init(title, systemImage: systemImage, description: description) { EmptyView() }
    }
}