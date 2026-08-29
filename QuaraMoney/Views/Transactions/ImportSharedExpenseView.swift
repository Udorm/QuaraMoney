import SwiftUI
import SwiftData

/// Staging screen for an incoming shared expense — from QuaraMoney's own split
/// sheet (v1) or from MitraTrip's "Export to QuaraMoney" (v2, per-expense).
///
/// Nothing here commits automatically. A custom URL scheme is an unauthenticated
/// entry point — any app or web page can invoke `quaramoney://split` — so the
/// user reviews and confirms every import, and the sender's claimed identity is
/// never rendered as a trust signal.
///
/// Built on a native inset-grouped `List`: the previous version hand-rolled the
/// grouped look with `VStack` + `Divider().padding(.leading, 56)` + a manual
/// `secondarySystemGroupedBackground`, which was fine while every row was a
/// read-only label but has to re-earn row metrics, Dynamic Type reflow and
/// VoiceOver semantics the moment the rows become editable controls.
///
/// The header, the compact share summary and the entry-row anatomy mirror
/// MitraTrip's export sheet, so the handoff reads as one flow across two apps.
/// The rows themselves follow `TransactionRowView` — category leading, note
/// beneath it, amount over date on the trailing edge — because that is what they
/// are about to become.
struct ImportSharedExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let payload: SharedExpensePayload

    @Query(
        filter: #Predicate<Wallet> { !$0.isArchived && $0.deletedAt == nil },
        sort: \Wallet.name
    ) private var wallets: [Wallet]

    @Query(
        filter: #Predicate<Category> { $0.deletedAt == nil },
        sort: \Category.name
    ) private var allCategories: [Category]

    // Editable staging state
    @State private var selectedWallet: Wallet?
    @State private var selectedCategory: Category?
    @State private var date = Date()
    @State private var note = ""
    @State private var rateText = ""
    @State private var excludedEntryIDs: Set<String> = []
    /// Per-entry category overrides, keyed by `SharedExpenseEntry.sourceId`.
    @State private var entryCategoryOverrides: [String: UUID] = [:]

    @State private var didPrepare = false
    @State private var isSaving = false
    @State private var duplicateEntryIDs: Set<String> = []
    @State private var errorMessage: String?
    @State private var showConfirm = false
    @State private var showAllWallets = false
    @State private var showAddWallet = false
    @State private var categoryPickerTarget: CategoryPickerTarget?

    // Suggestion engine
    @State private var scoredWallets: [ScoredWallet] = []
    @State private var suggestionTask: Task<Void, Never>?
    @State private var autoSelectedWalletID: UUID?

    private let maxQuickWallets = 4

    /// How far the gradient reaches: toolbar plus the handoff header, fading out
    /// before the summary card. Scaled so it still covers the header when
    /// Dynamic Type grows it.
    @ScaledMetric(relativeTo: .body) private var backdropHeight: CGFloat = 250

    /// Which category picker is open — the consolidated one, or one entry's.
    private enum CategoryPickerTarget: Identifiable {
        case consolidated
        case entry(String)

        var id: String {
            switch self {
            case .consolidated: "consolidated"
            case .entry(let sourceID): "entry-\(sourceID)"
            }
        }
    }

    // MARK: - Derived

    /// Savings wallets can't receive direct expense transactions.
    private var sourceWallets: [Wallet] { wallets.filter { !$0.isSavings } }

    private var expenseCategories: [Category] { allCategories.filter { $0.type == .expense } }

    private var entries: [SharedExpenseEntry] { payload.entries ?? [] }

    private var isDetailed: Bool { payload.isDetailed }

    private var includedEntries: [SharedExpenseEntry] {
        entries.filter { !excludedEntryIDs.contains($0.sourceId) }
    }

    private var currencyCode: String { payload.currencyCode }

    /// The amount that will actually be committed, in minor units — the sum of
    /// the included entries in Detailed mode, the payload total otherwise.
    private var totalMinor: Int64 {
        if isDetailed {
            return includedEntries.reduce(into: Int64(0)) { $0 += $1.amountMinor }
        }
        if let source = payload.source { return source.totalMinor }
        return MoneyMinorUnitConverter.toMinorUnits(payload.splitAmount, currencyCode: currencyCode)
    }

    private var totalAmount: Decimal {
        MoneyMinorUnitConverter.fromMinorUnits(totalMinor, currencyCode: currencyCode)
    }

    private var transactionCount: Int { isDetailed ? includedEntries.count : 1 }

    private var isCrossCurrency: Bool {
        guard let wallet = selectedWallet else { return false }
        return wallet.currencyCode.caseInsensitiveCompare(currencyCode) != .orderedSame
    }

    /// The rate actually applied: the user's override when it parses, otherwise
    /// today's rate from `CurrencyManager`.
    ///
    /// `CurrencyManager` keeps only *current* rates, so a three-week-old expense
    /// would silently be converted at today's rate. Surfacing it as an editable
    /// field is the difference between an estimate the user accepted and one
    /// applied behind their back.
    private var effectiveRate: Decimal {
        guard let wallet = selectedWallet else { return 1 }
        guard isCrossCurrency else { return 1 }
        if let override = Decimal(string: rateText.trimmingCharacters(in: .whitespaces)), override > 0 {
            return override
        }
        return CurrencyManager.shared.convert(amount: 1, from: currencyCode, to: wallet.currencyCode)
    }

    private var canSave: Bool {
        selectedWallet != nil && totalMinor > 0 && !isSaving
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                handoffSection
                summarySection
                warningSection
                walletSection
                detailSection
                rateSection
                entriesSection
            }
            .listStyle(.insetGrouped)
            // The backdrop has to reach the toolbar, so it goes behind the whole
            // scroll view — which means hiding the list's own background and
            // putting the grouped colour back underneath it.
            .scrollContentBackground(.hidden)
            .background(alignment: .top) {
                AppHandoffBackdrop()
                    .frame(height: backdropHeight)
                    .ignoresSafeArea(edges: .top)
            }
            .background {
                Color(.systemGroupedBackground).ignoresSafeArea()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("split.receivedTitle".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if transactionCount > 1 { showConfirm = true } else { commit() }
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L10n.Common.save).fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .overlay {
                if sourceWallets.isEmpty {
                    ContentUnavailableView {
                        Label("transaction.setup.wallet.title".localized, systemImage: "wallet.pass")
                    } description: {
                        Text("transaction.setup.wallet.message".localized)
                    } actions: {
                        Button("wallet.add".localized) { showAddWallet = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .task { prepareIfNeeded() }
            .sheet(isPresented: $showAddWallet, onDismiss: autoSelectNewWalletIfNeeded) {
                AddWalletView(viewModel: AddWalletViewModel(dataService: SwiftDataService(modelContext: modelContext)))
            }
            .sheet(isPresented: $showAllWallets) {
                TransactionWalletPickerSheet(
                    wallets: sourceWallets,
                    selectedWalletID: selectedWallet?.id,
                    onSelect: { wallet in
                        selectedWallet = wallet
                        showAllWallets = false
                        HapticManager.shared.selection()
                    },
                    onDismiss: { showAllWallets = false }
                )
            }
            .sheet(item: $categoryPickerTarget) { target in
                TransactionCategoryPickerSheet(
                    allCategories: expenseCategories,
                    rankedSuggestions: [],
                    selectedCategoryID: selectedCategoryID(for: target),
                    transactionType: .expense,
                    onSelect: { category in
                        apply(category, to: target)
                        categoryPickerTarget = nil
                    },
                    onDismiss: { categoryPickerTarget = nil }
                )
            }
            .confirmationDialog(
                "split.import.confirmTitle".localized(with: transactionCount),
                isPresented: $showConfirm,
                titleVisibility: .visible
            ) {
                Button("split.import.confirmAction".localized) { commit() }
                Button(L10n.Common.cancel, role: .cancel) {}
            } message: {
                Text("split.import.confirmMessage".localized(
                    with: totalAmount.formattedAmount(for: currencyCode),
                    selectedWallet?.name ?? ""
                ))
            }
            .alert(L10n.Common.error, isPresented: .constant(errorMessage != nil)) {
                Button(L10n.Common.ok) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Handoff header

    /// Sits outside the grouped cards so the two icons read as artwork rather
    /// than as another settings row.
    private var handoffSection: some View {
        Section {
            AppHandoffVisual(role: .destination)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }

    // MARK: - Summary

    /// The amount, its currency and its provenance in a single row.
    ///
    /// This replaced a 40pt hero. The number still leads, but at a size that
    /// leaves the screen's real work — choosing a wallet, checking the
    /// categories — above the fold instead of below it. Identical in shape to
    /// MitraTrip's summary so the figure you approved there is recognisably the
    /// same figure here.
    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("split.import.shareLabel".localized)
                        .appFont(.caption2, weight: .semibold)
                        .tracking(0.5)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Text(currencyCode)
                        .appFont(.caption2, weight: .medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }

                Text(totalAmount.formattedAmount(for: currencyCode))
                    .appFont(.title, weight: .bold)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: totalMinor)

                Text(metadataLine)
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
    }

    /// Trip name plus what the figure above is made of. `source.app` is a claim
    /// made by the sender, not a verified fact, so the trip name is described
    /// neutrally and never rendered as a trust badge.
    private var metadataLine: String {
        var parts: [String] = []
        if let source = payload.source, !source.tripName.isEmpty {
            parts.append(source.tripName)
        }
        parts.append(compositionText)
        return parts.joined(separator: " · ")
    }

    private var compositionText: String {
        if isDetailed {
            return "split.import.entrySummary".localized(with: includedEntries.count, entries.count)
        }
        if payload.isCustomSplit {
            return "split.customSplitInfo".localized(with: payload.originalAmount.formattedAmount(for: currencyCode))
        }
        if payload.splitCount <= 1 || payload.splitAmount == payload.originalAmount {
            return "split.fullAmountInfo".localized(with: payload.originalAmount.formattedAmount(for: currencyCode))
        }
        return "split.originalBillInfo".localized(with: payload.originalAmount.formattedAmount(for: currencyCode), payload.splitCount)
    }

    // MARK: - Warnings

    /// Duplicates lead: that warning has already acted on the user's behalf by
    /// pre-excluding rows, so it is the one they must read to understand why the
    /// total is lower than the link promised.
    @ViewBuilder
    private var warningSection: some View {
        let hasDuplicates = !duplicateEntryIDs.isEmpty
        if payload.isStale || hasDuplicates {
            Section {
                if hasDuplicates {
                    warningRow(
                        systemImage: "exclamationmark.triangle.fill",
                        text: "split.import.duplicateWarning".localized(with: duplicateEntryIDs.count)
                    )
                }
                if payload.isStale {
                    warningRow(
                        systemImage: "clock.badge.exclamationmark",
                        text: "split.import.staleWarning".localized
                    )
                }
            }
        }
    }

    /// A tinted row rather than a grey `Label`.
    ///
    /// The previous version rendered as an ordinary list row and read as
    /// incidental detail — a caution about money that may already be in the
    /// ledger has to survive being scrolled past. The tint rides on
    /// `listRowBackground`, which the grouped list clips to its own shape, so
    /// there is no shape in this source to keep in sync.
    private func warningRow(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .appFont(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(text)
                .appFont(.footnote, weight: .medium)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.orange.opacity(0.14))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Wallet

    @ViewBuilder
    private var walletSection: some View {
        if !sourceWallets.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(frequentWallets) { wallet in
                            WalletChip(wallet: wallet, isSelected: selectedWallet?.id == wallet.id) {
                                selectedWallet = wallet
                                HapticManager.shared.selection()
                            }
                        }
                        if sourceWallets.count > maxQuickWallets {
                            Button("common.more".localized) { showAllWallets = true }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            } header: {
                // No footer: the header already says "Save to Wallet", and the
                // chips below it are self-evidently the choice.
                Text("split.selectWallet".localized)
            }
        }
    }

    private var frequentWallets: [Wallet] {
        let ordered = (scoredWallets.isEmpty ? sourceWallets : scoredWallets.map(\.wallet))
            .filter { wallet in sourceWallets.contains { $0.id == wallet.id } }
        return Array(ordered.prefix(maxQuickWallets))
    }

    // MARK: - Details

    /// Consolidated imports only.
    ///
    /// In Itemized mode every field here was either dead or duplicated: `commit`
    /// takes the date from `entry.date` and the category from
    /// `category(for: entry)`, so the pickers moved nothing, and the trip name
    /// they described is already in the summary above. A control that appears
    /// editable but changes nothing is worse than an absent one, so the whole
    /// section is gone in that mode. For a consolidated import these are the only
    /// place the single transaction's category, date and note can be set.
    @ViewBuilder
    private var detailSection: some View {
        if !isDetailed {
            Section("common.details".localized) {
                categoryRow

                DatePicker("split.date".localized, selection: $date, displayedComponents: [.date, .hourAndMinute])

                LabeledContent("split.note".localized) {
                    TextField("split.note".localized, text: $note, axis: .vertical)
                        .lineLimit(1...3)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.sentences)
                }

                if let location = payload.location {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.primaryTitle).appFont(.body)
                            if let secondary = location.secondaryTitle {
                                Text(secondary).appFont(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "mappin.and.ellipse").foregroundStyle(.red)
                    }
                }
            }
        }
    }

    /// A disclosure row, not a bare label.
    ///
    /// The category is the field most likely to need changing, and the previous
    /// version gave no sign it could be: a right-aligned grey string reads as a
    /// read-only value everywhere else in iOS. The category's own icon plus a
    /// trailing chevron is the same affordance the rest of the app uses for a
    /// row that opens a picker.
    private var categoryRow: some View {
        Button {
            categoryPickerTarget = .consolidated
        } label: {
            HStack(spacing: 12) {
                Text("split.category".localized)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if let category = selectedCategory {
                    Image(systemName: category.icon)
                        .appFont(.caption)
                        .foregroundStyle(Color(hex: category.colorHex) ?? .gray)
                    Text(category.displayName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("common.none".localized)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .appFont(.caption2, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("split.import.changeCategoryHint".localized)
    }

    // MARK: - Exchange rate

    @ViewBuilder
    private var rateSection: some View {
        if isCrossCurrency, let wallet = selectedWallet {
            let converted = totalAmount * effectiveRate
            Section {
                LabeledContent("split.import.rate".localized) {
                    TextField(
                        rateePlaceholder(wallet: wallet),
                        text: $rateText
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                }
                LabeledContent("split.walletEquivalentLabel".localized) {
                    Text(converted.formattedAmount(for: wallet.currencyCode))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("split.import.rate".localized)
            } footer: {
                Text("split.import.rateFooter".localized(with: currencyCode, wallet.currencyCode))
                    .sectionFooter()
            }
        }
    }

    private func rateePlaceholder(wallet: Wallet) -> String {
        let live = CurrencyManager.shared.convert(amount: 1, from: currencyCode, to: wallet.currencyCode)
        return NSDecimalNumber(decimal: live).stringValue
    }

    // MARK: - Entries (Detailed mode)

    @ViewBuilder
    private var entriesSection: some View {
        if isDetailed {
            Section {
                ForEach(entries) { entry in
                    entryRow(entry)
                }
            } header: {
                HStack {
                    Text("split.import.entries".localized)
                    Spacer()
                    Button(excludedEntryIDs.isEmpty ? "split.import.excludeAll".localized
                                                    : "split.import.includeAll".localized) {
                        withAnimation {
                            excludedEntryIDs = excludedEntryIDs.isEmpty
                                ? Set(entries.map(\.sourceId))
                                : []
                        }
                    }
                    .appFont(.footnote)
                    .textCase(nil)
                }
            } footer: {
                Text("split.import.entriesFooter".localized)
                    .sectionFooter()
            }
        }
    }

    /// `TransactionRowView`'s anatomy — category icon, category name, note
    /// beneath, amount over date on the trailing edge — so a row here looks like
    /// the transaction it becomes. The leading circle includes or excludes it;
    /// the chevron after the category name marks the row as tappable to
    /// recategorise, which nothing in the previous version did.
    private func entryRow(_ entry: SharedExpenseEntry) -> some View {
        let isIncluded = !excludedEntryIDs.contains(entry.sourceId)
        let category = category(for: entry)
        let isDuplicate = duplicateEntryIDs.contains(entry.sourceId)
        let tint = category.flatMap { Color(hex: $0.colorHex) } ?? .gray

        return HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) { toggle(entry) }
                HapticManager.shared.selection()
            } label: {
                Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                    .appFont(.title3)
                    .foregroundStyle(isIncluded ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isIncluded ? "split.import.included".localized : "split.import.excluded".localized)

            ZStack {
                Circle()
                    .fill(tint.opacity(0.1))
                    .frame(width: 34, height: 34)

                Image(systemName: category?.icon ?? "questionmark")
                    .appFont(.subheadline)
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(category?.displayName ?? "common.none".localized)
                        .appFont(.subheadline, weight: .medium)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Image(systemName: "chevron.down")
                        .appFont(.caption2, weight: .semibold)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 4) {
                    if isDuplicate {
                        Text("split.import.duplicateBadge".localized)
                            .appFont(.caption2, weight: .medium)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }

                    Text(entry.title.isEmpty ? "split.title".localized : entry.title)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(MoneyMinorUnitConverter.fromMinorUnits(entry.amountMinor, currencyCode: currencyCode)
                        .formattedAmount(for: currencyCode))
                    .appFont(.subheadline, weight: .semibold)
                    .monospacedDigit()
                    .lineLimit(1)

                Text(entry.date.appFormatted(date: .abbreviated, time: .omitted))
                    .appFont(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .opacity(isIncluded ? 1 : 0.45)
        .contentShape(Rectangle())
        .onTapGesture { categoryPickerTarget = .entry(entry.sourceId) }
        .accessibilityHint("split.import.changeCategoryHint".localized)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(isIncluded ? "split.import.exclude".localized : "split.import.include".localized) {
                withAnimation(.snappy) { toggle(entry) }
            }
            .tint(isIncluded ? .orange : .accentColor)
        }
    }

    private func toggle(_ entry: SharedExpenseEntry) {
        if excludedEntryIDs.contains(entry.sourceId) {
            excludedEntryIDs.remove(entry.sourceId)
        } else {
            excludedEntryIDs.insert(entry.sourceId)
        }
    }

    // MARK: - Category resolution

    private func category(for entry: SharedExpenseEntry) -> Category? {
        if let overrideID = entryCategoryOverrides[entry.sourceId] {
            return expenseCategories.first { $0.id == overrideID }
        }
        return SplitExpenseService.resolveCategory(key: entry.categoryKey, name: nil, in: modelContext)
    }

    private func selectedCategoryID(for target: CategoryPickerTarget) -> UUID? {
        switch target {
        case .consolidated: selectedCategory?.id
        case .entry(let sourceID):
            entryCategoryOverrides[sourceID]
                ?? entries.first { $0.sourceId == sourceID }.flatMap { category(for: $0)?.id }
        }
    }

    private func apply(_ category: Category, to target: CategoryPickerTarget) {
        switch target {
        case .consolidated: selectedCategory = category
        case .entry(let sourceID): entryCategoryOverrides[sourceID] = category.id
        }
    }

    // MARK: - Preparation

    private func prepareIfNeeded() {
        guard !didPrepare else { return }
        didPrepare = true

        date = payload.date
        note = defaultNote
        selectedCategory = SplitExpenseService.resolveCategory(for: payload, in: modelContext)

        if selectedWallet == nil {
            if let matching = sourceWallets.first(where: {
                $0.currencyCode.caseInsensitiveCompare(currencyCode) == .orderedSame
            }) {
                autoSelectedWalletID = matching.id
                selectedWallet = matching
            } else if let first = sourceWallets.first {
                autoSelectedWalletID = first.id
                selectedWallet = first
            }
        }

        flagDuplicates()
        recomputeSuggestions()
    }

    private var defaultNote: String {
        if let source = payload.source, !source.tripName.isEmpty {
            return "split.importedNote".localized(with: source.tripName)
        }
        if let raw = payload.note, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "split.importedNote".localized(with: raw)
        }
        return "split.importedDefaultNote".localized
    }

    /// Flags rows that look already-imported and **pre-excludes** them. A warning
    /// the user must actively override beats one they can scroll past.
    private func flagDuplicates() {
        let candidates: [SharedExpenseImportGuard.Candidate]
        if isDetailed {
            candidates = entries.map {
                .init(
                    amount: MoneyMinorUnitConverter.fromMinorUnits($0.amountMinor, currencyCode: currencyCode),
                    currencyCode: currencyCode,
                    date: $0.date,
                    searchHint: $0.title
                )
            }
        } else {
            candidates = [.init(amount: totalAmount, currencyCode: currencyCode, date: payload.date, searchHint: payload.note)]
        }

        let flagged = SharedExpenseImportGuard.likelyDuplicateIndices(among: candidates, in: modelContext)
        guard !flagged.isEmpty else { return }

        if isDetailed {
            let ids = flagged.compactMap { index in entries.indices.contains(index) ? entries[index].sourceId : nil }
            duplicateEntryIDs = Set(ids)
            excludedEntryIDs.formUnion(ids)
        } else {
            duplicateEntryIDs = ["consolidated"]
        }
    }

    // MARK: - Suggestions

    private func recomputeSuggestions() {
        let location = payload.location.map {
            SuggestionLocationContext(
                applePlaceID: nil,
                spatialKey: TransactionLocation.spatialKey(latitude: $0.latitude, longitude: $0.longitude)
            )
        }
        let container = modelContext.container
        let walletID = selectedWallet?.id
        let categoryID = selectedCategory?.id

        suggestionTask?.cancel()
        suggestionTask = Task {
            let snapshot = await TransactionSuggestionEngine.computeSuggestions(
                container: container,
                type: .expense,
                selectedWalletID: walletID,
                selectedCategoryID: categoryID,
                location: location
            )
            guard !Task.isCancelled else { return }
            applySuggestions(snapshot)
        }
    }

    private func applySuggestions(_ snapshot: SuggestionSnapshot) {
        let byID = Dictionary(sourceWallets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        scoredWallets = snapshot.wallets.compactMap { ranked in
            byID[ranked.id].map { ScoredWallet(wallet: $0, score: ranked.score, lastUsed: ranked.lastUsed) }
        }
        // Upgrade the provisional pick to the top suggestion only while the user
        // hasn't chosen one themselves.
        if let current = selectedWallet,
           current.id == autoSelectedWalletID,
           let top = scoredWallets.first?.wallet,
           top.id != current.id {
            autoSelectedWalletID = top.id
            selectedWallet = top
        }
    }

    private func autoSelectNewWalletIfNeeded() {
        guard selectedWallet == nil, let wallet = sourceWallets.first else { return }
        selectedWallet = wallet
        recomputeSuggestions()
    }

    // MARK: - Commit

    private func commit() {
        guard let wallet = selectedWallet else { return }
        isSaving = true

        let rate = effectiveRate
        var inserted: [Transaction] = []

        do {
            if isDetailed {
                guard !includedEntries.isEmpty else {
                    isSaving = false
                    errorMessage = "split.import.noneSelected".localized
                    return
                }
                for entry in includedEntries {
                    let amount = MoneyMinorUnitConverter.fromMinorUnits(entry.amountMinor, currencyCode: currencyCode)
                    let title = entry.title.isEmpty ? note : entry.title
                    let transaction = try makeTransaction(
                        amount: amount,
                        date: entry.date,
                        note: noteText(for: title),
                        category: category(for: entry),
                        wallet: wallet,
                        rate: rate
                    )
                    inserted.append(transaction)
                }
            } else {
                let transaction = try makeTransaction(
                    amount: totalAmount,
                    date: date,
                    note: note,
                    category: selectedCategory,
                    wallet: wallet,
                    rate: rate
                )
                inserted.append(transaction)
            }
        } catch {
            isSaving = false
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }

        // Every transaction validated before anything was inserted, so a partial
        // import can't reach the store.
        for transaction in inserted { modelContext.insert(transaction) }

        do {
            try modelContext.save()
            wallet.invalidateBalanceCache()
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            HapticManager.shared.notification(type: .success)
            dismiss()
        } catch {
            isSaving = false
            ErrorService.shared.handlePersistenceError(error, context: "ImportSharedExpenseView.commit")
        }
    }

    private func noteText(for title: String) -> String {
        guard let source = payload.source, !source.tripName.isEmpty else { return title }
        return "\(title) · \(source.tripName)"
    }

    /// Builds and **validates** a transaction without inserting it.
    ///
    /// `Transaction.validate()` and `WalletLedgerRules.validate(transaction:)`
    /// both run here. The previous implementation called neither, so a payload
    /// with a non-positive amount reached `insert` + `save` and corrupted the
    /// wallet balance — `EventLedgerService` validates on the analogous internal
    /// export path, and this path is fed by an unauthenticated URL.
    private func makeTransaction(
        amount: Decimal,
        date: Date,
        note: String,
        category: Category?,
        wallet: Wallet,
        rate: Decimal
    ) throws -> Transaction {
        let transaction = Transaction(
            amount: amount,
            currencyCode: currencyCode,
            date: date,
            type: .expense
        )
        transaction.category = category
        transaction.note = note
        transaction.tags = TransactionTagParser.tags(in: note)
        transaction.sourceWallet = wallet
        transaction.exchangeRate = rate
        transaction.storedRate = rate
        transaction.updatedAt = Date()
        transaction.needsSync = true

        if let loc = payload.location {
            transaction.location = TransactionLocation(
                displayName: loc.displayName,
                fullAddress: loc.fullAddress,
                shortAddress: loc.shortAddress,
                latitude: loc.latitude,
                longitude: loc.longitude,
                source: .manual,
                locality: loc.locality,
                administrativeArea: loc.administrativeArea,
                countryCode: loc.countryCode
            )
        }

        let errors = transaction.validate()
        if let first = errors.first { throw first }
        try WalletLedgerRules.validate(transaction: transaction)
        return transaction
    }
}
