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
                return "Contribution"
            }
            return transaction.categoryName ?? "Uncategorized"
        case .wallet(let transaction, _):
            return transaction.category?.name
            ?? (transaction.type == .transfer
                ? "Transfer"
                : (transaction.type == .adjustment ? "Balance Adjustment" : (transaction.note ?? "Uncategorized")))
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
    
    var body: some View {
        HStack {
            ZStack {
                Circle()
                    .fill((Color(hex: iconColorHex) ?? .gray).opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: iconName)
                    .font(.app(.body))
                    .foregroundStyle(Color(hex: iconColorHex) ?? .gray)
            }
            
            VStack(alignment: .leading) {
                Text(titleText)
                    .font(.app(.body, weight: .medium))
                
                if let subtitleText {
                    Text(subtitleText)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
                

                
                if let debt {
                    HStack(spacing: 4) {
                        Image(systemName: debt.type == .owedToMe ? "arrow.up.right" : "arrow.down.left")
                        Text(debt.personName)
                    }
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
                    .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text(amountText)
                    .font(.app(.body, weight: .semibold))
                    .foregroundStyle(isPositive ? incomeColor : expenseColor)
                
                Text(timeText)
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titleText), \(amountText), \(timeText)\(subtitleText.map { ", \($0)" } ?? "")")
    }
}
