import SwiftUI
import SwiftData
import Charts

struct AnalysisView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = AnalysisViewModel()
    
    var body: some View {
        AnalysisContentView(vm: viewModel)
            .onAppear {
                viewModel.configure(modelContext: modelContext)
                viewModel.refreshData()
            }
    }
}

struct AnalysisContentView: View {
    @ObservedObject var vm: AnalysisViewModel
    
    // For Wallet Filter - We need to query wallets. 
    @Query(filter: #Predicate<Wallet> { !$0.isArchived }, sort: \Wallet.name) private var wallets: [Wallet]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Charts (Now includes the Period Picker)
                    SpendingTrendChart(vm: vm)
                    
                    if !vm.categoryStats.isEmpty {
                        CategoryBreakdownChart(vm: vm)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(L10n.Analysis.title)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AnalysisFilterSheetButton(
                        selectedTransactionType: $vm.selectedTransactionType,
                        selectedWallet: $vm.selectedWallet,
                        customStartDate: $vm.customStartDate,
                        customEndDate: $vm.customEndDate,
                        wallets: wallets
                    )
                }
            }
        }
    }
    
    @ViewBuilder
    private func OverviewSection(vm: AnalysisViewModel) -> some View {
        VStack(spacing: 16) {
            FinancialSummaryCards(income: vm.totalIncome, expense: vm.totalExpense)
                .padding(.horizontal)
        }
    }
}


struct SpendingTrendChart: View {
    @ObservedObject var vm: AnalysisViewModel
    @State private var dragOffset: CGFloat = 0
    @State private var slideDirection: Int = 0 // -1 = left, 0 = none, 1 = right
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Segmented Control
            Picker("Period", selection: $vm.selectedPeriod) {
                Text("D").tag(AnalysisPeriod.day)
                Text("W").tag(AnalysisPeriod.week)
                Text("M").tag(AnalysisPeriod.month)
                Text("6M").tag(AnalysisPeriod.sixMonths)
                Text("Y").tag(AnalysisPeriod.year)
                Text("LY").tag(AnalysisPeriod.lastYear)
            }
            .pickerStyle(.segmented)
            
            // 2. Header Stats with Navigation
            HStack {
                // Back Button
                Button {
                    slideDirection = 1
                    withAnimation(.easeInOut(duration: 0.3)) {
                        vm.navigateBack()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        slideDirection = 0
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .appFont(.title2)
                        .foregroundStyle(.secondary)
                }
                .disabled(vm.selectedPeriod == .custom)
                
                Spacer()
                
                VStack(spacing: 4) {
                    Text(vm.selectedTransactionType == .expense ? "analysis.totalSpending".localized : "analysis.totalIncome".localized)
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    let amount = vm.selectedTransactionType == .expense ? vm.totalExpense : vm.totalIncome
                    Text(amount.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode)))
                        .font(.app(.title, weight: .bold))
                        .foregroundStyle(Color.primary)
                    
                    Text(vm.filterDescription)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Forward Button
                Button {
                    slideDirection = -1
                    withAnimation(.easeInOut(duration: 0.3)) {
                        vm.navigateForward()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        slideDirection = 0
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .appFont(.title2)
                        .foregroundStyle(.secondary)
                }
                .disabled(vm.selectedPeriod == .custom)
            }
            .frame(height: 80)

            // 3. Chart with swipe navigation between periods
            chartContent
                .frame(height: 250)
                .contentShape(Rectangle())
                .offset(x: dragOffset)
                .opacity(1.0 - Double(abs(dragOffset)) / 300.0)
                .id(vm.currentReferenceDate) // Trigger transition on date change
                .transition(.asymmetric(
                    insertion: .move(edge: slideDirection >= 0 ? .leading : .trailing),
                    removal: .move(edge: slideDirection >= 0 ? .trailing : .leading)
                ))
                .animation(.easeInOut(duration: 0.3), value: vm.currentReferenceDate)
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            // Only track horizontal drags
                            if abs(value.translation.width) > abs(value.translation.height) {
                                dragOffset = value.translation.width * 0.5
                            }
                        }
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else {
                                withAnimation(.spring()) { dragOffset = 0 }
                                return
                            }
                            
