import SwiftUI
import SwiftData

struct RecurringProgressHeaderView: View {
    @State private var viewModel: RecurringProgressViewModel
    
    init(modelContext: ModelContext) {
        _viewModel = State(wrappedValue: RecurringProgressViewModel(dataService: SwiftDataService(modelContext: modelContext), context: modelContext))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.Recurring.monthlyProgress)
                .font(.app(.headline))
                .foregroundStyle(.primary)
            
            if viewModel.expectedExpenses > 0 {
                progressRow(
                    title: L10n.Recurring.expenses,
                    paid: viewModel.paidExpenses,
                    expected: viewModel.expectedExpenses,
                    color: .red,
                    icon: "arrow.up.right"
                )
            }
            
            if viewModel.expectedIncome > 0 {
                progressRow(
                    title: L10n.Recurring.income,
                    paid: viewModel.receivedIncome,
                    expected: viewModel.expectedIncome,
                    color: .green,
                    icon: "arrow.down.left"
                )
            }
            
            if viewModel.expectedExpenses == 0 && viewModel.expectedIncome == 0 {
                Text(L10n.Recurring.noProgressThisMonth)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    @ViewBuilder
    private func progressRow(title: String, paid: Decimal, expected: Decimal, color: Color, icon: String) -> some View {
        let currencyCode = viewModel.preferredCurrencyCode
        let percentage = expected > 0 ? Double(NSDecimalNumber(decimal: paid).doubleValue / NSDecimalNumber(decimal: expected).doubleValue) : 0
        
        VStack(spacing: 6) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(color)
                
                Spacer()
                
                Text(L10n.Recurring.progressDetail(paid.formattedAmount(for: currencyCode), expected.formattedAmount(for: currencyCode)))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.2))
                        .frame(height: 6)
                    
                    Capsule()
                        .fill(color)
                        .frame(width: max(0, min(geometry.size.width * CGFloat(percentage), geometry.size.width)), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}
