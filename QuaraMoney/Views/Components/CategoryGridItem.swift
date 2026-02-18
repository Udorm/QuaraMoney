import SwiftUI

struct CategoryGridItem: View {
    let category: Category
    let isSelected: Bool
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
                            .frame(width: 46, height: 46)
                    }
                    
                    Image(systemName: category.icon)
                        .font(.app(.title3))
                        .foregroundColor(isSelected ? .white : categoryColor)
                        .frame(width: 40, height: 40)
                        .background(isSelected ? categoryColor : Color(.tertiarySystemGroupedBackground))
                        .clipShape(Circle())
                        .overlay(
                            // Optional: subtle border for unselected to make them distinct from background
                            Circle()
                                .stroke(Color.secondary.opacity(0.2), lineWidth: isSelected ? 0 : 1)
                        )
                }
                
                Text(category.name)
                    .font(.app(.caption2, weight: isSelected ? .bold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? categoryColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
