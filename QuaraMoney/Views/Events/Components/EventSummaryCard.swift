import SwiftUI

struct EventSummaryCard: View {
    let event: Event
    let totalCost: Int64
    let userNetBalance: Int64
    let remainingPool: Int64
    let settlementStatus: EventSettlementStatus
    let onAddExpense: () -> Void
    let onSettle: () -> Void
    
    private var eventColor: Color {
        Color(hex: event.colorHex) ?? .blue
    }
    
    private func formatMinor(_ value: Int64) -> String {
        MoneyMinorUnitConverter
            .fromMinorUnits(value, currencyCode: event.currencyCode)
            .formattedAmount(for: event.currencyCode)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Top Row: Status + Remaining Pool
            HStack {
                EventSettlementStatusBadge(status: settlementStatus)
                
                Spacer()
                
                if remainingPool != 0 {
                    HStack(spacing: 4) {
                        Text("Pool:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatMinor(remainingPool))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(remainingPool >= 0 ? Color.green : Color.red)
                    }
                }
            }
            
            // Main Stats: Total Cost
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.EventSettlement.totalCost)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                Text(formatMinor(totalCost))
                    .appFont(size: 34, weight: .bold)
                    .foregroundStyle(.primary)
            }
            
            // Integrated Buttons
            HStack(spacing: 12) {
                Button(action: onAddExpense) {
                    Text(L10n.EventAdditional.summaryAddExpense)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(eventColor)
                .controlSize(.regular)
                
                if settlementStatus != .active {
                    Button(action: onSettle) {
                        Text(L10n.EventAdditional.summarySettle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        }
    }
}

// Reusing badge from v1 (extracted or redefined locally if private)
private struct EventSettlementStatusBadge: View {
    let status: EventSettlementStatus
    
    private var label: String {
        switch status {
        case .active: return "Active"
        case .readyToSettle: return "Ready to Settle"
        case .settled: return "Settled"
        }
    }
    
    private var color: Color {
        switch status {
        case .active: return .secondary
        case .readyToSettle: return .orange
        case .settled: return .green
        }
    }
    
    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
