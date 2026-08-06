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

    @Environment(\.modelContext) private var modelContext

    // UI State
    @State private var showAllCategories = false
    @State private var showAllWallets = false
    @State private var showScanner = false
    @State private var showLocationPicker = false
    @State private var isFetchingCurrentLocation = false
    @State private var relativeDayOffset: Int = 0
    private let referenceDate = Calendar.current.startOfDay(for: Date())
    // Inline creation of a first wallet/category when the user has none.
    @State private var showAddWallet = false
    @State private var showAddCategory = false
    /// Note editing swaps the calculator keypad for the system keyboard in
    /// place; the form above never moves.
    @State private var isNoteBarVisible = false
    @FocusState private var noteFieldFocused: Bool
    @FocusState private var rateFieldFocused: Bool

    // Suggestion engine: cached, contextual rankings (same wiring as classic —
    // computed on a background context, resolved back to @Query models).
    @State private var scoredWallets: [ScoredWallet] = []
    @State private var scoredCategories: [ScoredCategory] = []
    @State private var scoredTags: [ScoredTag] = []
    /// In-flight suggestion compute; each recompute cancels its predecessor.
    @State private var suggestionTask: Task<Void, Never>?
    /// Provisional auto-picks (vs. deliberate user choices) that a late-arriving
    /// ranking is allowed to upgrade.
    @State private var autoSelectedWalletID: UUID?
    @State private var autoSelectedCategoryID: UUID?
    /// Ranking signal only — never written to the transaction's location.
    @State private var backgroundLocationKey: String?
    @State private var locationService = CurrentLocationService()

    private let maxQuickWallets = 4

    /// Free text on the detail chips (note, place name, goal name) is truncated
    /// at this width instead of stretching its pill across the row — the full
    /// value stays one tap away in the note bar / location picker.
    @ScaledMetric(relativeTo: .subheadline) private var chipTextMaxWidth: CGFloat = 180
    /// Real rendered width of the current date label (character counts badly
    /// mis-measure Khmer, which stacks combining marks and uses wider glyphs).
    @State private var measuredDateLabelWidth: CGFloat = 0
    @ScaledMetric(relativeTo: .subheadline) private var minDateLabelWidth: CGFloat = 70
    @ScaledMetric(relativeTo: .subheadline) private var maxDateLabelWidth: CGFloat = 170

    init(viewModel: AddTransactionViewModel, isNewTransaction: Bool = true) {
        self._viewModel = State(wrappedValue: viewModel)
        self.isNewTransaction = isNewTransaction
    }

    // MARK: - Derived collections (shared semantics with classic view)

    private var filteredCategories: [Category] {
        categories.filter { $0.type == viewModel.type }
    }

    private var sourceWallets: [Wallet] {
        viewModel.type == .transfer ? wallets : wallets.filter { !$0.isSavings }
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
        let limit = count > 4 ? 3 : 4

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
        let ordered = (scoredWallets.isEmpty ? sourceWallets : scoredWallets.map(\.wallet))
            .filter { wallet in sourceWallets.contains { $0.id == wallet.id } }
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
        let type = viewModel.type
        let walletID = viewModel.selectedWallet?.id
        let categoryID = viewModel.selectedCategory?.id
        let container = modelContext.container

        suggestionTask?.cancel()
        suggestionTask = Task {
            let snapshot = await TransactionSuggestionEngine.computeSuggestions(
                container: container,
                type: type,
                selectedWalletID: walletID,
                selectedCategoryID: categoryID,
                location: location
            )
            guard !Task.isCancelled else { return }
            applySuggestions(snapshot)
        }
    }

    /// Resolves the background-ranked IDs back to this view's @Query models and
    /// upgrades provisional auto-selections to the ranked top picks.
    private func applySuggestions(_ snapshot: SuggestionSnapshot) {
        let walletsByID = Dictionary(sourceWallets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let categoriesByID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        scoredWallets = snapshot.wallets.compactMap { ranked in
            walletsByID[ranked.id].map {
                ScoredWallet(wallet: $0, score: ranked.score, lastUsed: ranked.lastUsed)
            }
        }
        scoredCategories = snapshot.categories.compactMap { ranked in
            categoriesByID[ranked.id].map {
                ScoredCategory(category: $0, score: ranked.score, lastUsed: ranked.lastUsed, isHighlighted: ranked.isHighlighted)
            }
        }
        scoredTags = snapshot.tags

        guard isNewTransaction else { return }

        // Wallet: upgrade only if the current selection is still our auto-pick.
        if let current = viewModel.selectedWallet,
           current.id == autoSelectedWalletID,
           let top = scoredWallets.first?.wallet,
           top.id != current.id {
            autoSelectedWalletID = top.id
            selectWallet(top)
        }

        // Category: same rule (the compact view auto-picks a category too).
        if viewModel.selectedCategory?.id == autoSelectedCategoryID,
           let top = orderedCategories.first?.category,
           top.id != viewModel.selectedCategory?.id {
            autoSelectedCategoryID = top.id
            viewModel.selectedCategory = top
        }
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

    /// One spring for the whole chip⇄editor handoff, so the pill's tint and
    /// width, the panel's bloom and the keypad's exit all move as one gesture.
    /// Tuned close to the keyboard's own curve — the panel rides up with the
    /// keyboard rather than racing it.
    private static let noteEditorAnimation: Animation = .spring(duration: 0.32, bounce: 0.12)

    private func beginNoteEditing() {
        withAnimation(Self.noteEditorAnimation) {
            isNoteBarVisible = true
        }
    }

    private func endNoteEditing() {
        noteFieldFocused = false
        withAnimation(Self.noteEditorAnimation) {
            isNoteBarVisible = false
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Scrollable so the *form* absorbs the squeeze when the keyboard
                // is up — a plain VStack + Spacer instead compresses the bottom
                // bar's growing note field back down to one line. Content that
                // fits never bounces, so this reads identically to a static
                // layout in the normal case.
                ScrollView {
                    formContent
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.never)

                bottomBar
            }
            .background(Color(.systemGroupedBackground))
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
                    // Reads `isValid` inside its own body so a keystroke (which
                    // changes the amount → validity) only re-renders this button,
                    // not the whole screen.
                    CompactSaveButton(viewModel: viewModel) {
                        if viewModel.saveTransaction() {
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                ScannerView(isPresented: $showScanner) { result in
                    switch result {
                    case .success(let images):
                        if let firstImage = images.first {
                            let walletSnapshots = sourceWallets.map(ReceiptWalletSnapshot.init)
                            Task {
                                await viewModel.scanReceipt(
                                    image: firstImage,
                                    availableWallets: walletSnapshots,
                                    modelContext: modelContext
                                )
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
                    wallets: sourceWallets,
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
                    transactionType: viewModel.type,
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
                // Provisional preselection (name order) so the form is instantly
                // savable; upgraded to the ranked top picks when the background
                // suggestion compute lands (see applySuggestions).
                if viewModel.selectedWallet == nil, let wallet = sourceWallets.first {
                    autoSelectedWalletID = wallet.id
                    viewModel.selectedWallet = wallet
                    viewModel.syncCurrencyToWallet()
                }
                if isNewTransaction {
                    startBackgroundLocationFetch()
                    if let topCategory = filteredCategories.first {
                        autoSelectedCategoryID = topCategory.id
                        viewModel.selectedCategory = topCategory
                    }
                }
                recomputeSuggestions()
                relativeDayOffset = daysBetween(referenceDate, viewModel.date)
            }
            .onChange(of: viewModel.type) { _, _ in
                if isNewTransaction {
                    // Provisional per-type pick; the recompute upgrades it.
                    if let topCategory = filteredCategories.first {
                        autoSelectedCategoryID = topCategory.id
                        viewModel.selectedCategory = topCategory
                    } else {
                        autoSelectedCategoryID = nil
                        viewModel.selectedCategory = nil
                    }
                }
                recomputeSuggestions()
            }
            .onChange(of: viewModel.selectedWallet) { _, _ in recomputeSuggestions() }
            .onChange(of: viewModel.selectedCategory) { _, _ in recomputeSuggestions() }
            .onChange(of: viewModel.selectedLocation) { _, _ in recomputeSuggestions() }
            .onChange(of: viewModel.selectedCurrencyCode) { _, _ in
                if viewModel.type != .transfer {
                    viewModel.updateTransactionCurrencyExchangeRate()
                }
            }
            .onChange(of: relativeDayOffset) { _, newOffset in
                if let newDate = Calendar.current.date(byAdding: .day, value: newOffset, to: referenceDate) {
                    let calendar = Calendar.current
                    let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: viewModel.date)
                    if let combinedDate = calendar.date(bySettingHour: timeComponents.hour ?? 0, minute: timeComponents.minute ?? 0, second: timeComponents.second ?? 0, of: newDate) {
                        if calendar.startOfDay(for: viewModel.date) != calendar.startOfDay(for: combinedDate) {
                            viewModel.date = combinedDate
                            HapticManager.shared.selection()
                        }
                    }
                }
            }
            .onChange(of: viewModel.date) { _, newDate in
                let offset = daysBetween(referenceDate, newDate)
                if relativeDayOffset != offset {
                    relativeDayOffset = offset
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
            // Self-contained View so amount keystrokes only invalidate the card,
            // leaving the wallet/category/detail sections below untouched.
            CompactAmountCard(
                viewModel: viewModel,
                isNoteBarVisible: isNoteBarVisible,
                onTap: { endNoteEditing() }
            )

            walletSection

            if viewModel.type == .transfer {
                destinationSection
            } else {
                categorySection
            }

            detailChipRows


        }
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
            .appFont(.footnote, weight: .medium)
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
            if sourceWallets.isEmpty {
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
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
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

                        if sourceWallets.count > maxQuickWallets {
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
        guard viewModel.selectedWallet == nil, let wallet = sourceWallets.first else { return }
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
                    .appFont(.subheadline)
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
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField(L10n.Transaction.rate, value: $viewModel.exchangeRate, format: .number)
                        .keyboardType(.decimalPad)
                        .focused($rateFieldFocused)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Text(dest.currencyCode)
                        .appFont(.subheadline, weight: .semibold)

                    Spacer(minLength: 4)

                    // Isolated so per-keystroke amount changes don't re-render
                    // the surrounding wallet row / rate field.
                    TransferConvertedAmount(
                        viewModel: viewModel,
                        destinationCurrencyCode: dest.currencyCode
                    )
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
                    .appFont(.caption2)
                Text("common.more".localized)
                    .appFont(.subheadline, weight: .medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemGroupedBackground))
            .foregroundColor(.secondary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
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
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(frequentCategories) { scored in
                            CategoryChip(
                                category: scored.category,
                                isSelected: viewModel.selectedCategory?.id == scored.category.id,
                                isHighlighted: scored.isHighlighted
                            ) {
                                viewModel.selectedCategory = scored.category
                            }
                        }
                        
                        if filteredCategories.count > 4 {
                            moreChip { showAllCategories = true }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    // MARK: - Detail chips (date · time · note · location · goal)

    private var detailChipRows: some View {
        FlowLayout(spacing: 8) {
            dateChip
            timeChip
            noteChip
            locationChip
        }
    }

    /// Shared pill container for the detail chips. `isActive` marks the chip
    /// whose editor is currently open on the bottom bar.
    private func detailChip(
        icon: String,
        iconColor: Color,
        text: String,
        isSet: Bool,
        isActive: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(isActive ? Color.accentColor : iconColor)
            Text(text)
                .appFont(.subheadline, weight: .medium)
                .foregroundStyle(isActive ? Color.accentColor : (isSet ? Color.primary : Color.secondary))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: chipTextMaxWidth, alignment: .leading)
                // The note pill swaps its text for "Note" as the editor opens;
                // crossfade it instead of cutting.
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
        .background(isActive ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isActive ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Capsule())
    }

    private func daysBetween(_ start: Date, _ end: Date) -> Int {
        let calendar = Calendar.current
        let startOfStart = calendar.startOfDay(for: start)
        let startOfEnd = calendar.startOfDay(for: end)
        let components = calendar.dateComponents([.day], from: startOfStart, to: startOfEnd)
        return components.day ?? 0
    }

    private func dateLabel(forOffset offset: Int) -> String {
        guard let targetDate = Calendar.current.date(byAdding: .day, value: offset, to: referenceDate) else { return "" }
        let formatter = AppDateFormatterCache.formatter(
            dateStyle: .medium,
            timeStyle: .none,
            doesRelativeDateFormatting: true,
            locale: LanguageManager.shared.selectedLanguage.locale
        )
        return formatter.string(from: targetDate)
    }

    private var dateTextWidth: CGFloat {
        min(max(minDateLabelWidth, measuredDateLabelWidth), maxDateLabelWidth)
    }

    /// Layout-neutral probe (backgrounds don't size their parent): renders the
    /// current label at its natural size so the paged strip can be framed to the
    /// width the text actually needs, in any language or Dynamic Type size.
    private var dateLabelMeasurer: some View {
        Text(dateLabel(forOffset: relativeDayOffset))
            .appFont(.subheadline, weight: .medium)
            .lineLimit(1)
            .fixedSize()
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                measuredDateLabelWidth = width + 6
            }
    }

    private func adjustDate(by days: Int) {
        let newOffset = relativeDayOffset + days
        if (-365...365).contains(newOffset) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                relativeDayOffset = newOffset
            }
        }
    }

    private var dateChip: some View {
        HStack(spacing: 0) {
            Button {
                adjustDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .appFont(.footnote, weight: .bold)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.red)
                
                TabView(selection: $relativeDayOffset) {
                    ForEach(-365...365, id: \.self) { offset in
                        Text(dateLabel(forOffset: offset))
                            .appFont(.subheadline, weight: .medium)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: dateTextWidth, height: 24)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: dateTextWidth)
                .background(alignment: .leading) { dateLabelMeasurer }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .overlay {
                // Invisible native control: piggybacks on the system's own
                // compact-DatePicker popup (fast, correctly anchored, never
                // clipped) while the visible pill above stays fully custom.
                DatePicker(
                    "transaction.date".localized,
                    selection: $viewModel.date,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .opacity(0.02)
                .simultaneousGesture(TapGesture().onEnded { endNoteEditing() })
            }

            Button {
                adjustDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .appFont(.footnote, weight: .bold)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                    .padding(.trailing, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 36)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .accessibilityLabel("transaction.date".localized)
    }

    private var timeChip: some View {
        detailChip(
            icon: "clock",
            iconColor: .orange,
            text: viewModel.date.appFormatted(date: .omitted, time: .shortened),
            isSet: true
        )
        .overlay {
            // Invisible native control — see dateChip's overlay for why.
            DatePicker(
                "transaction.time".localized,
                selection: $viewModel.date,
                displayedComponents: [.hourAndMinute]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .opacity(0.02)
            .simultaneousGesture(TapGesture().onEnded { endNoteEditing() })
        }
        .accessibilityLabel("transaction.time".localized)
    }

    private var noteChip: some View {
        Button {
            beginNoteEditing()
        } label: {
            // While the note bar is open it owns the text — mirroring it here
            // only duplicates the editor until the pill truncates, and then
            // silently contradicts it (the pill holds the head, the field
            // follows the caret). The chip marks the destination instead.
            detailChip(
                icon: "note.text",
                iconColor: .gray,
                text: isNoteBarVisible
                    ? "transaction.noteLabel".localized
                    : (viewModel.note.isEmpty ? L10n.Transaction.note : viewModel.note),
                isSet: !viewModel.note.isEmpty,
                isActive: isNoteBarVisible
            )
        }
        .buttonStyle(.plain)
        // The pill truncates; VoiceOver still reads the whole note.
        .accessibilityLabel(viewModel.note.isEmpty
            ? L10n.Transaction.note
            : "\(L10n.Transaction.note): \(viewModel.note)")
    }

    private var locationChip: some View {
        Group {
            if isFetchingCurrentLocation {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("transaction.location".localized)
                        .appFont(.subheadline, weight: .medium)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            } else {
                HStack(spacing: 6) {
                    Button {
                        endNoteEditing()
                        showLocationPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: viewModel.selectedLocation == nil ? "mappin.and.ellipse" : "mappin.circle.fill")
                                .appFont(.footnote, weight: .semibold)
                                .foregroundStyle(.blue)
                            Text(viewModel.selectedLocation?.title ?? "transaction.location".localized)
                                .appFont(.subheadline, weight: .medium)
                                .foregroundStyle(viewModel.selectedLocation != nil ? .primary : .secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: chipTextMaxWidth, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)

                    if viewModel.selectedLocation != nil {
                        Button {
                            viewModel.selectedLocation = nil
                            HapticManager.shared.selection()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .appFont(.footnote)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }
        }
        .accessibilityLabel(viewModel.selectedLocation.map {
            "\("transaction.location".localized): \($0.title)"
        } ?? "transaction.location".localized)
    }

    private var calculatorSuggestionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Location suggestion chip (if location is not set)
                if viewModel.selectedLocation == nil {
                    Button {
                        useCurrentLocationDirectly()
                    } label: {
                        HStack(spacing: 4) {
                            if isFetchingCurrentLocation {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "location.fill")
                                    .appFont(.caption2)
                            }
                            Text("transaction.location.useCurrent".localized)
                                .appFont(.footnote, weight: .medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .foregroundColor(.blue)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isFetchingCurrentLocation)
                }

                // Tag suggestion chips
                ForEach(suggestedTagChips) { scored in
                    TagSuggestionChip(tag: scored.tag) { insertTag(scored.tag) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Bottom bar (keypad ⇄ note bar)

    @ViewBuilder
    private var bottomBar: some View {
        if isNoteBarVisible {
            // Blooms open from its top edge — the edge nearest the chip that
            // spawned it — while the keyboard supplies the upward motion. A
            // `.move(edge: .bottom)` here would double that rise and overshoot.
            noteBar
                .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
        } else if rateFieldFocused {
            // The system decimal pad owns the bottom while the rate is edited.
            EmptyView()
        } else {
            VStack(spacing: 0) {
                if viewModel.selectedLocation == nil || !suggestedTagChips.isEmpty {
                    calculatorSuggestionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                // Reads `isValid` (amount-dependent) inside its own body so a
                // keystroke re-renders only the keypad, not the form above it.
                CompactKeypad(viewModel: viewModel) {
                    if viewModel.saveTransaction() {
                        dismiss()
                    }
                }
            }
            .transition(.move(edge: .bottom))
        }
    }

    /// Floating editor panel: an elevated card so the field reads as the focused
    /// surface rather than another row blended into the form background.
    private var noteBar: some View {
        VStack(spacing: 10) {
            if !suggestedTagChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestedTagChips) { scored in
                            TagSuggestionChip(tag: scored.tag) { insertTag(scored.tag) }
                        }
                    }
                    // Matches the field row below so the panel keeps one
                    // left margin for everything inside it.
                    .padding(.horizontal, 12)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "note.text")
                        .appFont(.footnote, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)

                    // Grows with the note so the whole thing stays readable while
                    // typing — a single-line field only ever shows a window around
                    // the caret, which is also the only place a long note can be
                    // read back in full. Return inserts a newline on a vertical
                    // field, so "Done" is the way out.
                    TextField(L10n.Transaction.note, text: $viewModel.note, axis: .vertical)
                        .focused($noteFieldFocused)
                        .lineLimit(1...4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Color(.tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                )

                Button("common.done".localized) {
                    endNoteEditing()
                }
                .appFont(.subheadline, weight: .semibold)
                .padding(.bottom, 10)
            }
            // 12 on both axes so the field's corner sits on the arc of the
            // panel's — unequal insets can't be concentric on both edges.
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 12)
        // `hero`, matching the amount card: both are the elevated focal surface
        // of their moment. This also makes the field inside it exactly
        // concentric — 24 minus its 12pt inset is the field's own 12.
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.hero, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.16), radius: 14, y: 3)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .onAppear { noteFieldFocused = true }
    }
}

// MARK: - Tag suggestion chip

/// One `#tag` pill in the keypad / note-bar suggestion rails. Long tags truncate
/// so a single outlier can't monopolise the rail.
private struct TagSuggestionChip: View {
    let tag: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .footnote) private var maxLabelWidth: CGFloat = 140

    var body: some View {
        Button(action: action) {
            Text("#\(tag)")
                .appFont(.footnote, weight: .medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: maxLabelWidth, alignment: .leading)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("transaction.tag.add".localized(with: tag))
    }
}

// MARK: - Amount Card (isolated for per-keystroke updates)

/// The amount/expression display. Extracted into its own `View` so that typing
/// on the keypad — which mutates `expression`/`evaluatedAmount` — only
/// invalidates this subtree, leaving the wallet/category/detail sections of
/// `CompactAddTransactionView` untouched (they don't read the amount, and the
/// parent body no longer does either).
private struct CompactAmountCard: View {
    @Bindable var viewModel: AddTransactionViewModel
    let isNoteBarVisible: Bool
    let onTap: () -> Void

    /// Glass is a translucent material; when the user has asked the system to
    /// reduce transparency we fall back to the opaque tinted fill.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the caret blink. Started once on appear as a repeating animation.
    @State private var caretDimmed = false

    /// The card's identity colour — also the caret and the glass tint, so the
    /// whole surface reads as "expense" / "income" / "transfer" at a glance.
    private var typeTint: Color {
        switch viewModel.type {
        case .expense: return ThemeManager.shared.expenseColor
        case .income: return ThemeManager.shared.incomeColor
        case .transfer: return .blue
        default: return .secondary
        }
    }

    /// A fixed hero radius, matching the Home summary card — deliberately *not*
    /// `ConcentricRectangle`. Concentricity only means something when the child's
    /// corner can share a center of curvature with the parent's, which needs
    /// roughly equal insets on both axes. This card is inset 16pt horizontally
    /// but sits a nav bar's height below the sheet's top edge, so its corners
    /// land in the sheet's inner region where no common center exists; the
    /// concentric radius was being computed from a relationship the eye can't
    /// see. At this card's size the resulting 16pt floor also read pinched.
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CornerRadius.hero, style: .continuous)
    }

    private var isAmountEmpty: Bool {
        viewModel.expression.isEmpty && viewModel.evaluatedAmount == 0
    }

    private var exchangeRateString: String? {
        guard let wallet = viewModel.selectedWallet,
              viewModel.selectedCurrencyCode != wallet.currencyCode else { return nil }

        let convertedAmount = viewModel.evaluatedAmount * Decimal(viewModel.exchangeRate)
        return "≈ \(convertedAmount.formattedAmount(for: wallet.currencyCode))"
    }

    private var amountDisplayText: String {
        if !isNoteBarVisible && !viewModel.expression.isEmpty {
            return formatExpressionForDisplay(viewModel.expression)
        } else if viewModel.evaluatedAmount > 0 {
            return formatAmount(viewModel.evaluatedAmount)
        } else {
            return "0"
        }
    }

    private var amountHasOperators: Bool {
        let operators = CharacterSet(charactersIn: "+-×÷")
        return viewModel.expression.rangeOfCharacter(from: operators) != nil
    }

    private func formatExpressionForDisplay(_ expr: String) -> String {
        var result = ""
        var currentNumber = ""
        for char in expr {
            if char.isNumber || char == "." {
                currentNumber.append(char)
            } else if "+-×÷".contains(char) {
                if !currentNumber.isEmpty {
                    result += formatNumberString(currentNumber)
                    currentNumber = ""
                }
                result.append(char)
            }
        }
        if !currentNumber.isEmpty {
            result += formatNumberString(currentNumber)
        }
        return result
    }

    private func formatNumberString(_ numStr: String) -> String {
        let parts = numStr.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let intPart = parts.first else { return numStr }
        let reversed = String(intPart.reversed())
        var formatted = ""
        for (index, char) in reversed.enumerated() {
            if index > 0 && index % 3 == 0 {
                formatted.append(",")
            }
            formatted.append(char)
        }
        let intFormatted = String(formatted.reversed())
        if parts.count > 1 {
            return "\(intFormatted).\(parts[1])"
        } else if numStr.hasSuffix(".") {
            return "\(intFormatted)."
        }
        return intFormatted
    }

    private func formatAmount(_ value: Decimal) -> String {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        return CurrencyFormatterCache.keypadAmount.string(from: NSNumber(value: doubleValue)) ?? "0"
    }

    /// Blinking insertion point, matching the system text caret. Capsule-capped
    /// and tinted to the transaction type; held solid under Reduce Motion.
    private var caret: some View {
        Capsule()
            .fill(typeTint)
            .frame(width: 2.5, height: 36)
            .opacity(caretDimmed ? 0 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    caretDimmed = true
                }
            }
            .onDisappear { caretDimmed = false }
    }

    /// Secondary readouts under the amount. Both are trailing-aligned on one row
    /// so they hang off the amount's own edge instead of drifting centre.
    @ViewBuilder
    private var subline: some View {
        let showsResult = amountHasOperators && viewModel.evaluatedAmount > 0
        if showsResult || exchangeRateString != nil {
            HStack(spacing: 10) {
                Spacer(minLength: 0)

                if showsResult {
                    Text("= \(formatAmount(viewModel.evaluatedAmount))")
                        .appFont(.callout, weight: .medium)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                if let exchangeRateStr = exchangeRateString {
                    Text(exchangeRateStr)
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // Currency selector inline on the left
                CurrencySegmentedPicker(currencyCode: $viewModel.selectedCurrencyCode)
                    .padding(.leading, 8)

                Spacer(minLength: 8)

                // Amount input in the middle at the right
                HStack(alignment: .center, spacing: 4) {
                    Text(String.currencySymbol(for: viewModel.selectedCurrencyCode))
                        .appFont(size: 28, weight: .semibold)
                        .foregroundStyle(isAmountEmpty ? Color.secondary.opacity(0.5) : Color.secondary)

                    Text(amountDisplayText)
                        .appFont(size: 44, weight: .bold)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .foregroundStyle(isAmountEmpty ? Color.secondary.opacity(0.5) : Color.primary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.1), value: amountDisplayText)

                    if !isNoteBarVisible {
                        caret
                            .accessibilityHidden(true)
                    }
                }
                .padding(.trailing, 8)
                // One element: "Amount, $ 1,234" rather than three stray
                // fragments (symbol, digits, caret) as VoiceOver swipes past.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.Transaction.amount)
                .accessibilityValue("\(String.currencySymbol(for: viewModel.selectedCurrencyCode)) \(amountDisplayText)")
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)

            subline
        }
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        let shape = cardShape

        Group {
            if reduceTransparency {
                cardContent
                    .background(typeTint.opacity(0.15), in: shape)
            } else {
                cardContent
                    .glassEffect(.regular.tint(typeTint.opacity(0.18)), in: shape)
            }
        }
        // The whole card dismisses the note editor, not just the digits — the
        // amount is the thing the user is coming back to.
        .contentShape(shape)
        .onTapGesture { onTap() }
        .animation(.easeInOut(duration: 0.25), value: viewModel.type)
    }
}

// MARK: - Transfer converted-amount (isolated amount reader)

/// The "≈ converted" preview shown on cross-currency transfers. Isolated so its
/// per-keystroke amount reads don't re-render the surrounding destination row.
private struct TransferConvertedAmount: View {
    let viewModel: AddTransactionViewModel
    let destinationCurrencyCode: String

    var body: some View {
        let convertedAmount = viewModel.evaluatedAmount * Decimal(viewModel.exchangeRate)
        Text("≈ \(convertedAmount.formattedAmount(for: destinationCurrencyCode))")
            .appFont(.caption)
            .foregroundStyle(.blue)
            .lineLimit(1)
    }
}

// MARK: - Save affordances (isolated `isValid` readers)

/// Toolbar save button. Reads `isValid` (which depends on the amount) in its own
/// body so amount changes don't invalidate the parent screen.
private struct CompactSaveButton: View {
    let viewModel: AddTransactionViewModel
    let onSave: () -> Void

    var body: some View {
        Button {
            onSave()
        } label: {
            Image(systemName: "checkmark")
                .fontWeight(.semibold)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.isValid)
        .accessibilityLabel("common.save".localized)
    }
}

/// Wraps the shared `CalculatorKeyboardView` so the amount-dependent
/// `isSaveDisabled` read happens here, not in the parent's body.
private struct CompactKeypad: View {
    @Bindable var viewModel: AddTransactionViewModel
    let onSave: () -> Void

    var body: some View {
        CalculatorKeyboardView(
            expression: $viewModel.expression,
            evaluatedAmount: $viewModel.evaluatedAmount,
            onSave: onSave,
            isSaveDisabled: !viewModel.isValid
        )
    }
}

// MARK: - Category Chip Component
struct CategoryChip: View {
    let category: Category
    let isSelected: Bool
    let isHighlighted: Bool
    let action: () -> Void

    /// Long category names truncate rather than stretching the pill past the
    /// row (or, in a wrapping flow, past the screen edge).
    @ScaledMetric(relativeTo: .subheadline) private var maxLabelWidth: CGFloat = 150

    private var categoryColor: Color {
        Color(hex: category.colorHex) ?? .gray
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .appFont(.caption2)
                    .foregroundStyle(isSelected ? .white : categoryColor)
                Text(category.displayName)
                    .appFont(.subheadline, weight: .medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: maxLabelWidth, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? categoryColor : Color(.tertiarySystemGroupedBackground))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
            .overlay(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                            .stroke(Color.clear, lineWidth: 0)
                    } else if isHighlighted {
                        RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                            .stroke(categoryColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    } else {
                        RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.displayName) category\(isSelected ? ", selected" : "")")
    }
}
