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
    @State private var showCustomDateSheet = false
    
    // For Wallet Filter - We need to query wallets. 
    // Since we are inside a view, we can use @Query.
    @Query(sort: \Wallet.name) private var wallets: [Wallet]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Filter Description Header (Matching HomeView)
                    Text(vm.filterDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 4)

                    // Overview Cards
                    OverviewSection(vm: vm)
                    
                    // Charts
                    if !vm.dailyStats.isEmpty {
                        SpendingTrendChart(vm: vm)
                    }
                    
                    if !vm.categoryStats.isEmpty {
                        CategoryBreakdownChart(vm: vm)
                    } else {
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "chart.pie",
                            description: Text("No expenses found for this period.")
                        )
                        .padding(.vertical, 40)
                    }
                }
                .padding()
            }
            .navigationTitle("Financial Analysis")
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Period") {
                            ForEach(AnalysisViewModel.Period.allCases) { period in
                                Button {
                                    if period == .custom {
                                        showCustomDateSheet = true
                                    } else {
                                        vm.selectedPeriod = period
                                    }
                                } label: {
                                    if vm.selectedPeriod == period {
                                        Label(period.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(period.rawValue)
                                    }
                                }
                            }
                        }
                        
                        Section("Wallet") {
                            Button {
                                vm.selectedWallet = nil
                            } label: {
                                if vm.selectedWallet == nil {
                                    Label("All Wallets", systemImage: "checkmark")
                                } else {
                                    Text("All Wallets")
                                }
                            }
                            
                            ForEach(wallets) { wallet in
                                Button {
                                    vm.selectedWallet = wallet
                                } label: {
                                    if vm.selectedWallet?.id == wallet.id {
                                        Label(wallet.name, systemImage: "checkmark")
                                    } else {
                                        Text(wallet.name)
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: vm.isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.title3)
                            .foregroundStyle(vm.isFilterActive ? .blue : .primary)
                    }
                }
            }


            .sheet(isPresented: $showCustomDateSheet) {
                NavigationStack {
                    Form {
                        DatePicker("Start Date", selection: Binding(
                            get: { vm.customStartDate },
                            set: { vm.customStartDate = $0 }
                        ), displayedComponents: .date)
                        
                        DatePicker("End Date", selection: Binding(
                            get: { vm.customEndDate },
                            set: { vm.customEndDate = $0 }
                        ), displayedComponents: .date)
                    }
                    .navigationTitle("Custom Range")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                vm.selectedPeriod = .custom
                                showCustomDateSheet = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
    
    @ViewBuilder
    private func OverviewSection(vm: AnalysisViewModel) -> some View {
        VStack(spacing: 16) {
            // Net Worth Card - Hero Style
            VStack(alignment: .leading, spacing: 8) {
                Text("Net Worth")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .textCase(.uppercase)
                
                HStack(alignment: .lastTextBaseline) {
                    Text(vm.netWorth.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode)))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.blue.gradient)
            .cornerRadius(16)
            .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
            
            // Vibrant Cards Grid (Income, Expense, Savings)
            HStack(spacing: 12) {
                AnalysisSummaryCard(
                    title: "Income",
                    amount: vm.totalIncome,
                    color: .green,
                    icon: "arrow.down"
                )
                
                AnalysisSummaryCard(
                    title: "Expense",
                    amount: vm.totalExpense,
                    color: .red,
                    icon: "arrow.up"
                )
                
                AnalysisSummaryCard(
                    title: "Savings",
                    amount: vm.totalIncome - vm.totalExpense,
                    color: .orange,
                    icon: "leaf.fill"
                )
            }
        }
    }
}

struct AnalysisSummaryCard: View {
    let title: String
    let amount: Decimal
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption.bold())
                    .foregroundStyle(color)
                    .padding(6)
                    .background(.white.opacity(0.9)) // Contrast against colored bg
                    .clipShape(Circle())
                
                Spacer()
            }
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .textCase(.uppercase)
                .fontWeight(.medium)
            
            Text(amount.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode)))
                .font(.system(.callout, design: .rounded)) 
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading) // Fill available width
        .background(color.gradient) // Vibrant Gradient Background
        .cornerRadius(16)
        .shadow(color: color.opacity(0.3), radius: 6, x: 0, y: 4)
    }
}

