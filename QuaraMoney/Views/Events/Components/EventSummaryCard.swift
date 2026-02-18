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
            .formatted(.currency(code: event.currencyCode))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                // Background
                RoundedRectangle(cornerRadius: 24)
                    .fill(eventColor.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(eventColor.opacity(0.2), lineWidth: 1)
                    )
                
                // Decorative Icon
                Image(systemName: event.icon)
                    .font(.system(size: 100))
                    .foregroundStyle(eventColor.opacity(0.08))
                    .offset(x: 200, y: 10)
                    .clipped()
                
                VStack(alignment: .leading, spacing: 16) {
                    // Top Row: Status + Remaining Pool
                    HStack {
                        EventSettlementStatusBadge(status: settlementStatus)
                        
                        Spacer()
                        
                        if remainingPool != 0 {
                            HStack(spacing: 4) {
                                Text("Pool:")
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                                Text(formatMinor(remainingPool))
                                    .font(.app(.caption, weight: .medium))
                                    .foregroundStyle(remainingPool >= 0 ? Color.green : Color.red)
                            }
                        }
                    }
                    
                    // Main Stats: Total Cost
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Cost")
                            .font(.app(.subheadline, weight: .medium))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        
                        Text(formatMinor(totalCost))
                            .font(.system(.largeTitle, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                    }
                    
                    Spacer(minLength: 0)
                    
                    // Integrated Buttons
                    HStack(spacing: 12) {
                        Button(action: onAddExpense) {
                            Label("Add Expense", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(eventColor)
                        .controlSize(.regular)
                        
                        if settlementStatus != .active {
                            Button(action: onSettle) {
                                Label("Settle", systemImage: "arrow.left.arrow.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(height: 190)
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
            .font(.app(.caption, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
