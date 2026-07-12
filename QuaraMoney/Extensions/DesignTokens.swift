import CoreGraphics

/// Canonical corner-radius scale. Introduced to absorb accidental one-off radii
/// (7, 9, 13, 26 px) that had crept in alongside the intentional values. New
/// code should reach for one of these tokens rather than a bare literal.
///
/// The intentional literals already in wide use (10 / 12 / 16 / 20 / 24) map to
/// `small` / `medium` / `large` / `card` / `hero`; those sites were left as-is
/// to keep the diff surgical, but the tokens are the forward-looking reference.
enum CornerRadius {
    /// Small icon tiles — e.g. the 28pt `ListIconView` squares. (Absorbs 7/9.)
    static let icon: CGFloat = 8
    static let small: CGFloat = 10
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    /// Standard content card.
    static let card: CGFloat = 20
    /// Large hero / onboarding surfaces. (Absorbs 26.)
    static let hero: CGFloat = 24
}