struct SpendingTrendChart: View {
    @ObservedObject var vm: AnalysisViewModel
    @State private var selectedDate: Date?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: Net Flow
            VStack(alignment: .leading, spacing: 4) {
               Text("Net Flow")
                   .font(.subheadline)
                   .foregroundStyle(.secondary)
               
               let totalNet = vm.totalIncome - vm.totalExpense
               Text(totalNet.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode)))
                   .font(.title2.bold())
                   .foregroundStyle(totalNet >= 0 ? Color.primary : Color.red)
           }
           .padding(.horizontal)

            // Selection Details
            VStack(alignment: .leading, spacing: 4) {
                if let selected = selectedDate, let stat = vm.dailyStats.first(where: { self.isSamePeriod($0.date, as: selected) }) {
                     Text("\(self.formatPeriod(stat.date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                            Text(stat.income.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode)))
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                            Text(stat.expense.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode)))
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                    }
                } else {
                    Text("Select a bar to view inflow & outflow")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                Chart {
                    ForEach(vm.dailyStats) { stat in
                        // Income Bar
                        BarMark(
                            x: .value("Date", stat.date, unit: vm.grouping == .monthly ? .month : .day),
                            y: .value("Amount", stat.income)
                        )
                        .foregroundStyle(Color.green.gradient)
                        .cornerRadius(4)
                        
                        // Expense Bar
                        BarMark(
                            x: .value("Date", stat.date, unit: vm.grouping == .monthly ? .month : .day),
                            y: .value("Amount", stat.expense)
                        )
                        .foregroundStyle(Color.red.gradient)
                        .cornerRadius(4)
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartXAxis {
                    AxisMarks(values: .stride(by: vm.grouping == .monthly ? .month : .day, count: vm.grouping == .monthly ? 1 : 5)) { _ in
                        AxisValueLabel(format: vm.grouping == .monthly ? .dateTime.month() : .dateTime.day())
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 220)
                // Dynamic Width Logic
                .frame(width: chartWidth) 
                .padding(.horizontal)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
    
    // Helpers
    var averageExpense: Decimal {
        guard !vm.dailyStats.isEmpty else { return 0 }
        let total = vm.dailyStats.reduce(0) { $0 + $1.expense }
        return total / Decimal(vm.dailyStats.count)
    }
    
    var chartWidth: CGFloat {
        if vm.grouping == .monthly {
             return UIScreen.main.bounds.width - 60 // Fit Screen roughly
        } else {
             // Ensure at least screen width, but expand for scrolling if many days
             return max(UIScreen.main.bounds.width - 60, CGFloat(vm.dailyStats.count * 12)) 
        }
    }
    
    func isSamePeriod(_ date1: Date, as date2: Date) -> Bool {
        return Calendar.current.isDate(date1, equalTo: date2, toGranularity: vm.grouping == .monthly ? .month : .day)
    }
    
    func formatPeriod(_ date: Date) -> String {
        return date.formatted(vm.grouping == .monthly ? .dateTime.month(.wide).year() : .dateTime.day().month(.abbreviated))
    }
    
    func isDateSelected(_ date: Date) -> Bool {
        guard let selected = selectedDate else { return false }
        return isSamePeriod(date, as: selected)
    }
}

struct CategoryBreakdownChart: View {
    @ObservedObject var vm: AnalysisViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Top Spending Categories")
                .font(.headline)
            
            LazyVStack(spacing: 0) {
                ForEach(vm.categoryStats.prefix(5)) { stat in
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: stat.category.icon.isEmpty ? "circle.fill" : stat.category.icon)
                                .font(.title3)
                                .foregroundStyle(Color(hex: stat.colorHex) ?? .blue)
                                .frame(width: 30)
                                
                            VStack(alignment: .leading) {
                                Text(stat.category.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color(.systemGray6))
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
                                    .font(.callout)
                                    .monospacedDigit()
                                
                                let total = vm.categoryStats.reduce(0) { $0 + $1.amount }
                                let percent = total > 0 ? Double(truncating: stat.amount as NSNumber) / Double(truncating: total as NSNumber) : 0
                                Text(percent.formatted(.percent.precision(.fractionLength(0))))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        
                        Divider()
                            .padding(.leading, 40)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
}
