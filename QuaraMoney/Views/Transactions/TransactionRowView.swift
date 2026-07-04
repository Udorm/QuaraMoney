import SwiftUI
import SwiftData

struct TransactionRowView: View {
    private enum Source {
        case wallet(Transaction, Wallet?)
        case event(EventLedgerTransaction, paidByName: String, participantCount: Int, currencyCode: String)
    }
    
    private let source: Source
    
    // Cache theme colors for performance
    private let incomeColor: Color
    private let expenseColor: Color
    
    init(transaction: Transaction, contextWallet: Wallet? = nil) {
        self.source = .wallet(transaction, contextWallet)
        self.incomeColor = ThemeManager.shared.incomeColor
        self.expenseColor = ThemeManager.shared.expenseColor
    }
    
    init(eventTransaction: EventLedgerTransaction, paidByName: String, participantCount: Int, currencyCode: String) {
        self.source = .event(eventTransaction, paidByName: paidByName, participantCount: participantCount, currencyCode: currencyCode)
        self.incomeColor = ThemeManager.shared.incomeColor
        self.expenseColor = ThemeManager.shared.expenseColor
    }
    
    private var isPositive: Bool {
        switch source {
        case .event(let transaction, _, _, _):
            return transaction.kind == .contribution
        case .wallet(let transaction, let contextWallet):
            if transaction.type == .income { return true }
            if transaction.type == .expense { return false }
            if transaction.type == .transfer {
                if let context = contextWallet, let dest = transaction.destinationWallet, dest.id == context.id {
                    return true
                }
                return false
            }
            if transaction.type == .adjustment {
                return transaction.amount >= 0
            }
            return false
        }
    }
    
    private var iconName: String {
        switch source {
        case .event(let transaction, _, _, _):
            if transaction.kind == .contribution {
                return "tray.and.arrow.down.fill"
            }
            return transaction.categoryIcon ?? "arrow.up.circle.fill"
        case .wallet(let transaction, _):
            return transaction.category?.icon
            ?? (transaction.type == .income
                ? "arrow.down.circle.fill"
                : (transaction.type == .transfer
                    ? "arrow.left.arrow.right"
                    : (transaction.type == .adjustment ? "slider.horizontal.3" : "arrow.up.circle.fill")))
        }
    }
    
    private var iconColorHex: String {
        switch source {
        case .event(let transaction, _, _, _):
            if transaction.kind == .contribution {
                return "#34C759"
            }
            return transaction.categoryColorHex ?? "#8E8E93"
        case .wallet(let transaction, _):
            return transaction.category?.colorHex
            ?? (transaction.type == .adjustment ? "#FF9500" : "#8E8E93")
        }
    }
    
    private var titleText: String {
        switch source {
        case .event(let transaction, _, _, _):
            if transaction.kind == .contribution {
                return "event.transaction.tabContribution".localized
            }
            return transaction.categoryName ?? "transaction.uncategorized".localized
        case .wallet(let transaction, _):
            return transaction.category?.name
            ?? (transaction.type == .transfer
                ? "transaction.type.transfer".localized
                : (transaction.type == .adjustment ? "transaction.balanceAdjustment".localized : (transaction.note ?? "transaction.uncategorized".localized)))
        }
    }
    
    private var subtitleText: String? {
        var text: String?
        switch source {
        case .event(let transaction, _, _, _):
            if let note = transaction.note, !note.isEmpty {
                text = note
            }
        case .wallet(let transaction, _):
            if let note = transaction.note, !note.isEmpty {
                text = note
            }
        }
        
        if let meta = eventMeta {
            if let existing = text {
                return "\(existing) • \(meta)"
            }
            return meta
        }
        
        return text
    }
    
    private var amountText: String {
        switch source {
        case .event(let transaction, _, _, let currencyCode):
            let amount = MoneyMinorUnitConverter.fromMinorUnits(transaction.amountMinor, currencyCode: currencyCode)
            return "\(isPositive ? "+" : "-")\(amount.formattedAmount(for: currencyCode))"
        case .wallet(let transaction, _):
            return "\(isPositive ? "+" : "-")\(transaction.amount.formattedAmount(for: transaction.currencyCode))"
        }
    }
    
    private var timeText: String {
        switch source {
        case .event(let transaction, _, _, _):
            return transaction.date.formatted(date: .omitted, time: .shortened)
        case .wallet(let transaction, _):
            return transaction.date.formatted(date: .omitted, time: .shortened)
        }
    }
    
    private var debt: Debt? {
        guard case let .wallet(transaction, _) = source else { return nil }
        return transaction.debt
    }
    
    private var eventMeta: String? {
        guard case let .event(_, paidByName, _, _) = source else { return nil }
        // Just return the name directly as requested
        return paidByName
    }
    
    private var hasMetaLine: Bool {
        debt != nil || subtitleText != nil
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((Color(hex: iconColorHex) ?? .gray).opacity(0.1))
                    .frame(width: 34, height: 34)

                Image(systemName: iconName)
                    .font(.app(.subheadline))
                    .foregroundStyle(Color(hex: iconColorHex) ?? .gray)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.app(.subheadline, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if hasMetaLine {
                    HStack(spacing: 4) {
                        if let debt {
                            debtBadge(debt)
                        }

                        if let subtitleText {
                            Text(subtitleText)
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText)
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(isPositive ? incomeColor : expenseColor)
                    .lineLimit(1)

                Text(timeText)
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titleText), \(amountText), \(timeText)\(subtitleText.map { ", \($0)" } ?? "")")
    }

    @ViewBuilder
    private func debtBadge(_ debt: Debt) -> some View {
        HStack(spacing: 3) {
            Image(systemName: debt.type.directionIcon)
                .font(.system(size: 9, weight: .bold))
            Text(debt.personName)
                .font(.app(.caption2, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(debt.type.accentColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(debt.type.accentColor.opacity(0.12), in: Capsule())
        .layoutPriority(1)
    }
}
