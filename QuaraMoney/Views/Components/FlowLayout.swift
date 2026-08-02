import SwiftUI

/// Wraps subviews left-to-right, moving to a new row when the current row overflows the available width.
///
/// Subviews are measured *and* placed against the container width, so an item
/// that would be wider than a full row (a long note, a long place name) is
/// proposed the row width and truncates/wraps inside itself. The reported size
/// never exceeds the proposed width — otherwise a single oversized chip widens
/// the whole enclosing layout and pushes its siblings off screen.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        FlowResult(in: proposal.width, subviews: subviews, spacing: spacing).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            let frame = result.frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []

        init(in proposedWidth: CGFloat?, subviews: Subviews, spacing: CGFloat) {
            // A zero/absent proposal means the parent is only probing for an
            // ideal size — fall back to one unconstrained row.
            let maxWidth: CGFloat
            if let proposedWidth, proposedWidth.isFinite, proposedWidth > 0 {
                maxWidth = proposedWidth
            } else {
                maxWidth = .infinity
            }
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            var widestRow: CGFloat = 0

            for subview in subviews {
                // Ideal width first, so an item only takes the room it needs
                // (measuring against the row width would make every flexible
                // subview greedy and break the packing), then clamp to the row.
                let ideal = subview.sizeThatFits(.unspecified)
                let width = min(ideal.width, maxWidth)
                let height = width < ideal.width
                    ? subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
                    : ideal.height
                let itemSize = CGSize(width: width, height: height)

                if x > 0 && x + itemSize.width > maxWidth {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                frames.append(CGRect(x: x, y: y, width: itemSize.width, height: itemSize.height))
                rowHeight = max(rowHeight, itemSize.height)
                x += itemSize.width + spacing
                widestRow = max(widestRow, x - spacing)
            }

            size = CGSize(width: min(widestRow, maxWidth), height: y + rowHeight)
        }
    }
}
