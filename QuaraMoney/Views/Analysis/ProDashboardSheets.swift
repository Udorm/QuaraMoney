import SwiftUI
import SwiftData

// MARK: - Filter Sheet

/// The full filter configurator for the Pro dashboard. Uses deferred apply: nothing changes
/// until the user taps the confirm button, so they can stage a whole multi-dimensional query.
struct ProDashboardFilterSheet: View {
    @Bindable var vm: ProAnalyticsViewModel
    var wallets: [Wallet]
    var categories: [Category]

    @Environment(\.dismiss) private var dismiss

    // Staged (pending) state
    @State private var pendingFilter: DashboardFilter
    @State private var pendingPeriod: AnalysisPeriod
    @State private var pendingStart: Date
    @State private var pendingEnd: Date
    @State private var minAmountText: String
    @State private var maxAmountText: String

    init(vm: ProAnalyticsViewModel, wallets: [Wallet], categories: [Category]) {
        self.vm = vm
        self.wallets = wallets
        self.categories = categories
        _pendingFilter = State(initialValue: vm.filter)
        _pendingPeriod = State(initialValue: vm.selectedPeriod)
        _pendingStart = State(initialValue: vm.customStartDate)
        _pendingEnd = State(initialValue: vm.customEndDate)
        _minAmountText = State(initialValue: vm.filter.minAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        _maxAmountText = State(initialValue: vm.filter.maxAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
    }

    /// Categories matching the staged transaction type (categories are type-specific).
    private var typedCategories: [Category] {
        let type: TransactionType = pendingFilter.transactionType == .income ? .income : .expense
        return categories.filter { $0.type == type }
    }

    var body: some View {
        NavigationStack {
            Form {
                typeSection
                periodSection
                walletSection
                categorySection
                amountSection
                optionsSection
            }
            .navigationTitle("analysis.pro.filter.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("analysis.pro.filter.reset".localized) { resetStaged() }
                        .disabled(!pendingFilter.hasActiveConstraints)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { apply() } label: {
                        Image(systemName: "checkmark").fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Sections

    private var typeSection: some View {
        Section {
            Picker("analysis.transactionType".localized, selection: $pendingFilter.transactionType) {
                Text(L10n.Transaction.TransactionType.expense).tag(TransactionTypeFilter.expense)
                Text(L10n.Transaction.TransactionType.income).tag(TransactionTypeFilter.income)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("analysis.transactionType".localized).font(.app(.caption))
        }
        .onChange(of: pendingFilter.transactionType) { _, _ in
            // Drop category selections that no longer match the chosen type.
            let valid = Set(typedCategories.map(\.id))
            pendingFilter.categoryIds = pendingFilter.categoryIds.intersection(valid)
        }
    }

    private var periodSection: some View {
        Section {
            Picker("filter.period".localized, selection: $pendingPeriod) {
                Text("analysis.period.w".localized).tag(AnalysisPeriod.week)
                Text("analysis.period.m".localized).tag(AnalysisPeriod.month)
                Text("analysis.period.6m".localized).tag(AnalysisPeriod.sixMonths)
                Text("analysis.period.y".localized).tag(AnalysisPeriod.year)
                Text(L10n.Period.custom).tag(AnalysisPeriod.custom)
            }
            .pickerStyle(.menu)
            .font(.app(.body))

            if pendingPeriod == .custom {
                DatePicker("filter.startDate".localized, selection: $pendingStart, displayedComponents: .date)
                    .font(.app(.body))
                DatePicker("filter.endDate".localized, selection: $pendingEnd, in: pendingStart..., displayedComponents: .date)
                    .font(.app(.body))
            }
        } header: {
            Text("filter.period".localized).font(.app(.caption))
        }
    }

    private var walletSection: some View {
        Section {
            MultiSelectRow(
                title: "filter.allWallets".localized,
                icon: "square.stack.3d.up",
                iconColor: .secondary,
                isSelected: pendingFilter.walletIds.isEmpty
            ) {
                pendingFilter.walletIds = []
            }
            ForEach(wallets) { wallet in
                MultiSelectRow(
                    title: wallet.name,
                    icon: wallet.icon.isEmpty ? "creditcard" : wallet.icon,
                    iconColor: Color(hex: wallet.colorHex) ?? .blue,
                    isSelected: pendingFilter.walletIds.contains(wallet.id)
                ) {
                    toggle(&pendingFilter.walletIds, wallet.id)
                }
            }
        } header: {
            HStack {
                Text("filter.wallet".localized).font(.app(.caption))
                Spacer()
                if !pendingFilter.walletIds.isEmpty {
                    Text("analysis.pro.filter.nSelected".localized(with: pendingFilter.walletIds.count))
                        .font(.app(.caption2))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var categorySection: some View {
        Section {
            if typedCategories.isEmpty {
                Text("analysis.pro.filter.noCategories".localized)
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                MultiSelectRow(
                    title: "analysis.pro.filter.allCategories".localized,
                    icon: "square.grid.2x2",
                    iconColor: .secondary,
                    isSelected: pendingFilter.categoryIds.isEmpty
                ) {
                    pendingFilter.categoryIds = []
                }
                ForEach(typedCategories) { category in
                    MultiSelectRow(
                        title: category.name,
                        icon: category.icon.isEmpty ? "tag" : category.icon,
                        iconColor: Color(hex: category.colorHex) ?? .blue,
                        isSelected: pendingFilter.categoryIds.contains(category.id)
                    ) {
                        toggle(&pendingFilter.categoryIds, category.id)
                    }
                }
            }
        } header: {
            HStack {
                Text("filter.category".localized).font(.app(.caption))
                Spacer()
                if !pendingFilter.categoryIds.isEmpty {
                    Text("analysis.pro.filter.nSelected".localized(with: pendingFilter.categoryIds.count))
                        .font(.app(.caption2))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var amountSection: some View {
        Section {
            HStack {
                Text("analysis.pro.filter.min".localized)
                    .appFont(.body)
                Spacer()
                TextField("0", text: $minAmountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.app(.body))
                    .frame(maxWidth: 140)
            }
            HStack {
                Text("analysis.pro.filter.max".localized)
                    .appFont(.body)
                Spacer()
                TextField("∞", text: $maxAmountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.app(.body))
                    .frame(maxWidth: 140)
            }
        } header: {
            Text("analysis.pro.filter.amountRange".localized(with: vm.preferredCurrency)).font(.app(.caption))
        }
    }

    private var optionsSection: some View {
        Section {
            Toggle(isOn: $pendingFilter.includeExcluded) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("analysis.pro.filter.includeExcluded".localized)
                        .appFont(.body)
                    Text("analysis.pro.filter.includeExcluded.subtitle".localized)
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.app(.body))
        }
    }

    // MARK: Helpers

    private func toggle(_ set: inout Set<UUID>, _ id: UUID) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func resetStaged() {
        pendingFilter.clearConstraints()
        minAmountText = ""
        maxAmountText = ""
    }

    private func parseDecimal(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized)
    }

    private func apply() {
        var newFilter = pendingFilter
        let parsedMin = parseDecimal(minAmountText)
        let parsedMax = parseDecimal(maxAmountText)
        // Guard against an inverted range by swapping if needed.
        if let lo = parsedMin, let hi = parsedMax, lo > hi {
            newFilter.minAmount = hi
            newFilter.maxAmount = lo
        } else {
            newFilter.minAmount = parsedMin
            newFilter.maxAmount = parsedMax
        }

        // Apply period first (its setter resets the reference date), then the filter.
        if vm.selectedPeriod != pendingPeriod { vm.selectedPeriod = pendingPeriod }
        if vm.customStartDate != pendingStart { vm.customStartDate = pendingStart }
        if vm.customEndDate != pendingEnd { vm.customEndDate = pendingEnd }
        vm.filter = newFilter

        dismiss()
    }
}

// MARK: - Multi-Select Row

/// A tappable full-width row with a leading icon and a trailing checkmark for multi-select lists.
private struct MultiSelectRow: View {
    let title: String
    let icon: String
    var iconColor: Color = .blue
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .appFont(.body)
                    .foregroundStyle(iconColor)
                    .frame(width: 26)
                Text(title)
                    .appFont(.body)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .appFont(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabel))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Customize Sheet

/// Lets the user show/hide and reorder dashboard sections. Changes persist immediately.
struct ProCustomizeSheet: View {
    @Bindable var vm: ProAnalyticsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .active

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(vm.layout.order) { section in
                        let isVisible = !vm.layout.hidden.contains(section)
                        Toggle(isOn: visibilityBinding(section)) {
                            HStack(spacing: 12) {
                                Image(systemName: section.systemImage)
                                    .appFont(.body)
                                    .foregroundStyle(isVisible ? Color.accentColor : .secondary)
                                    .frame(width: 26)
                                Text(section.title)
                                    .appFont(.body)
                                    .foregroundStyle(isVisible ? .primary : .secondary)
                            }
                        }
                        .font(.app(.body))
                    }
                    .onMove { from, to in
                        vm.layout.order.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("analysis.pro.customize.subtitle".localized).font(.app(.caption))
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("analysis.pro.customize".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("analysis.pro.filter.reset".localized) {
                        vm.resetLayout()
                    }
                    .disabled(vm.layout.isDefault)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "checkmark").fontWeight(.semibold)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// Binding that maps a section's visibility to the layout's `hidden` set.
    private func visibilityBinding(_ section: DashboardSection) -> Binding<Bool> {
        Binding(
            get: { !vm.layout.hidden.contains(section) },
            set: { visible in
                if visible { vm.layout.hidden.remove(section) }
                else { vm.layout.hidden.insert(section) }
            }
        )
    }
}
