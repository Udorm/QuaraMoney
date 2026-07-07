import SwiftUI
import SwiftData
import CoreLocation

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: AddTransactionViewModel
    let isNewTransaction: Bool

    // Query data
    @Query(filter: #Predicate<Category> { $0.deletedAt == nil }, sort: \Category.name) private var categories: [Category]
    @Query(filter: #Predicate<Wallet> { !$0.isArchived && $0.deletedAt == nil }, sort: \Wallet.name) private var wallets: [Wallet]
    @Query(filter: #Predicate<SavingsGoal> { $0.deletedAt == nil }, sort: \SavingsGoal.priority) private var savingsGoals: [SavingsGoal]
    
    // UI State
    @State private var showAllCategories = false
    @State private var showAllWallets = false
    @State private var showKeyboard = true
    @State private var showScanner = false
    @State private var showLocationPicker = false
    @State private var isFetchingCurrentLocation = false
    @State private var showDebtSheet = false
    // Inline creation of a first wallet/category when the user has none.
    @State private var showAddWallet = false
    @State private var showAddCategory = false

    @Environment(\.modelContext) private var modelContext

    // Suggestion engine: cached, contextual rankings (recomputed on context changes, not every body pass)
    @State private var scoredWallets: [ScoredWallet] = []
    @State private var scoredCategories: [ScoredCategory] = []
    @State private var scoredTags: [ScoredTag] = []
    /// Recent transactions used as the tag-candidate pool. Fetched once on
    /// appear (tags aren't queryable via #Predicate — they're a Codable array).
    @State private var tagSourceTransactions: [Transaction] = []
    /// Device current-location spatial key, fetched in the background for ranking ONLY.
    /// Never written to the transaction's location field.
    @State private var backgroundLocationKey: String?
    @State private var locationService = CurrentLocationService()

    @FocusState private var isNoteFieldFocused: Bool
    
    // Configuration
    private let maxQuickCategories = 3 // Show 3 categories + "More" to keep strictly to one row (4 items)
    private let maxQuickWallets = 4
    
    init(viewModel: AddTransactionViewModel, isNewTransaction: Bool = true) {
        self._viewModel = State(wrappedValue: viewModel)
        self.isNewTransaction = isNewTransaction
    }
    
    /// True when editing a transaction that belongs to a debt/loan. Such entries
    /// are read-only here — the user manages them from the Debts & Loans screen
    /// so the debt's derived ledger (totals, repayments) can't be silently
    /// corrupted by changing the amount, type, or currency.
    private var isDebtLinked: Bool { viewModel.debt != nil }

    private var filteredCategories: [Category] {
        categories.filter { $0.type == viewModel.type }
    }
    
    /// Contextually-ranked categories for the current type (falls back to name order until first compute).
    private var orderedCategories: [ScoredCategory] {
        let typeMatched = scoredCategories.filter { $0.category.type == viewModel.type }
        if typeMatched.isEmpty {
            // Cold start or pre-compute: name-ordered (filteredCategories already sorted), no highlight.
            return filteredCategories.map {
                ScoredCategory(category: $0, score: 0, lastUsed: nil, isHighlighted: false)
            }
        }
        return typeMatched
    }

    /// Top contextual categories for the quick grid — keeps the 3+More cap and the
    /// "inject the current selection so it stays visible" behavior.
    private var frequentCategories: [ScoredCategory] {
        let sorted = orderedCategories
        let count = filteredCategories.count
        let limit = count > 4 ? 3 : 4 // If more than 4, show 3 + More. Else show all up to 4.

        var items = Array(sorted.prefix(limit))

        // If user selected a category that isn't in the top N, replace the last one to show selection
        if let selected = viewModel.selectedCategory, !items.contains(where: { $0.category.id == selected.id }) {
            let selectedScored = sorted.first(where: { $0.category.id == selected.id })
                ?? ScoredCategory(category: selected, score: 0, lastUsed: nil, isHighlighted: false)
            if !items.isEmpty {
                items[items.count - 1] = selectedScored
            } else {
                items.append(selectedScored)
            }
        }

        return items
    }

    /// Contextually-ranked wallets for the quick chips (falls back to name order until first compute).
    private var frequentWallets: [Wallet] {
        let ordered = scoredWallets.isEmpty ? wallets : scoredWallets.map(\.wallet)
        return Array(ordered.prefix(maxQuickWallets))
    }

    // MARK: - Suggestion recompute

    /// Resolves the scoring location: manual selection first, else the background current location.
    /// Used for ranking only — never persisted to the transaction.
    private func scoringLocation() -> SuggestionLocationContext? {
        if let selection = viewModel.selectedLocation {
            return SuggestionLocationContext(
                applePlaceID: selection.applePlaceID,
                spatialKey: TransactionLocation.spatialKey(
                    latitude: selection.latitude,
                    longitude: selection.longitude
                )
            )
        }
        if let key = backgroundLocationKey {
            return SuggestionLocationContext(applePlaceID: nil, spatialKey: key)
        }
        return nil
    }

    private func recomputeSuggestions() {
        let location = scoringLocation()
        scoredWallets = TransactionSuggestionEngine.rankWallets(
            wallets,
            type: viewModel.type,
            selectedCategory: viewModel.selectedCategory,
            location: location
        )
        scoredCategories = TransactionSuggestionEngine.rankCategories(
            categories,
            type: viewModel.type,
            selectedWallet: viewModel.selectedWallet,
            location: location
        )
        scoredTags = TransactionSuggestionEngine.rankTags(
            in: tagSourceTransactions,
            type: viewModel.type,
            selectedWallet: viewModel.selectedWallet,
            selectedCategory: viewModel.selectedCategory,
            location: location
        )
    }

    // MARK: - Tag suggestions

    /// Chips to show under the note field. While the user is typing a `#token`
    /// at the end of the note, suggestions narrow to prefix matches; otherwise
    /// the contextual top tags show. Tags already present in the note are
    /// excluded so chips always represent something new to insert.
    private var suggestedTagChips: [ScoredTag] {
        guard !scoredTags.isEmpty else { return [] }

        let activeToken = isNoteFieldFocused
            ? TransactionTagParser.activeTagToken(in: viewModel.note)
            : nil
        var existing = Set(TransactionTagParser.tags(in: viewModel.note).map { $0.lowercased() })
        if let activeToken, !activeToken.isEmpty {
            // The token being typed parses as a "complete" tag — don't let it
            // suppress its own completions.
            existing.remove(activeToken.lowercased())
        }

        let candidates = scoredTags.filter { scored in
            let key = scored.tag.lowercased()
            guard !existing.contains(key) else { return false }
            if let activeToken, !activeToken.isEmpty {
                return key.hasPrefix(activeToken.lowercased())
            }
            return true
        }
        return Array(candidates.prefix(8))
    }

    /// Inserts a suggested tag into the note: completes the `#token` being
    /// typed when there is one, otherwise appends `#tag` to the end.
    private func insertTag(_ tag: String) {
        var note = viewModel.note
        if isNoteFieldFocused, let token = TransactionTagParser.activeTagToken(in: note) {
            note.removeLast(token.count + 1) // the partial token and its "#"
        } else if !note.isEmpty, note.last?.isWhitespace != true {
            note += " "
        }
        note += "#\(tag) "
        viewModel.note = note
        HapticManager.shared.selection()
    }

    /// Fetches the recent noted transactions the tag ranker mines for candidates.
    /// Date-range only (indexed); tag extraction happens in the engine.
    private func loadTagSourceTransactions() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? .distantPast
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= cutoff && $0.note != nil && $0.deletedAt == nil }
        )
        tagSourceTransactions = (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Fetches the device's current location in the background to bias suggestions.
    /// Scoring signal only — silently ignores denial/failure and never sets a transaction location.
    private func startBackgroundLocationFetch() {
        Task {
            do {
                let location = try await locationService.requestCurrentLocation()
                backgroundLocationKey = TransactionLocation.spatialKey(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                recomputeSuggestions()
            } catch {
                // Location is an optional ranking signal; ignore unavailable/denied/no-fix.
            }
        }
    }

    /// One-tap action from the location row: resolves the device's current location and writes it
    /// straight into the transaction, without opening the full picker.
    private func useCurrentLocationDirectly() {
        guard !isFetchingCurrentLocation else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            showKeyboard = false
            isNoteFieldFocused = false
        }
        isFetchingCurrentLocation = true
        Task {
            defer { isFetchingCurrentLocation = false }
            do {
                let location = try await locationService.requestCurrentLocation()
                let selection = try await TransactionPlaceLookup.reverseGeocode(
                    location: location,
                    source: .currentLocation
                )
                viewModel.selectedLocation = selection
                HapticManager.shared.notification(type: .success)
            } catch {
                HapticManager.shared.notification(type: .error)
            }
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
                        Section(footer:
                            Group {
                                if let exchangeRateStr = exchangeRateString {
                                    Label(exchangeRateStr, systemImage: "lock.fill")
                                        .font(.app(.footnote))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        ) {
                            AmountDisplayView(
                                amount: viewModel.evaluatedAmount,
                                currencyCode: $viewModel.selectedCurrencyCode,
                                expression: viewModel.expression,
                                isEditing: showKeyboard,
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

                        // MARK: - Linked Debt (single combined indicator + open button)
                        if let debt = viewModel.debt {
                            Section {
                                Button {
                                    showDebtSheet = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: debt.type == .owedToMe ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                                            .font(.app(.title3))
                                            .foregroundStyle(debt.type.accentColor)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(debt.type == .owedToMe ? "transaction.linkedToDebt".localized : "transaction.linkedToLoan".localized)
                                                .font(.app(.caption2))
                                                .foregroundStyle(.secondary)
                                            Text(debt.personName)
                                                .font(.app(.subheadline, weight: .semibold))
                                                .foregroundStyle(.primary)
                                        }
                                        Spacer()
                                        Text("debt.viewDebt".localized)
                                            .font(.app(.caption, weight: .medium))
                                            .foregroundStyle(.tint)
                                        Image(systemName: "chevron.right")
                                            .font(.app(.caption2, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            } footer: {
                                Text("transaction.debtLocked.message".localized(with: debt.personName))
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
                        } else if viewModel.type != .adjustment && !isDebtLinked {
                            // Category is hidden for debt-linked transactions —
                            // it's a managed system category and not editable.
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
                    .listSectionSpacing(.compact)
                    .contentMargins(.top, 16, for: .scrollContent)
                }
            }
            .safeAreaInset(edge: .bottom, alignment: .trailing) {
                // Scanning overwrites the form from a receipt, so it's only offered
                // for a fresh, non-debt-linked entry, and tucked away while the
                // calculator keyboard is occupying the same corner of the screen.
                // A safe-area inset (not a ZStack overlay) so the list reserves
                // space for it instead of scrolling content underneath.
                if isNewTransaction && !isDebtLinked && !showKeyboard {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "doc.text.viewfinder")
                    }
                    .modifier(CircularFABStyle())
                    .controlSize(.large)
                    .padding(.trailing)
                    .padding(.bottom, 8)
                    .accessibilityLabel("Scan receipt")
                    .transition(.scale.combined(with: .opacity))
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
            .navigationTitle(isDebtLinked ? (viewModel.debt?.personName ?? "") : "")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                // Type isn't relevant/editable for a debt-linked transaction — hide it.
                if !isDebtLinked {
                    ToolbarItem(placement: .principal) {
                        transactionTypeSelector
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if viewModel.saveTransaction() {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.isValid)
                    .accessibilityLabel("Save transaction")
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
                        #if DEBUG
                        print("Scanner failed: \(error)")
                        #endif
                    }
                }
            }
            .sheet(isPresented: $showLocationPicker) {
                TransactionLocationPickerView(selection: $viewModel.selectedLocation)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showDebtSheet) {
                if let debt = viewModel.debt {
                    NavigationStack {
                        DebtDetailView(debt: debt)
                    }
                }
            }
            .onAppear {
                loadTagSourceTransactions()
                recomputeSuggestions()
                // Preselect the top contextually-ranked wallet
                if viewModel.selectedWallet == nil, let wallet = scoredWallets.first?.wallet ?? wallets.first {
                    viewModel.selectedWallet = wallet
                    viewModel.syncCurrencyToWallet()
                    // Selected wallet now informs category co-occurrence ranking
                    recomputeSuggestions()
                }
                // Only show keyboard for new transactions
                showKeyboard = isNewTransaction

                // Fetch current location in the background to refine suggestions (new entries only)
                if isNewTransaction {
                    startBackgroundLocationFetch()
                }
            }
            .onChange(of: viewModel.type) { _, _ in recomputeSuggestions() }
            .onChange(of: viewModel.selectedWallet) { _, _ in recomputeSuggestions() }
            .onChange(of: viewModel.selectedCategory) { _, _ in recomputeSuggestions() }
            .onChange(of: viewModel.selectedLocation) { _, _ in recomputeSuggestions() }
            .onChange(of: viewModel.selectedCurrencyCode) { _, _ in
                // Re-value the transaction against its wallet when the currency
                // changes (e.g. editing a debt transaction's currency).
                if viewModel.type != .transfer {
                    viewModel.updateTransactionCurrencyExchangeRate()
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
    
    /// Selects a source wallet and refreshes the appropriate exchange rate:
    /// transfers use the source→destination rate, while income/expense use the
    /// transaction-currency→wallet-currency rate so a wallet in a different
    /// currency (e.g. a debt in USD paid from a KHR wallet) is valued correctly.
    private func selectWallet(_ wallet: Wallet) {
        viewModel.selectedWallet = wallet
        viewModel.syncCurrencyToWallet()
        if viewModel.type == .transfer {
            viewModel.updateExchangeRate()
        } else {
            viewModel.updateTransactionCurrencyExchangeRate()
        }
    }

    // MARK: - Wallet Selector
    @ViewBuilder
    private var walletSelector: some View {
        if wallets.isEmpty {
            TransactionSetupPrompt(
                icon: "wallet.pass",
                tint: .accentColor,
                title: "transaction.setup.wallet.title".localized,
                message: "transaction.setup.wallet.message".localized,
                actionTitle: "wallet.add".localized
            ) {
                showAddWallet = true
            }
            .padding(.vertical, 4)
            .sheet(isPresented: $showAddWallet, onDismiss: autoSelectNewWalletIfNeeded) {
                AddWalletView(viewModel: AddWalletViewModel(dataService: SwiftDataService(modelContext: modelContext)))
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(frequentWallets) { wallet in
                            WalletChip(
                                wallet: wallet,
                                isSelected: viewModel.selectedWallet?.id == wallet.id
                            ) {
                                selectWallet(wallet)
                            }
                        }

                        if wallets.count > maxQuickWallets {
                            Button {
                                showAllWallets = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "ellipsis")
                                        .font(.app(.caption2))
                                    Text("common.more".localized)
                                        .font(.app(.subheadline, weight: .medium))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.tertiarySystemGroupedBackground))
                                .foregroundColor(.secondary)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
    }

    /// Auto-selects the wallet the user just created so a first-time entry can be
    /// saved immediately. Only acts when nothing is selected yet (i.e. the
    /// empty-state prompt drove the creation).
    private func autoSelectNewWalletIfNeeded() {
        guard viewModel.selectedWallet == nil, let wallet = wallets.first else { return }
        selectWallet(wallet)
        recomputeSuggestions()
    }

    /// Auto-selects a freshly created category (for the current type) after the
    /// inline "Add Category" prompt.
    private func autoSelectNewCategoryIfNeeded() {
        guard viewModel.selectedCategory == nil, let category = filteredCategories.first else { return }
        viewModel.selectedCategory = category
    }
    
    // MARK: - Wallet Picker Sheet
    private var walletPickerSheet: some View {
        TransactionWalletPickerSheet(
            wallets: wallets,
            selectedWalletID: viewModel.selectedWallet?.id,
            onSelect: { wallet in
                selectWallet(wallet)
                showAllWallets = false
            },
            onDismiss: { showAllWallets = false }
        )
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
                TransactionSetupPrompt(
                    icon: "square.grid.2x2",
                    tint: .accentColor,
                    title: "transaction.setup.category.title".localized,
                    message: "transaction.setup.category.message".localized,
                    actionTitle: "category.add".localized
                ) {
                    showAddCategory = true
                }
                .padding(.vertical, 4)
            } else {
                // Show frequent categories in grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(frequentCategories) { scored in
                        CategoryGridItem(
                            category: scored.category,
                            isSelected: viewModel.selectedCategory?.id == scored.category.id,
                            isHighlighted: scored.isHighlighted
                        ) {
                            viewModel.selectedCategory = scored.category
                        }
                    }
                    
                    // Always show a "More" option if there are more than 4 categories
                    if filteredCategories.count > 4 {
                        Button {
                            showAllCategories = true
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    Image(systemName: "ellipsis")
                                        .font(.app(.title3))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 40, height: 40)
                                        .background(Color(.tertiarySystemGroupedBackground))
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                        )
                                }
                                .frame(width: 46, height: 46)

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
        .sheet(isPresented: $showAddCategory, onDismiss: autoSelectNewCategoryIfNeeded) {
            AddCategoryView(initialType: viewModel.type)
        }
    }
    
    // MARK: - Category Picker Sheet
    private var categoryPickerSheet: some View {
        TransactionCategoryPickerSheet(
            allCategories: filteredCategories,
            rankedSuggestions: orderedCategories,
            selectedCategoryID: viewModel.selectedCategory?.id,
            onSelect: { category in
                viewModel.selectedCategory = category
                showAllCategories = false
            },
            onDismiss: { showAllCategories = false }
        )
    }
    
    // MARK: - Optional Fields Section

    /// Settings-style rounded-square icon tile for consistent, native-looking form rows.
    private func fieldIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.app(.footnote, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }

    private var optionalFieldsSection: some View {
        Group {
            // Date Selection Row
            DatePicker(
                selection: $viewModel.date,
                displayedComponents: [.date]
            ) {
                Label {
                    Text("transaction.date".localized)
                } icon: {
                    fieldIcon("calendar", color: .red)
                }
            }

            // Time Selection Row
            DatePicker(
                selection: $viewModel.date,
                displayedComponents: [.hourAndMinute]
            ) {
                Label {
                    Text(L10n.TransactionAdditional.time)
                } icon: {
                    fieldIcon("clock", color: .orange)
                }
            }

            // Note Field — supports inline #tags; suggestions render below.
            Label {
                TextField(L10n.Transaction.note, text: $viewModel.note)
                    .focused($isNoteFieldFocused)
                    .submitLabel(.done)
            } icon: {
                fieldIcon("note.text", color: .gray)
            }

            // Tag suggestion chips: contextual top tags by default; switches to
            // prefix-matched autocomplete while a `#token` is being typed.
            if !suggestedTagChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestedTagChips) { scored in
                            Button {
                                insertTag(scored.tag)
                            } label: {
                                Text("#\(scored.tag)")
                                    .font(.app(.footnote, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("transaction.tag.add".localized(with: scored.tag))
                        }
                    }
                }
                .listRowSeparator(.hidden, edges: .top)
            }

            // Location Row — tappable label opens the picker; trailing circle is a one-tap current-location shortcut.
            HStack(spacing: 12) {
                fieldIcon("mappin.and.ellipse", color: .blue)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showKeyboard = false
                        isNoteFieldFocused = false
                    }
                    showLocationPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Text("transaction.location".localized)
                            .foregroundStyle(.primary)

                        Spacer(minLength: 8)

                        if let location = viewModel.selectedLocation {
                            Text(location.title)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Compact one-tap "use current location" — fills the field without opening the picker.
                Button {
                    useCurrentLocationDirectly()
                } label: {
                    ZStack {
                        if isFetchingCurrentLocation {
                            ProgressView()
                        } else {
                            Image(systemName: "location.fill")
                                .font(.app(.footnote, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .background(Color.blue.opacity(0.12), in: Circle())
                }
                .buttonStyle(.borderless)
                .disabled(isFetchingCurrentLocation)
                .accessibilityLabel("transaction.location.useCurrent".localized)
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
            Toggle("transaction.excludeFromReports".localized, isOn: $viewModel.excludeFromReports)
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
        .accessibilityLabel("\(wallet.name) wallet\(isSelected ? ", selected" : "")")
    }
}
