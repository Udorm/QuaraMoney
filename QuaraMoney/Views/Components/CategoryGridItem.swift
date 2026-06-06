import SwiftUI

struct CategoryGridItem: View {
    let category: Category
    let isSelected: Bool
    /// Marks the top contextual suggestion. Purely a visual hint — does not auto-select.
    var isHighlighted: Bool = false
    let action: () -> Void

    private var categoryColor: Color {
        Color(hex: category.colorHex) ?? .gray
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    // Selection ring for selected state
                    if isSelected {
                        Circle()
                            .stroke(categoryColor, lineWidth: 2)
                    } else if isHighlighted {
                        // Suggestion ring (dashed) — distinct from the solid selection ring
                        Circle()
                            .stroke(categoryColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    }

                    Image(systemName: category.icon)
                        .font(.app(.title3))
                        .foregroundColor(isSelected ? .white : categoryColor)
                        .frame(width: 40, height: 40)
                        .background(isSelected ? categoryColor : Color(.tertiarySystemGroupedBackground))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.secondary.opacity(0.2), lineWidth: isSelected ? 0 : 1)
                        )

                    // "Suggested" sparkle badge in the top-trailing corner
                    if isHighlighted && !isSelected {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(categoryColor)
                            .padding(3)
                            .background(Color(.secondarySystemGroupedBackground), in: Circle())
                            .offset(x: 18, y: -18)
                    }
                }
                .frame(width: 46, height: 46)

                Text(category.name)
                    .font(.app(.caption2, weight: isSelected ? .bold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? categoryColor : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isHighlighted ? "\(category.name), suggested" : category.name)
    }
}
