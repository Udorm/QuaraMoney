import SwiftUI
import SwiftData

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel: AddTransactionViewModel
    let isNewTransaction: Bool
    
    // Query data
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(filter: #Predicate<Wallet> { !$0.isArchived }, sort: \Wallet.name) private var wallets: [Wallet]
    
    // UI State
    @State private var showDatePicker = false
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
    
    init(viewModel: AddTransactionViewModel, isNewTransaction: Bool = true, initialShowScanner: Bool = false) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.isNewTransaction = isNewTransaction
        self._showScanner = State(initialValue: initialShowScanner)
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
            ZStack {
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
                            VStack(spacing: 0) {
                                transactionTypeSelector
                                
                                AmountDisplayView(
                                    amount: viewModel.evaluatedAmount,
                                    currencyCode: $viewModel.selectedCurrencyCode,
                                    expression: viewModel.expression,
                                    isEditing: showKeyboard,
                                    exchangeRateInfo: exchangeRateString
                                )
                                .onTapGesture {
                                    if viewModel.type != .adjustment {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showKeyboard = true
                                            isNoteFieldFocused = false
                                        }
                                    }
                                }
 
                            }
                        }
                        // .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                        .listRowBackground(Color.clear)                        
                        .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0))
                        

                        // MARK: - Linked Debt Indicator
                        if let debt = viewModel.debt {
                            Section {
                                HStack {
                                    Image(systemName: debt.type == .owedToMe ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill")
                                        .foregroundStyle(debt.type == .owedToMe ? .red : .green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(debt.type == .owedToMe ? "Linked to Debt" : "Linked to Loan")
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
                        
                        // MARK: - Wallet Selector
                        Section("transaction.fromWallet".localized) {
                            walletSelector
                        }
                        
                        // MARK: - Category/Destination Section
                        if viewModel.type == .transfer {
                            Section("transaction.toWallet".localized) {
                                destinationWalletSection
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
                    .listStyle(.insetGrouped)
                }
            } // Close ZStack
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
            .navigationTitle(viewModel.isEditing ? L10n.Common.edit : L10n.Transaction.add)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "doc.text.viewfinder")
                    }
                }
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
            }
            .onAppear {
                // Preselect the most used wallet (by transaction count)
                if viewModel.selectedWallet == nil, let wallet = mostUsedWallet ?? wallets.first {
                    viewModel.selectedWallet = wallet
                    viewModel.syncCurrencyToWallet()
                }
                // Only show keyboard for new transactions
                showKeyboard = isNewTransaction
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
                    Text("Balance Adjustment")
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
                .onChange(of: viewModel.type) { _, newType in
                    if newType != .transfer {
                        viewModel.selectedCategory = nil
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
                    Text("≈ \(convertedAmount.formatted(.currency(code: dest.currencyCode)))")
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
            .navigationTitle("Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $categorySearchText, prompt: "Search categories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAllCategories = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Optional Fields Section
    private var optionalFieldsSection: some View {
        Group {
            // Date Row - using native DatePicker inline
            DatePicker(
                selection: $viewModel.date,
                displayedComponents: [.date, .hourAndMinute]
            ) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    Text("transaction.date".localized)
                }
            }
            .disabled(viewModel.type == .adjustment)
            .opacity(viewModel.type == .adjustment ? 0.6 : 1.0)
            
            // Note Field
            HStack {
                Image(systemName: "note.text")
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                TextField(L10n.Transaction.note, text: $viewModel.note)
                    .focused($isNoteFieldFocused)
            }
            
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
            .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}
