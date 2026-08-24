import SwiftUI

// MARK: - DebtType presentation helpers

extension DebtType {
    /// Accent color: green when money flows toward the user, red when away.
    var accentColor: Color {
        switch self {
        case .owedToMe: return .green
        case .iOwe: return .red
        }
    }

    /// Directional glyph for the small status badge on avatars / rows.
    var directionIcon: String {
        switch self {
        case .owedToMe: return "arrow.down.left"
        case .iOwe: return "arrow.up.right"
        }
    }

    /// Localized title used throughout the redesigned screens.
    var localizedTitle: String {
        switch self {
        case .owedToMe: return L10n.Debt.owedToMe
        case .iOwe: return L10n.Debt.iOwe
        }
    }

    /// Short relationship phrase, e.g. "Owes you" / "You owe".
    var relationshipPhrase: String {
        switch self {
        case .owedToMe: return "debt.owesYou".localized
        case .iOwe: return "debt.youOwe".localized
        }
    }
}

// MARK: - Card container (mirrors ProCard surface)

/// Grouped card matching the app's analytics / Pro-dashboard surfaces.
struct DebtCard<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }
}

// MARK: - Avatar

/// Monogram avatar tinted by debt direction, with a small directional badge or checkmark.
struct DebtAvatar: View {
    let name: String
    let type: DebtType
    var isCompleted: Bool = false
    var size: CGFloat = 44

    private var initials: String {
        let parts = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        let joined = letters.joined().uppercased()
        return joined.isEmpty ? "?" : joined
    }

    private var avatarColor: Color {
        isCompleted ? .secondary : type.accentColor
    }

