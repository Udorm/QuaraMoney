import SwiftUI
import SwiftData

/// Dedicated read-only preview screen for receiving and accepting a shared expense.
/// Preserves the sender's currency, amount, date, category, and location.
/// Features a clean hero amount card with non-truncating explanation footer,
/// the Compact Add Transaction wallet chip selector with suggestion engine auto-selection,
/// and native Apple inset grouped detail rows.
struct ImportSharedExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let payload: SharedExpensePayload

    @Query(
        filter: #Predicate<Wallet> { !$0.isArchived && $0.deletedAt == nil },
        sort: \Wallet.name
    ) private var wallets: [Wallet]

    @State private var selectedWallet: Wallet?
    @State private var isSaving: Bool = false
    @State private var showNoWalletAlert: Bool = false
    @State private var showAllWallets: Bool = false
    @State private var showAddWallet: Bool = false

    // Suggestion engine state
    @State private var scoredWallets: [ScoredWallet] = []
    @State private var suggestionTask: Task<Void, Never>?
    @State private var autoSelectedWalletID: UUID?

    private let maxQuickWallets = 4

    /// Excludes savings goals / savings wallets that cannot receive direct expense transactions.
    private var sourceWallets: [Wallet] {
        wallets.filter { !$0.isSavings }
    }

    private var resolvedCategory: Category? {
        SplitExpenseService.resolveCategory(for: payload, in: modelContext)
    }

    private var effectiveNote: String {
        if let raw = payload.note, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "split.importedNote".localized(with: raw)
        }
        return "split.importedDefaultNote".localized
    }

    /// Contextually-ranked wallets for the horizontal quick chip rail, mirroring CompactAddTransactionView.
    private var frequentWallets: [Wallet] {
        let ordered = (scoredWallets.isEmpty ? sourceWallets : scoredWallets.map(\.wallet))
            .filter { wallet in sourceWallets.contains { $0.id == wallet.id } }
        return Array(ordered.prefix(maxQuickWallets))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Amount Card & Explanation Footer
                    amountHeroCard

                    // MARK: - Wallet Selection Section (CompactAddTransactionView Chip Rail)
                    walletSection

                    // MARK: - Native Apple Detail Rows
                    detailSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("split.receivedTitle".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.Common.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        acceptAndSave()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || sourceWallets.isEmpty)
                    .accessibilityLabel(L10n.Common.save)
                }
            }
            .onAppear {
                initialWalletPreselection()
            }
            .alert(L10n.Common.error, isPresented: $showNoWalletAlert) {
                Button(L10n.Common.ok, role: .cancel) { }
            } message: {
                Text("wallet.emptyState".localized)
            }
        }
    }

    // MARK: - Amount Hero Card & Footer Explanation
    private var amountHeroCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            let shape = RoundedRectangle(cornerRadius: CornerRadius.hero, style: .continuous)
            let typeTint = ThemeManager.shared.expenseColor

            let cardContent = VStack(alignment: .center, spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    Text(String.currencySymbol(for: payload.currencyCode))
                        .appFont(size: 28, weight: .semibold)
                        .foregroundStyle(Color.secondary)

                    Text(formatAmountValue(payload.splitAmount, currencyCode: payload.currencyCode))
                        .appFont(size: 44, weight: .bold)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .foregroundStyle(Color.primary)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)

            Group {
                if reduceTransparency {
                    cardContent
                        .background(typeTint.opacity(0.15), in: shape)
                } else if #available(iOS 26.0, *) {
                    cardContent
                        .glassEffect(.regular.tint(typeTint.opacity(0.18)), in: shape)
                } else {
                    cardContent
                        .background(Color(.secondarySystemGroupedBackground), in: shape)
                }
            }
            .clipShape(shape)
            .contentShape(shape)

            // Native Apple form footer explanation text under the card (no truncation)
            VStack(alignment: .leading, spacing: 3) {
                Text("split.receivedSubtitle".localized)
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if payload.isCustomSplit {
                    Text(String(format: "split.customSplitInfo".localized, payload.originalAmount.formattedAmount(for: payload.currencyCode)))
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if payload.splitCount <= 1 || payload.splitAmount == payload.originalAmount {
                    Text(String(format: "split.fullAmountInfo".localized, payload.originalAmount.formattedAmount(for: payload.currencyCode)))
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(format: "split.originalBillInfo".localized, payload.originalAmount.formattedAmount(for: payload.currencyCode), payload.splitCount))
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
        }
    }

    private func formatAmountValue(_ value: Decimal, currencyCode: String) -> String {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        if currencyCode.uppercased() == "KHR" {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: doubleValue)) ?? "\(value)"
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            return formatter.string(from: NSNumber(value: doubleValue)) ?? "\(value)"
        }
    }

    // MARK: - Wallet Section (Matching CompactAddTransactionView)
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
                    showAddWallet = true
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
                .sheet(isPresented: $showAddWallet, onDismiss: autoSelectNewWalletIfNeeded) {
                    AddWalletView(viewModel: AddWalletViewModel(dataService: SwiftDataService(modelContext: modelContext)))
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(frequentWallets) { wallet in
                            WalletChip(
                                wallet: wallet,
                                isSelected: selectedWallet?.id == wallet.id
                            ) {
                                selectedWallet = wallet
                                HapticManager.shared.selection()
                            }
                        }

                        if sourceWallets.count > maxQuickWallets {
                            moreChip { showAllWallets = true }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .chipRail()
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
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .appFont(.footnote, weight: .medium)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 16)
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

    // MARK: - Detail Section (Native Apple Inset Grouped Rows)
    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("common.details".localized)

            VStack(spacing: 0) {
                // Category
                if let category = resolvedCategory {
                    let iconColor = Color(hex: category.colorHex) ?? .orange
                    let iconName = category.icon.isEmpty ? "fork.knife" : category.icon
                    detailRow(
                        icon: iconName,
                        iconColor: iconColor,
                        title: "split.category".localized,
                        value: category.displayName
                    )
                    Divider().padding(.leading, 56)
                }

                // Date & Time
                detailRow(
                    icon: "calendar",
                    iconColor: .blue,
                    title: "split.date".localized,
                    value: payload.date.appFormatted(date: .abbreviated, time: .shortened)
                )

                // Location (if present)
                if let loc = payload.location {
                    Divider().padding(.leading, 56)
                    detailLocationRow(loc: loc)
                }

                // Note
                Divider().padding(.leading, 56)
                detailRow(
                    icon: "note.text",
                    iconColor: .purple,
                    title: "split.note".localized,
                    value: effectiveNote
                )
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
        }
    }

    private func detailRow(
        icon: String,
        iconColor: Color,
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .appFont(.body)
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .appFont(.body, weight: .medium)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func detailLocationRow(loc: SharedExpenseLocation) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "mappin.and.ellipse")
                    .appFont(.body)
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("split.location".localized)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                Text(loc.primaryTitle)
                    .appFont(.body, weight: .medium)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let secondary = loc.secondaryTitle {
                    Text(secondary)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Suggestion Engine & Preselection
    private func scoringLocation() -> SuggestionLocationContext? {
        if let loc = payload.location {
            return SuggestionLocationContext(
                applePlaceID: nil,
                spatialKey: TransactionLocation.spatialKey(
                    latitude: loc.latitude,
                    longitude: loc.longitude
                )
            )
        }
        return nil
    }

    private func initialWalletPreselection() {
        if selectedWallet == nil {
            // Provisional preselection: first try currency-matching wallet, then first available
            if let matching = sourceWallets.first(where: { $0.currencyCode.uppercased() == payload.currencyCode.uppercased() }) {
                autoSelectedWalletID = matching.id
                selectedWallet = matching
            } else if let firstWallet = sourceWallets.first {
                autoSelectedWalletID = firstWallet.id
                selectedWallet = firstWallet
            }
        }

        recomputeSuggestions()
    }

    private func recomputeSuggestions() {
        let location = scoringLocation()
        let categoryID = resolvedCategory?.id
        let container = modelContext.container
        let initialWalletID = selectedWallet?.id

        suggestionTask?.cancel()
        suggestionTask = Task {
            let snapshot = await TransactionSuggestionEngine.computeSuggestions(
                container: container,
                type: .expense,
                selectedWalletID: initialWalletID,
                selectedCategoryID: categoryID,
                location: location
            )
            guard !Task.isCancelled else { return }
            applySuggestions(snapshot)
        }
    }

    private func applySuggestions(_ snapshot: SuggestionSnapshot) {
        let walletsByID = Dictionary(sourceWallets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        scoredWallets = snapshot.wallets.compactMap { ranked in
            walletsByID[ranked.id].map {
                ScoredWallet(wallet: $0, score: ranked.score, lastUsed: ranked.lastUsed)
            }
        }

        // Upgrade provisional preselection to top suggestion if user hasn't manually picked another wallet
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

    // MARK: - Accept & Save Action
    private func acceptAndSave() {
        guard let wallet = selectedWallet else {
            showNoWalletAlert = true
            return
        }

        isSaving = true

        let transaction = Transaction(
            amount: payload.splitAmount,
            currencyCode: payload.currencyCode,
            date: payload.date,
            type: .expense
        )

        transaction.category = resolvedCategory
        transaction.note = effectiveNote
        transaction.tags = TransactionTagParser.tags(in: effectiveNote)
        transaction.sourceWallet = wallet

        // Authoritative exchange rate relative to chosen wallet
        let rate: Decimal
        if payload.currencyCode.uppercased() == wallet.currencyCode.uppercased() {
            rate = 1.0
        } else {
            rate = CurrencyManager.shared.convert(
                amount: 1.0,
                from: payload.currencyCode,
                to: wallet.currencyCode
            )
        }
        transaction.exchangeRate = rate
        transaction.storedRate = rate

        // Location transfer
        if let loc = payload.location {
            let persistentLocation = TransactionLocation(
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
            transaction.location = persistentLocation
        }

        transaction.updatedAt = Date()
        transaction.needsSync = true

        modelContext.insert(transaction)

        do {
            try modelContext.save()
            wallet.invalidateBalanceCache()
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            HapticManager.shared.notification(type: .success)
            dismiss()
        } catch {
            isSaving = false
            ErrorService.shared.handlePersistenceError(error, context: "ImportSharedExpenseView.acceptAndSave")
        }
    }
}
