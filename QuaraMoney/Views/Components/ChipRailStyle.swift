import SwiftUI

/// Styles a horizontal chip rail so it's obvious the row scrolls.
///
/// Two things are going on, and the first matters more than the second:
///
/// 1. **The rail bleeds to the screen edge.** A rail laid out inside the form's
///    horizontal padding ends its viewport `inset` points early, so a row of
///    chips can finish just short of that edge with a clean gap after it —
///    indistinguishable from a rail with nothing left to show. Cancelling the
///    ancestor's padding and re-applying it as scroll *content* margins keeps
///    the first chip aligned with everything else in the form while handing the
///    trailing edge those points back, which is usually enough for the next
///    chip to intrude. When content does get cut it's cut at the screen edge,
///    which reads as "continues off-screen" rather than "ends in a box".
///
/// 2. **A conditional fade** on whichever edge still has content past it. This
///    softens a mid-chip cut, but it cannot rescue a flush one on its own — over
///    a gap of background it fades nothing, and over a sliver of white chip it's
///    too subtle to notice. It supports the bleed; it doesn't replace it.
///
/// The gradient runs to `background.opacity(0)` rather than `.clear` so it holds
/// its hue: fading to `.clear` blends toward transparent black and greys the
/// chip on the way out.
struct ChipRailStyle: ViewModifier {
    /// The ancestor's horizontal padding, which this cancels and re-applies as
    /// content margins. Must match, or the first chip will misalign.
    var inset: CGFloat = 16
    /// The surface behind the rail; the fade dissolves into it.
    var background: Color = Color(.systemGroupedBackground)
    var fadeWidth: CGFloat = 28

    @State private var edges = ChipRailEdges()

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, inset, for: .scrollContent)
            .onScrollGeometryChange(for: ChipRailEdges.self) { geometry in
                // `visibleRect` is in content coordinates, so this holds with
                // the content margins applied above. Both supported languages
                // are LTR, so min/max map onto leading/trailing directly.
                ChipRailEdges(
                    leading: geometry.visibleRect.minX > 1,
                    trailing: geometry.visibleRect.maxX < geometry.contentSize.width - 1
                )
            } action: { _, newEdges in
                edges = newEdges
            }
            // Both overlays go on *before* the negative padding below. A
            // `.padding(-inset)` view reports its parent's width and lets the
            // scroll view overflow it, so an overlay attached afterwards would
            // pin itself to the old inset position — the fades would float
            // `inset` points shy of the bezel the rail actually reaches.
            .overlay(alignment: .leading) {
                fade(from: .leading, isVisible: edges.leading)
            }
            .overlay(alignment: .trailing) {
                fade(from: .trailing, isVisible: edges.trailing)
            }
            .padding(.horizontal, -inset)
    }

    private func fade(from edge: UnitPoint, isVisible: Bool) -> some View {
        LinearGradient(
            colors: [background, background.opacity(0)],
            startPoint: edge,
            endPoint: edge == .leading ? .trailing : .leading
        )
        .frame(width: fadeWidth)
        // Decoration only — the half-covered chip underneath stays tappable.
        .allowsHitTesting(false)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: isVisible)
    }
}

/// Which edges of a rail still have content past them.
struct ChipRailEdges: Equatable {
    var leading = false
    var trailing = false
}

extension View {
    /// Styles a horizontal chip rail for scroll legibility. Apply to the
    /// `ScrollView` itself, not to its content.
    /// - Parameter inset: the horizontal padding of the container this rail
    ///   sits in, which the rail bleeds past and re-applies as content margins.
    func chipRail(
        inset: CGFloat = 16,
        background: Color = Color(.systemGroupedBackground),
        fadeWidth: CGFloat = 28
    ) -> some View {
        modifier(ChipRailStyle(inset: inset, background: background, fadeWidth: fadeWidth))
    }
}