    var body: some View {
        Circle()
            .fill(avatarColor.opacity(isCompleted ? 0.1 : 0.15))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .appFont(size: size * 0.38, weight: .semibold)
                    .foregroundStyle(avatarColor)
            }
            .overlay(alignment: .bottomTrailing) {
                if !isCompleted {
                    Image(systemName: type.directionIcon)
                        .appFont(size: size * 0.26, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: size * 0.42, height: size * 0.42)
                        .background(Circle().fill(type.accentColor))
                        .overlay(
                            Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 1.5)
                        )
                        .offset(x: 2, y: 2)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Progress bar

/// Slim, rounded repayment-progress bar.
struct DebtProgressBar: View {
    let progress: Double          // 0...1
    let tint: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Due-date chip

/// Compact due-date / overdue indicator.
struct DebtDueChip: View {
    let debt: Debt

    var body: some View {
        if debt.isCompleted {
            label(text: "debt.settled".localized, systemImage: "checkmark.circle.fill", color: .green)
        } else if debt.isOverdue, let due = debt.dueDate {
            label(text: "\("debt.overdue".localized) · \(due.appFormatted(date: .abbreviated, time: .omitted))",
                  systemImage: "exclamationmark.circle.fill", color: .red)
        } else if let due = debt.dueDate {
            label(text: "\("debt.due".localized) \(due.appFormatted(date: .abbreviated, time: .omitted))",
                  systemImage: "calendar", color: .secondary)
        } else {
            label(text: "debt.noDueDate".localized, systemImage: "calendar", color: .secondary)
        }
    }

    private func label(text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .appFont(size: 11, weight: .semibold)
            Text(text)
                .appFont(.caption2, weight: .medium)
        }
        .foregroundStyle(color)
    }
}

// MARK: - Debt Row (Redesigned for Active & Settled States)

struct DebtRow: View {
    let debt: Debt

    private var isPartiallyPaid: Bool {
        !debt.isCompleted && debt.amountPaid > 0 && debt.progress < 1
    }

    private var dateText: String {
        let date = debt.dueDate ?? debt.principalTransaction?.date ?? debt.dateCreated
        return date.appFormatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        HStack(spacing: 12) {
            DebtAvatar(name: debt.personName, type: debt.type, isCompleted: debt.isCompleted)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(debt.personName)
                        .appFont(.body, weight: .semibold)
                        .foregroundStyle(debt.isCompleted ? .secondary : .primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    // Total / original amount
                    Text(debt.currentTotalAmount.formattedAmount(for: debt.currencyCode))
                        .appFont(.body, weight: .bold)
                        .foregroundStyle(debt.isCompleted ? .secondary : debt.type.accentColor)
                        .lineLimit(1)
                }

                if isPartiallyPaid {
                    DebtProgressBar(progress: debt.progress, tint: debt.type.accentColor, height: 5)
                        .padding(.vertical, 1)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if debt.isCompleted {
                        // Left (below main title): Date
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .appFont(size: 11, weight: .medium)
                            Text(dateText)
                                .appFont(.caption2, weight: .medium)
                        }
                        .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        // Right (below amount): Settled status
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .appFont(size: 11, weight: .semibold)
                            Text("debt.settled".localized)
                                .appFont(.caption2, weight: .semibold)
                        }
                        .foregroundStyle(.green)
                    } else {
                        DebtDueChip(debt: debt)

                        Spacer(minLength: 8)

                        if isPartiallyPaid {
                            Text("debt.row.partiallyPaid".localized(
                                with: debt.amountPaid.formattedAmount(for: debt.currencyCode),
                                debt.displayRemaining.formattedAmount(for: debt.currencyCode)
                            ))
                            .appFont(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        } else {
                            // Show date under amount when no progress yet
                            Text(dateText)
                                .appFont(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        if debt.isCompleted {
            return "\(debt.personName), \("debt.settled".localized), \(debt.currentTotalAmount.formattedAmount(for: debt.currencyCode)), \(dateText)"
        } else {
            return "\(debt.personName), \(debt.type.relationshipPhrase) \(debt.currentTotalAmount.formattedAmount(for: debt.currencyCode))"
        }
    }
}

// MARK: - Debt Transaction Row (Single Group with Date instead of Time)

struct DebtTransactionRow: View {
    let transaction: Transaction

    private var isIncome: Bool {
        transaction.type == .income
    }

    private var amountColor: Color {
        isIncome ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    private var amountPrefix: String {
        isIncome ? "+" : "-"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((Color(hex: transaction.category?.colorHex ?? "#8E8E93") ?? .gray).opacity(0.12))
                    .frame(width: 36, height: 36)

                Image(systemName: transaction.category?.icon ?? (isIncome ? "arrow.down.circle.fill" : "arrow.up.circle.fill"))
                    .appFont(.subheadline)
                    .foregroundStyle(Color(hex: transaction.category?.colorHex ?? "#8E8E93") ?? .gray)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.category?.displayName ?? transaction.note ?? "transaction.uncategorized".localized)
                    .appFont(.subheadline, weight: .medium)
                    .lineLimit(1)

                if let note = transaction.note, !note.isEmpty, note != transaction.category?.displayName {
                    Text(note)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let wallet = transaction.sourceWallet {
                    Text(wallet.name)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(amountPrefix)\(transaction.amount.formattedAmount(for: transaction.currencyCode))")
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(amountColor)
                    .monospacedDigit()
                    .lineLimit(1)

                Text(transaction.date.appFormatted(date: .abbreviated, time: .omitted))
                    .appFont(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

// MARK: - Action button press style

struct DebtQuickActionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Debt-anchor deletion guard

extension View {
    /// Presents the "can't delete a debt's anchor transaction from here" alert.
    /// Bound to a `String?` message that a view model sets when a blocked
    /// deletion is attempted; clearing it dismisses the alert.
    func debtDeletionBlockedAlert(_ message: Binding<String?>) -> some View {
        alert(
            "debt.linkedTransaction".localized,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            ),
            presenting: message.wrappedValue
        ) { _ in
            Button(L10n.Common.ok, role: .cancel) {}
        } message: { text in
            Text(text)
        }
    }
}

// MARK: - Wallet chip row

/// Horizontal scrolling wallet selector matching the Add Transaction screen,
/// with an optional "track only" (no wallet) chip.
struct DebtWalletChips: View {
    let wallets: [Wallet]
    @Binding var selectedWallet: Wallet?
    var allowNone: Bool = true
    var noneTitle: String = "debt.trackOnly".localized
    var onChange: (() -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if allowNone {
                    noneChip
                }
                ForEach(wallets) { wallet in
                    WalletChip(
                        wallet: wallet,
                        isSelected: selectedWallet?.id == wallet.id
                    ) {
                        HapticManager.shared.selection()
                        selectedWallet = wallet
                        onChange?()
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var noneChip: some View {
        let isSelected = selectedWallet == nil
        return Button {
            HapticManager.shared.selection()
            selectedWallet = nil
            onChange?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tray")
                    .appFont(.caption2)
                Text(noneTitle)
                    .appFont(.subheadline, weight: .medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(.tertiarySystemGroupedBackground))
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