                            if value.translation.width > 60 {
                                // Swipe right -> go back
                                slideDirection = 1
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    dragOffset = 0
                                    vm.navigateBack()
                                }
                            } else if value.translation.width < -60 {
                                // Swipe left -> go forward
                                slideDirection = -1
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    dragOffset = 0
                                    vm.navigateForward()
                                }
                            } else {
                                // Snap back
                                withAnimation(.spring()) {
                                    dragOffset = 0
                                }
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                slideDirection = 0
                            }
                        }
                )
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var chartContent: some View {
        if vm.dailyStats.isEmpty {
            AppEmptyStateView(
                "analysis.noData".localized,
                systemImage: "chart.bar",
                description: "analysis.noTransactionsForPeriod".localized
            )
        } else {
            Chart {
                ForEach(vm.dailyStats) { stat in
                    let amount = vm.selectedTransactionType == .expense ? stat.expense : stat.income
                    let color = vm.selectedTransactionType == .expense ? ThemeManager.shared.expenseColor : ThemeManager.shared.incomeColor
                    BarMark(
                        x: .value("Date", stat.date, unit: self.chartUnit),
                        y: .value("Amount", amount)
                    )
                    .foregroundStyle(color.gradient)
                    .cornerRadius(4)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: self.chartUnit, count: self.axisStrideCount)) { value in
                    AxisValueLabel(format: self.axisFormat, centered: true)
                        .font(.app(.caption2))
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.2))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.2))
                    AxisValueLabel()
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // Helpers
    
    var chartUnit: Calendar.Component {
        switch vm.grouping {
        case .hour: return .hour
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }
    
    var axisStrideCount: Int {
        // Customize stride based on the visible range (Period)
        switch vm.selectedPeriod {
        case .day: return 4 // Every 4 hours
        case .week: return 1 // Every day
        case .month: return 5 // Every 5 days
        case .sixMonths: return 1 // Every month
        case .year: return 1 // Every month
        case .lastYear: return 1
        case .custom: return 5
        }
    }
    
    var axisFormat: Date.FormatStyle {
        switch vm.selectedPeriod {
        case .day: return .dateTime.hour()
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day()
        case .sixMonths: return .dateTime.month(.abbreviated)
        case .year: return .dateTime.month(.abbreviated)
        case .lastYear: return .dateTime.month(.abbreviated)
        case .custom: return .dateTime.day().month()
        }
    }
    

}

struct CategoryBreakdownChart: View {
    @ObservedObject var vm: AnalysisViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(vm.selectedTransactionType == .expense ? "analysis.topSpendingCategories".localized : "analysis.topIncomeCategories".localized)
                    .font(.app(.headline))
                
                Spacer()
                
                Text(vm.filterDescription)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            
            LazyVStack(spacing: 0) {
                ForEach(vm.categoryStats.prefix(5)) { stat in
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: stat.category.icon.isEmpty ? "circle.fill" : stat.category.icon)
                                .appFont(.title3)
                                .foregroundStyle(Color(hex: stat.colorHex) ?? .blue)
                                .frame(width: 30)
                                
                            VStack(alignment: .leading) {
                                Text(stat.category.name)
                                    .font(.app(.subheadline, weight: .medium))
                                
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color(.systemGray4).opacity(0.5))
                                            .frame(height: 6)
                                        
                                        let maxAmount = vm.categoryStats.first?.amount ?? 1
                                        let ratio = maxAmount > 0 ? Double(truncating: stat.amount as NSNumber) / Double(truncating: maxAmount as NSNumber) : 0
                                        
                                        Capsule().fill(Color(hex: stat.colorHex) ?? .blue)
                                            .frame(width: geo.size.width * CGFloat(ratio), height: 6)
                                    }
                                }
                                .frame(height: 6)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text(stat.amount.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode)))
                                    .font(.app(.callout))
                                    .monospacedDigit()
                                
                                let total = vm.categoryStats.reduce(0) { $0 + $1.amount }
                                let percent = total > 0 ? Double(truncating: stat.amount as NSNumber) / Double(truncating: total as NSNumber) : 0
                                Text(percent.formatted(.percent.precision(.fractionLength(0))))
                                    .font(.app(.caption2))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        
                        Divider()
                            .padding(.leading, 40)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}
