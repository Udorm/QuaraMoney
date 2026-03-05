import SwiftUI
import SwiftData

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel: AddTransactionViewModel
    let isNewTransaction: Bool
    let startWithScanner: Bool
    
    // Query data
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(filter: #Predicate<Wallet> { !$0.isArchived }, sort: \Wallet.name) private var wallets: [Wallet]
    @Query(sort: \SavingsGoal.priority) private var savingsGoals: [SavingsGoal]
    
    // UI State
    @State private var isDateExpanded = false
    @State private var isTimeExpanded = false
    @State private var showAllCategories = false
    @State private var showAllWallets = false
    @State private var showKeyboard = true
    @State private var categorySearchText = ""
    @State private var walletSearchText = ""
    @State private var showScanner = false

    @FocusState private var isNoteFieldFocused: Bool
    
    // Configuration
    private let maxQuickCategories = 3 // Show 3 categories + "More" to keep strictly to one row (4 items)
    private let maxQuickWallets = 4
    
    init(viewModel: AddTransactionViewModel, isNewTransaction: Bool = true, startWithScanner: Bool = false) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.isNewTransaction = isNewTransaction
        self.startWithScanner = startWithScanner
    }
    
    private var filteredCategories: [Category] {
        categories.filter { $0.type == viewModel.type }
    }
    
    /// Get frequently used categories (by transaction count) - limit to maxQuickCategories
    private var frequentCategories: [Category] {
        let sorted = filteredCategories.sorted { cat1, cat2 in
            let count1 = cat1.transactions?.count ?? 0
            let count2 = cat2.transactions?.count ?? 0
            return count1 > count2
        }
        let count = filteredCategories.count
        let limit = count > 4 ? 3 : 4 // If more than 4, show 3 + More. Else show all up to 4.
        
        var items = Array(sorted.prefix(limit))
        
        // If user selected a category that isn't in the top N, replace the last one to show selection
        if let selected = viewModel.selectedCategory, !items.contains(where: { $0.id == selected.id }) {
            if !items.isEmpty {
                items[items.count - 1] = selected
            } else {
                items.append(selected)
            }
        }
        
        return items
    }
    
    /// Get frequently used wallets (by transaction count) - limit to maxQuickWallets
    private var frequentWallets: [Wallet] {
        let sorted = wallets.sorted { w1, w2 in
            let count1 = (w1.outgoingTransactions?.count ?? 0) + (w1.incomingTransactions?.count ?? 0)
            let count2 = (w2.outgoingTransactions?.count ?? 0) + (w2.incomingTransactions?.count ?? 0)
            return count1 > count2
        }
        return Array(sorted.prefix(maxQuickWallets))
    }
    
    /// Get the most used wallet (by transaction count)
    private var mostUsedWallet: Wallet? {
        wallets.max { w1, w2 in
            let count1 = (w1.outgoingTransactions?.count ?? 0) + (w1.incomingTransactions?.count ?? 0)
            let count2 = (w2.outgoingTransactions?.count ?? 0) + (w2.incomingTransactions?.count ?? 0)
            return count1 < count2
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                // Tap to dismiss keyboard
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
                    }
                
                VStack(spacing: 16) {
                    List {
                        

                        // MARK: - Amount & Type (Fluid row)
                        Section {
                            AmountDisplayView(
                                amount: viewModel.evaluatedAmount,
                                currencyCode: $viewModel.selectedCurrencyCode,
                                expression: viewModel.expression,
                                isEditing: showKeyboard,
                                exchangeRateInfo: exchangeRateString,
                                onTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showKeyboard = true
                                        isNoteFieldFocused = false
                                    }
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(
                                Group {
                                    if viewModel.type == .expense {
                                        ThemeManager.shared.expenseColor.opacity(0.15)
                                    } else if viewModel.type == .income {
                                        ThemeManager.shared.incomeColor.opacity(0.15)
                                    } else if viewModel.type == .transfer {
                                        Color.blue.opacity(0.1)
                                    } else {
                                        Color(.secondarySystemGroupedBackground)
                                    }
                                }
                            )
                        }
                        
                        if let exchangeRateStr = exchangeRateString {
                            Section {
                                HStack {
                                    Text(exchangeRateStr)
                                        .font(.app(.subheadline, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        // MARK: - Linked Debt Indicator
                        if let debt = viewModel.debt {
                            Section {
                                HStack {
                                    Image(systemName: debt.type == .owedToMe ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill")
                                        .foregroundStyle(debt.type == .owedToMe ? .red : .green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(debt.type == .owedToMe ? "transaction.linkedToDebt".localized : "transaction.linkedToLoan".localized)
                                            .font(.app(.caption2))
                                            .foregroundStyle(.secondary)
                                        Text(debt.personName)
                                            .font(.app(.subheadline, weight: .semibold))
                                    }
                                    Spacer()
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        // MARK: - Linked Savings Goal Indicator (editing)
                        if viewModel.isEditing, let goal = viewModel.selectedSavingsGoal, viewModel.type == .transfer {
                            Section {
                                HStack {
                                    Image(systemName: goal.iconName)
                                        .foregroundStyle(Color(hex: goal.colorHex) ?? .green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L10n.Savings.selectGoal)
                                            .font(.app(.caption2))
                                            .foregroundStyle(.secondary)
                                        Text(goal.name)
                                            .font(.app(.subheadline, weight: .semibold))
                                    }
                                    Spacer()
                                    Text(goal.progressPercent(converter: CurrencyManager.shared.convert))
                                        .font(.app(.caption))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        // MARK: - Wallet Selector
                        Section("transaction.fromWallet".localized) {
                            walletSelector
                        }
                        
                        // MARK: - Category/Destination Section
                        if viewModel.type == .transfer {
                            Section("transaction.toWallet".localized) {
                                destinationWalletSection
                            }

                            // Savings Goal Picker for transfers
                            Section {
                                savingsGoalPicker
                            }
                            .onChange(of: viewModel.destinationWallet) { _, newDest in
                                guard let dest = newDest else {
                                    viewModel.selectedSavingsGoal = nil
                                    return
                                }
                                // Auto-select if exactly one active goal is linked to this wallet
                                let matchingGoals = savingsGoals.filter { goal in
                                    !goal.isCompleted && goal.linkedWallet?.id == dest.id
                                }
                                if matchingGoals.count == 1 {
                                    viewModel.selectedSavingsGoal = matchingGoals.first
                                }
                            }
                        } else if viewModel.type != .adjustment {
                            Section(L10n.Category.title) {
                                categorySection
                            }
                        }
                        
                        // MARK: - Optional Fields
                        Section {
                            optionalFieldsSection
                        }

                        reportingSection
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .safeAreaInset(edge: .bottom) {
                // MARK: - Calculator Keyboard (Dismissible)
                if showKeyboard && !isNoteFieldFocused {
                    CalculatorKeyboardView(
                        expression: $viewModel.expression,
                        evaluatedAmount: $viewModel.evaluatedAmount,
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showKeyboard = false
                            }
                        }
                    )
                    .transition(.move(edge: .bottom))
                    .background(Color(.systemGroupedBackground))
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    transactionTypeSelector
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        viewModel.saveTransaction()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.isValid)
                }
                
                // Moved scan button to FAB
            }
            .sheet(isPresented: $showScanner) {
                ScannerView(isPresented: $showScanner) { result in
                    switch result {
                    case .success(let images):
                        if let firstImage = images.first {
                            Task {
                                await viewModel.scanReceipt(image: firstImage, availableWallets: wallets)
                            }
                        }
                    case .failure(let error):
                        print("Scanner failed: \(error)")
                    }
                }
            }
            .onAppear {
                // Preselect the most used wallet (by transaction count)
                if viewModel.selectedWallet == nil, let wallet = mostUsedWallet ?? wallets.first {
                    viewModel.selectedWallet = wallet
                    viewModel.syncCurrencyToWallet()
                }
                // Only show keyboard for new transactions
                showKeyboard = isNewTransaction && !startWithScanner
                
                if startWithScanner {
                    showScanner = true
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }
    
    private func dismissKeyboard() {
        withAnimation(.easeInOut(duration: 0.2)) {
            // Finalize calculation before dismissing
            if let result = ExpressionEvaluator.evaluate(viewModel.expression), result > 0 {
                viewModel.evaluatedAmount = result
                let doubleValue = NSDecimalNumber(decimal: result).doubleValue
                if doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
                    viewModel.expression = String(format: "%.0f", doubleValue)
                } else {
                    viewModel.expression = String(format: "%.2f", doubleValue)
                }
            }
            showKeyboard = false
            isNoteFieldFocused = false
        }
    }
    
    // MARK: - Transaction Type Selector
    private var transactionTypeSelector: some View {
        Group {
            if viewModel.type == .adjustment {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.orange)
                    Text("transaction.type.adjustment".localized)
                        .font(.app(.headline))
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(10)
            } else {
                Picker("transaction.type".localized, selection: $viewModel.type) {
                    Text(L10n.Transaction.TransactionType.expense).tag(TransactionType.expense)
                    Text(L10n.Transaction.TransactionType.income).tag(TransactionType.income)
                    Text(L10n.Transaction.TransactionType.transfer).tag(TransactionType.transfer)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                .onChange(of: viewModel.type) { _, newType in
                    if newType != .transfer {
                        viewModel.selectedCategory = nil
                        viewModel.selectedSavingsGoal = nil
                    }
                }
            }
        }
    }
    
    private var exchangeRateString: String? {
        guard let wallet = viewModel.selectedWallet,
              viewModel.selectedCurrencyCode != wallet.currencyCode else { return nil }
        
        let rate = viewModel.exchangeRate
        let rateString = rate.formatted(.number.precision(.significantDigits(2...6)))
        return "1 \(viewModel.selectedCurrencyCode) ≈ \(rateString) \(wallet.currencyCode)"
    }
    
    // MARK: - Wallet Selector
    private var walletSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(frequentWallets) { wallet in
                        WalletChip(
                            wallet: wallet,
                            isSelected: viewModel.selectedWallet?.id == wallet.id
                        ) {
                            viewModel.selectedWallet = wallet
                            viewModel.syncCurrencyToWallet()
                            viewModel.updateExchangeRate()
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            
            if wallets.count > maxQuickWallets {
                Button {
                    showAllWallets = true
                } label: {
                    HStack {
                        Image(systemName: "checklist")
                        Text(L10n.Common.seeAll)
                    }
                    .font(.app(.subheadline))
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .overlay(
            Group {
                if viewModel.type == .adjustment {
                    Color(.secondarySystemFill)
                        .allowsHitTesting(true)
                }
            }
        )
        .sheet(isPresented: $showAllWallets) {
            walletPickerSheet
        }
    }
    
    // MARK: - Wallet Picker Sheet
    private var walletPickerSheet: some View {
        let displayWallets = walletSearchText.isEmpty ? wallets : wallets.filter { $0.name.localizedCaseInsensitiveContains(walletSearchText) || $0.currencyCode.localizedCaseInsensitiveContains(walletSearchText) }
        
        return NavigationStack {
            List {
                ForEach(displayWallets) { wallet in
                    Button {
                        viewModel.selectedWallet = wallet
                        viewModel.syncCurrencyToWallet()
                        viewModel.updateExchangeRate()
                        showAllWallets = false
                    } label: {
                        HStack {
                            Image(systemName: wallet.icon)
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(wallet.name)
                                Text(wallet.currencyCode)
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.selectedWallet?.id == wallet.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle(L10n.Wallet.selectWallet)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $walletSearchText, prompt: Text("transaction.searchWallets".localized))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { showAllWallets = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Destination Wallet Section (for Transfers)
    @ViewBuilder
    private var destinationWalletSection: some View {
        let availableWallets = wallets.filter { $0.id != viewModel.selectedWallet?.id }
        
        VStack(alignment: .leading, spacing: 12) {
            if availableWallets.isEmpty {
                Text("transaction.noOtherWallets".localized)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableWallets) { wallet in
                            WalletChip(
                                wallet: wallet,
                                isSelected: viewModel.destinationWallet?.id == wallet.id
                            ) {
                                viewModel.destinationWallet = wallet
                                viewModel.updateExchangeRate()
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Exchange rate if different currencies
            if let source = viewModel.selectedWallet,
               let dest = viewModel.destinationWallet,
               source.currencyCode != dest.currencyCode {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("1 \(source.currencyCode) =")
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                        TextField(L10n.Transaction.rate, value: $viewModel.exchangeRate, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text(dest.currencyCode)
                            .font(.app(.subheadline, weight: .semibold))
                    }
                    
                    let convertedAmount = viewModel.evaluatedAmount * Decimal(viewModel.exchangeRate)
                    Text("≈ \(convertedAmount.formattedAmount(for: dest.currencyCode))")
                        .font(.app(.caption))
                        .foregroundStyle(.blue)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Category Section (Smart Selection)
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if filteredCategories.isEmpty {
                Text("transaction.noCategoriesForType".localized(with: viewModel.type.title))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                // Show frequent categories in grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(frequentCategories) { category in
                        CategoryGridItem(
                            category: category,
                            isSelected: viewModel.selectedCategory?.id == category.id
                        ) {
                            viewModel.selectedCategory = category
                        }
                    }
                    
                    // Always show a "More" option if there are more than 4 categories
                    if filteredCategories.count > 4 {
                        Button {
                            showAllCategories = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "ellipsis.circle.fill")
                                    .font(.app(.title3))
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, height: 40)
                                    .background(Color(.tertiarySystemGroupedBackground))
                                    .clipShape(Circle())
                                
                                Text("common.more".localized)
                                    .font(.app(.caption2))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $showAllCategories) {
            categoryPickerSheet
        }
    }
    
    // MARK: - Category Picker Sheet
    private var categoryPickerSheet: some View {
        let displayCategories = categorySearchText.isEmpty ? filteredCategories : filteredCategories.filter { $0.name.localizedCaseInsensitiveContains(categorySearchText) }
        
        return NavigationStack {
            List {
                ForEach(displayCategories) { category in
                    Button {
                        viewModel.selectedCategory = category
                        showAllCategories = false
                    } label: {
                        HStack {
                            Image(systemName: category.icon)
                                .foregroundColor(Color(hex: category.colorHex) ?? .gray)
                                .frame(width: 24)
                            Text(category.name)
                            Spacer()
                            if viewModel.selectedCategory?.id == category.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle(L10n.TransactionAdditional.selectCategory)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $categorySearchText, prompt: L10n.TransactionAdditional.searchCategories)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { showAllCategories = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Optional Fields Section
    private var optionalFieldsSection: some View {
        Group {
            // Date Selection Row
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isDateExpanded.toggle()
                    if isDateExpanded {
                        isTimeExpanded = false
                        showKeyboard = false
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    Text("transaction.date".localized)
                    Spacer()
                    Text(viewModel.date.formatted(date: .long, time: .omitted))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isDateExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            
            if isDateExpanded {
                DatePicker(
                    "",
                    selection: $viewModel.date,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Time Selection Row
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isTimeExpanded.toggle()
                    if isTimeExpanded {
                        isDateExpanded = false
                        showKeyboard = false
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    Text(L10n.TransactionAdditional.time)
                    Spacer()
                    Text(viewModel.date.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isTimeExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isTimeExpanded {
                DatePicker(
                    "",
                    selection: $viewModel.date,
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Note Field
            HStack {
                Image(systemName: "note.text")
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                TextField(L10n.Transaction.note, text: $viewModel.note)
                    .focused($isNoteFieldFocused)
            }
        }
    }
    
    // MARK: - Savings Goal Picker (for Transfers)
    private var savingsGoalPicker: some View {
        let eligibleGoals = savingsGoals.filter { goal in
            !goal.isCompleted && (goal.linkedWallet == nil || goal.linkedWallet?.id == viewModel.destinationWallet?.id)
        }
        // Sort: goals whose linkedWallet matches the destination wallet come first
        let sortedGoals = eligibleGoals.sorted { g1, g2 in
            let g1Matches = g1.linkedWallet?.id == viewModel.destinationWallet?.id && g1.linkedWallet != nil
            let g2Matches = g2.linkedWallet?.id == viewModel.destinationWallet?.id && g2.linkedWallet != nil
            if g1Matches != g2Matches { return g1Matches }
            return g1.priority < g2.priority
        }

        return Picker(L10n.Savings.selectGoal, selection: $viewModel.selectedSavingsGoal) {
            Text("budget.threshold.none".localized).tag(nil as SavingsGoal?)
            ForEach(sortedGoals) { goal in
                HStack {
                    Image(systemName: goal.iconName)
                    Text(goal.name)
                }
                .tag(goal as SavingsGoal?)
            }
        }
    }

    private var reportingSection: some View {
        Section {
            // Exclude Toggle
            Toggle("Exclude from Reports", isOn: $viewModel.excludeFromReports)
        }
    }
}

// MARK: - Wallet Chip Component
struct WalletChip: View {
    let wallet: Wallet
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: wallet.icon)
                    .font(.app(.caption2))
                Text(wallet.name)
                    .font(.app(.subheadline, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(.tertiarySystemGroupedBackground))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
