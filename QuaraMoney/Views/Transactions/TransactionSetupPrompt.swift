import SwiftUI

/// Actionable empty-state prompt shown in the Add/Edit Transaction screens when
/// the user has no wallets, or no categories for the current type. Rather than a
/// dead-end "nothing here" label, it guides the user to create the missing
/// prerequisite (wallet/category) inline — the whole row is tappable and the
/// trailing pill echoes the primary action.
///
/// Background-free by design so it adapts to its container: it inherits the grouped
/// list-row fill in the classic form, and the compact card layout wraps it in its
/// own card background.
struct TransactionSetupPrompt: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.primary)
                    Text(message)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(actionTitle)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(tint, in: Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(actionTitle)")
        .accessibilityAddTraits(.isButton)
    }
}
