import SwiftUI
import SwiftData
import CoreLocation

/// One-screen transaction entry: the calculator keypad is always visible and
/// every input is reachable in a single tap — no scrolling, no keyboard
/// dismissal. Lives side-by-side with `AddTransactionView` (classic) behind
/// the "Compact Transaction Entry" setting; `AddTransactionContainer` picks.
///
/// Debt-linked and balance-adjustment entries always use the classic screen
/// (they render locked, special-cased UI) — the container gates them.
struct CompactAddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: AddTransactionViewModel
    let isNewTransaction: Bool

    // Query data
    @Query(filter: #Predicate<Category> { $0.deletedAt == nil }, sort: \Category.name) private var categories: [Category]
    @Query(filter: #Predicate<Wallet> { !$0.isArchived && $0.deletedAt == nil }, sort: \Wallet.name) private var wallets: [Wallet]
    @Query(filter: #Predicate<SavingsGoal> { $0.deletedAt == nil }, sort: \SavingsGoal.priority) private var savingsGoals: [SavingsGoal]

    @Environment(\.modelContext) private var modelContext

    // UI State
    @State private var showAllCategories = false
    @State private var showAllWallets = false
    @State private var showScanner = false
    @State private var showLocationPicker = false
    @State private var showDatePopover = false
    @State private var showTimePopover = false
    @State private var isFetchingCurrentLocation = false
    // Inline creation of a first wallet/category when the user has none.
    @State private var showAddWallet = false
    @State private var showAddCategory = false
    /// Note editing swaps the calculator keypad for the system keyboard in
    /// place; the form above never moves.
    @State private var isNoteBarVisible = false
    @FocusState private var noteFieldFocused: Bool
    @FocusState private var rateFieldFocused: Bool

    // Suggestion engine: cached, contextual rankings (same wiring as classic)
    @State private var scoredWallets: [ScoredWallet] = []
    @State private var scoredCategories: [ScoredCategory] = []
    @State private var scoredTags: [ScoredTag] = []
    @State private var tagSourceTransactions: [Transaction] = []
    /// Ranking signal only — never written to the transaction's location.
    @State private var backgroundLocationKey: String?
    @State private var locationService = CurrentLocationService()

    private let maxQuickWallets = 4

    init(viewModel: AddTransactionViewModel, isNewTransaction: Bool = true) {
        self._viewModel = State(wrappedValue: viewModel)
        self.isNewTransaction = isNewTransaction
    }

    // MARK: - Derived collections (shared semantics with classic view)

    private var filteredCategories: [Category] {
        categories.filter { $0.type == viewModel.type }
    }

    private var orderedCategories: [ScoredCategory] {
        let typeMatched = scoredCategories.filter { $0.category.type == viewModel.type }
        if typeMatched.isEmpty {
            return filteredCategories.map {
                ScoredCategory(category: $0, score: 0, lastUsed: nil, isHighlighted: false)
            }
        }
        return typeMatched
    }

    private var frequentCategories: [ScoredCategory] {
        let sorted = orderedCategories
        let count = filteredCategories.count
        let limit = count > 4 ? 3 : 4 // 3 + More on one strict row

        var items = Array(sorted.prefix(limit))
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

    private var frequentWallets: [Wallet] {
        let ordered = scoredWallets.isEmpty ? wallets : scoredWallets.map(\.wallet)
        return Array(ordered.prefix(maxQuickWallets))
    }

    // MARK: - Suggestion recompute

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

    private var suggestedTagChips: [ScoredTag] {
        guard !scoredTags.isEmpty else { return [] }

        let activeToken = noteFieldFocused
            ? TransactionTagParser.activeTagToken(in: viewModel.note)
            : nil
        var existing = Set(TransactionTagParser.tags(in: viewModel.note).map { $0.lowercased() })
        if let activeToken, !activeToken.isEmpty {
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

    private func insertTag(_ tag: String) {
        var note = viewModel.note
        if noteFieldFocused, let token = TransactionTagParser.activeTagToken(in: note) {
            note.removeLast(token.count + 1)
        } else if !note.isEmpty, note.last?.isWhitespace != true {
            note += " "
        }
        note += "#\(tag) "
        viewModel.note = note
        HapticManager.shared.selection()
    }

    private func loadTagSourceTransactions() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? .distantPast
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= cutoff && $0.note != nil && $0.deletedAt == nil }
        )
        tagSourceTransactions = (try? modelContext.fetch(descriptor)) ?? []
    }

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
                // Optional ranking signal; ignore unavailable/denied/no-fix.
            }
        }
    }

    private func useCurrentLocationDirectly() {
        guard !isFetchingCurrentLocation else { return }
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

    // MARK: - Note editing (keypad ⇄ system keyboard swap)

    private func beginNoteEditing() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isNoteBarVisible = true
        }
    }

    private func endNoteEditing() {
        noteFieldFocused = false
        withAnimation(.easeInOut(duration: 0.2)) {
            isNoteBarVisible = false
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            // Bounces only when it doesn't fit (e.g. accessibility text sizes);
            // at standard sizes the whole form sits above the keypad statically.
            ScrollView {
                formContent
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.never)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    typeSelector
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.Common.cancel)
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    overflowMenu
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
                    .accessibilityLabel("common.save".localized)
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
            .sheet(isPresented: $showAllWallets) {
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
            .sheet(isPresented: $showAllCategories) {
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
            .sheet(isPresented: $showAddWallet, onDismiss: autoSelectNewWalletIfNeeded) {
                AddWalletView(viewModel: AddWalletViewModel(dataService: SwiftDataService(modelContext: modelContext)))
            }
            .sheet(isPresented: $showAddCategory, onDismiss: autoSelectNewCategoryIfNeeded) {
                AddCategoryView(initialType: viewModel.type)
            }
            .onAppear {
                loadTagSourceTransactions()
                recomputeSuggestions()
                if viewModel.selectedWallet == nil, let wallet = scoredWallets.first?.wallet ?? wallets.first {
                    viewModel.selectedWallet = wallet
                    viewModel.syncCurrencyToWallet()
                    recomputeSuggestions()
                }
                if isNewTransaction {
                    startBackgroundLocationFetch()
                }
            }
            .onChange(of: viewModel.type) { _, _ in recomputeSuggestions() }
            .onChange(of: viewModel.selectedWallet) { _, _ in recomputeSuggestions() }
            .onChange(of: viewModel.selectedCategory) { _, _ in recomputeSuggestions() }
            .onChange(of: viewModel.selectedLocation) { _, _ in recomputeSuggestions() }
            .onChange(of: viewModel.selectedCurrencyCode) { _, _ in
                if viewModel.type != .transfer {
                    viewModel.updateTransactionCurrencyExchangeRate()
                }
            }
            .onChange(of: viewModel.destinationWallet) { _, newDest in
                guard let dest = newDest else {
                    viewModel.selectedSavingsGoal = nil
                    return
                }
                let matchingGoals = savingsGoals.filter { goal in
                    !goal.isCompleted && goal.linkedWallet?.id == dest.id
                }
                if matchingGoals.count == 1 {
                    viewModel.selectedSavingsGoal = matchingGoals.first
                }
            }
            .onChange(of: noteFieldFocused) { _, focused in
                // Swipe-down keyboard dismissal should also restore the keypad.
                if !focused && isNoteBarVisible {
                    endNoteEditing()
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Form

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            amountCard

            walletSection

            if viewModel.type == .transfer {
                destinationSection
            } else {
                categorySection
            }

            detailChipRow
        }
    }

    // MARK: - Amount card

    private var amountBackground: Color {
        switch viewModel.type {
        case .expense: return ThemeManager.shared.expenseColor.opacity(0.15)
        case .income: return ThemeManager.shared.incomeColor.opacity(0.15)
        case .transfer: return Color.blue.opacity(0.1)
        default: return Color(.secondarySystemGroupedBackground)
        }
    }

    private var exchangeRateString: String? {
        guard let wallet = viewModel.selectedWallet,
              viewModel.selectedCurrencyCode != wallet.currencyCode else { return nil }

        let rate = viewModel.exchangeRate
        let rateString = rate.formatted(.number.precision(.significantDigits(2...6)))
        return "1 \(viewModel.selectedCurrencyCode) ≈ \(rateString) \(wallet.currencyCode)"
    }

    private var amountCard: some View {
        VStack(spacing: 0) {
            AmountDisplayView(
                amount: viewModel.evaluatedAmount,
                currencyCode: $viewModel.selectedCurrencyCode,
                expression: viewModel.expression,
                isEditing: !isNoteBarVisible,
                onTap: {
                    // Tapping the amount hands input back to the keypad.
                    endNoteEditing()
                }
            )
            if let exchangeRateStr = exchangeRateString {
                Label(exchangeRateStr, systemImage: "lock.fill")
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .background(amountBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Type selector

    private var typeSelector: some View {
        Picker("transaction.type".localized, selection: $viewModel.type) {
            Text(L10n.Transaction.TransactionType.expense).tag(TransactionType.expense)
            Text(L10n.Transaction.TransactionType.income).tag(TransactionType.income)
            Text(L10n.Transaction.TransactionType.transfer).tag(TransactionType.transfer)
        }
        .pickerStyle(.segmented)
        .onChange(of: viewModel.type) { _, newType in
            if newType != .transfer {
                viewModel.selectedCategory = nil
                viewModel.selectedSavingsGoal = nil
            }
        }
    }

    // MARK: - Wallet sections

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.app(.footnote, weight: .medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.leading, 4)
    }

    private func selectWallet(_ wallet: Wallet) {
        viewModel.selectedWallet = wallet
        viewModel.syncCurrencyToWallet()
        if viewModel.type == .transfer {
            viewModel.updateExchangeRate()
        } else {
            viewModel.updateTransactionCurrencyExchangeRate()
        }
    }

    @ViewBuilder
    private var walletSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("transaction.fromWallet".localized)
            if wallets.isEmpty {
                TransactionSetupPrompt(
                    icon: "wallet.pass",
                    tint: .accentColor,
                    title: "transaction.setup.wallet.title".localized,
                    message: "transaction.setup.wallet.message".localized,
                    actionTitle: "wallet.add".localized
                ) {
                    endNoteEditing()
                    showAddWallet = true
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
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
                            moreChip { showAllWallets = true }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    /// Auto-selects the wallet the user just created so a first-time entry can be
    /// saved immediately. Only acts when nothing is selected yet.
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

    private var destinationSection: some View {
        let availableWallets = wallets.filter { $0.id != viewModel.selectedWallet?.id }

        return VStack(alignment: .leading, spacing: 6) {
            sectionLabel("transaction.toWallet".localized)
            if availableWallets.isEmpty {
                Text("transaction.noOtherWallets".localized)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
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
                    .padding(.horizontal, 2)
                }
            }

            if let source = viewModel.selectedWallet,
               let dest = viewModel.destinationWallet,
               source.currencyCode != dest.currencyCode {
                HStack(spacing: 6) {
                    Text("1 \(source.currencyCode) =")
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                    TextField(L10n.Transaction.rate, value: $viewModel.exchangeRate, format: .number)
                        .keyboardType(.decimalPad)
                        .focused($rateFieldFocused)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Text(dest.currencyCode)
                        .font(.app(.subheadline, weight: .semibold))

                    Spacer(minLength: 4)

                    let convertedAmount = viewModel.evaluatedAmount * Decimal(viewModel.exchangeRate)
                    Text("≈ \(convertedAmount.formattedAmount(for: dest.currencyCode))")
                        .font(.app(.caption))
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
                .padding(.top, 2)
                .padding(.leading, 4)
            }
        }
    }

    private func moreChip(action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category section

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(L10n.Category.title)
            if filteredCategories.isEmpty {
                TransactionSetupPrompt(
                    icon: "square.grid.2x2",
                    tint: .accentColor,
                    title: "transaction.setup.category.title".localized,
                    message: "transaction.setup.category.message".localized,
                    actionTitle: "category.add".localized
                ) {
                    endNoteEditing()
                    showAddCategory = true
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
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

                    if filteredCategories.count > 4 {
                        Button {
                            showAllCategories = true
                        } label: {
                            VStack(spacing: 4) {
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
                                    .frame(width: 46, height: 46)

                                Text("common.more".localized)
                                    .font(.app(.caption2))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Detail chips (date · time · note · location · goal)

    private var detailChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                dateChip
                timeChip
                noteChip
                locationChip
                if viewModel.type == .transfer {
                    savingsGoalChip
                }
                if viewModel.excludeFromReports {
                    excludedChip
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    /// Shared pill container for the detail chips.
    private func detailChip(
        icon: String,
        iconColor: Color,
        text: String,
        isSet: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.app(.footnote, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(text)
                .font(.app(.subheadline, weight: .medium))
                .foregroundStyle(isSet ? .primary : .secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Capsule())
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true // "Today" / "Yesterday", localized
        return formatter.string(from: viewModel.date)
    }

    private var dateChip: some View {
        Button {
            endNoteEditing()
            showDatePopover = true
        } label: {
            detailChip(icon: "calendar", iconColor: .red, text: dateLabel, isSet: true)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDatePopover, arrowEdge: .bottom) {
            DatePicker(
                "transaction.date".localized,
                selection: $viewModel.date,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .frame(width: 320, height: 340)
            .padding(8)
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("transaction.date".localized)
    }

    private var timeChip: some View {
        Button {
            endNoteEditing()
            showTimePopover = true
        } label: {
            detailChip(
                icon: "clock",
                iconColor: .orange,
                text: viewModel.date.formatted(date: .omitted, time: .shortened),
                isSet: true
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showTimePopover, arrowEdge: .bottom) {
            DatePicker(
                "transaction.time".localized,
                selection: $viewModel.date,
                displayedComponents: [.hourAndMinute]
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(width: 220)
            .padding(8)
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("transaction.time".localized)
    }

    private var noteChip: some View {
        Button {
            beginNoteEditing()
        } label: {
            detailChip(
                icon: "note.text",
                iconColor: .gray,
                text: viewModel.note.isEmpty ? L10n.Transaction.note : viewModel.note,
                isSet: !viewModel.note.isEmpty
            )
            .frame(maxWidth: 180, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Transaction.note)
    }

    private var locationChip: some View {
        Menu {
            Button {
                useCurrentLocationDirectly()
            } label: {
                Label("transaction.location.useCurrent".localized, systemImage: "location.fill")
            }
            Button {
                endNoteEditing()
                showLocationPicker = true
            } label: {
                Label("transaction.location.pick".localized, systemImage: "map")
            }
            if viewModel.selectedLocation != nil {
                Button(role: .destructive) {
                    viewModel.selectedLocation = nil
                } label: {
                    Label("transaction.location.clear".localized, systemImage: "xmark.circle")
                }
            }
        } label: {
            Group {
                if isFetchingCurrentLocation {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("transaction.location".localized)
                            .font(.app(.subheadline, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 36)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                } else {
                    detailChip(
                        icon: viewModel.selectedLocation == nil ? "mappin.and.ellipse" : "mappin.circle.fill",
                        iconColor: .blue,
                        text: viewModel.selectedLocation?.title ?? "transaction.location".localized,
                        isSet: viewModel.selectedLocation != nil
                    )
                    .frame(maxWidth: 180, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("transaction.location".localized)
    }

    private var savingsGoalChip: some View {
        let eligibleGoals = savingsGoals.filter { goal in
            !goal.isCompleted && (goal.linkedWallet == nil || goal.linkedWallet?.id == viewModel.destinationWallet?.id)
        }
        let sortedGoals = eligibleGoals.sorted { g1, g2 in
            let g1Matches = g1.linkedWallet?.id == viewModel.destinationWallet?.id && g1.linkedWallet != nil
            let g2Matches = g2.linkedWallet?.id == viewModel.destinationWallet?.id && g2.linkedWallet != nil
            if g1Matches != g2Matches { return g1Matches }
            return g1.priority < g2.priority
        }

        return Menu {
            Button {
                viewModel.selectedSavingsGoal = nil
            } label: {
                Label("budget.threshold.none".localized, systemImage: "circle.slash")
            }
            ForEach(sortedGoals) { goal in
                Button {
                    viewModel.selectedSavingsGoal = goal
                } label: {
                    Label(goal.name, systemImage: goal.iconName)
                }
            }
        } label: {
            detailChip(
                icon: viewModel.selectedSavingsGoal?.iconName ?? "flag",
                iconColor: viewModel.selectedSavingsGoal.flatMap { Color(hex: $0.colorHex) } ?? .green,
                text: viewModel.selectedSavingsGoal?.name ?? L10n.Savings.selectGoal,
                isSet: viewModel.selectedSavingsGoal != nil
            )
            .frame(maxWidth: 160, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Savings.selectGoal)
    }

    /// Visible only while "Exclude from Reports" is on (toggled in the ⋯ menu);
    /// tapping it switches the exclusion back off.
    private var excludedChip: some View {
        Button {
            viewModel.excludeFromReports = false
            HapticManager.shared.selection()
        } label: {
            detailChip(
                icon: "eye.slash.fill",
                iconColor: .orange,
                text: "transaction.excludeFromReports".localized,
                isSet: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("transaction.excludeFromReports".localized)
    }

    // MARK: - Overflow menu

    private var overflowMenu: some View {
        Menu {
            if isNewTransaction {
                Button {
                    endNoteEditing()
                    showScanner = true
                } label: {
                    Label("transaction.scanReceipt".localized, systemImage: "doc.text.viewfinder")
                }
            }
            Toggle(isOn: $viewModel.excludeFromReports) {
                Label("transaction.excludeFromReports".localized, systemImage: "eye.slash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - Bottom bar (keypad ⇄ note bar)

    @ViewBuilder
    private var bottomBar: some View {
        if isNoteBarVisible {
            noteBar
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if rateFieldFocused {
            // The system decimal pad owns the bottom while the rate is edited.
            EmptyView()
        } else {
            CalculatorKeyboardView(
                expression: $viewModel.expression,
                evaluatedAmount: $viewModel.evaluatedAmount,
                onSave: {
                    if viewModel.saveTransaction() {
                        dismiss()
                    }
                },
                isSaveDisabled: !viewModel.isValid
            )
            .transition(.move(edge: .bottom))
        }
    }

    private var noteBar: some View {
        VStack(spacing: 8) {
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
                    .padding(.horizontal, 16)
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "note.text")
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField(L10n.Transaction.note, text: $viewModel.note)
                    .focused($noteFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { endNoteEditing() }

                Button("common.done".localized) {
                    endNoteEditing()
                }
                .font(.app(.subheadline, weight: .semibold))
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .onAppear { noteFieldFocused = true }
    }
}
