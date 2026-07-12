import SwiftUI

/// Unified row component for selection UIs (filter sheets, picker sheets).
/// Replaces PeriodRow, WalletRow, and FilterOptionRow with a single consistent implementation.
struct SelectableRow: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    var iconColor: Color = .secondary
    let isSelected: Bool
    var selectionStyle: SelectionStyle = .checkmark
    let action: () -> Void

    enum SelectionStyle {
        /// Single-select: blue checkmark on the right when selected
        case checkmark
        /// Multi-select: circle when unselected, checkmark.circle.fill when selected
        case circleCheckmark
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(isSelected ? iconColor == .secondary ? .blue : iconColor : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(.body)
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            switch selectionStyle {
            case .checkmark:
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            case .circleCheckmark:
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
    }
}
