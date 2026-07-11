import SwiftUI
import SwiftData

struct AddDebtView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: DebtFormViewModel
    @State private var showKeyboard: Bool
    @FocusState private var isNameFocused: Bool

    @Query(filter: #Predicate<Wallet> { !$0.isArchived && $0.deletedAt == nil }, sort: \Wallet.name) private var wallets: [Wallet]

    init(debtToEdit: Debt? = nil) {
        let vm = DebtFormViewModel(debt: debtToEdit)
        _viewModel = State(wrappedValue: vm)
        // New entries open straight into the keypad; edits start collapsed.
        _showKeyboard = State(initialValue: debtToEdit == nil)
    }

    private var accentColor: Color { viewModel.type.accentColor }

    private var amountEditable: Bool {
        !viewModel.isEditing || viewModel.canEditAmount
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                    .onTapGesture { collapseKeyboard() }

                List {
                    // MARK: Amount
                    Section(footer: amountFooter) {
                        AmountDisplayView(
                            amount: viewModel.evaluatedAmount,
                            currencyCode: $viewModel.currencyCode,
                            expression: viewModel.expression,
                            isEditing: showKeyboard && amountEditable,
                            showsCurrencyPicker: !viewModel.isEditing,
                            onTap: {
                                guard amountEditable else { return }
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showKeyboard = true
                                    isNameFocused = false
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(accentColor.opacity(0.15))
                    }

                    // MARK: Person
                    Section("debt.who".localized) {
                        TextField(L10n.Debt.personName, text: $viewModel.personName)
                            .appFont(.body)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                    }

                    // MARK: Wallet (creation only)
                    if !viewModel.isEditing {
                        Section {
                            DebtWalletChips(wallets: wallets, selectedWallet: $viewModel.selectedWallet, allowNone: false)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        } header: {
                            Text(viewModel.type == .iOwe ? "debt.toWallet".localized : "debt.fromWallet".localized)
                        } footer: {
                            walletFooter
                        }
                    }

                    // MARK: Date & due date
                    Section {
                        DatePicker(L10n.Transaction.date, selection: $viewModel.date, displayedComponents: .date)
                            .appFont(.body)
                        DatePicker(L10n.TransactionAdditional.time, selection: $viewModel.date, displayedComponents: .hourAndMinute)
                            .appFont(.body)

                        Toggle("debt.setDueDate".localized, isOn: $viewModel.hasDueDate.animation())
                            .appFont(.body)
                        if viewModel.hasDueDate {
                            DatePicker(L10n.Debt.dueDate, selection: $viewModel.dueDate, displayedComponents: .date)
                                .appFont(.body)
                        }
                    }

                    // MARK: Note
                    Section(L10n.Transaction.note) {
                        TextField(L10n.Transaction.note, text: $viewModel.note, axis: .vertical)
                            .appFont(.body)
                            .lineLimit(1...4)
                            .focused($isNameFocused)
                    }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(.compact)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(viewModel.isEditing ? L10n.Common.edit : L10n.Debt.add)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if showKeyboard && amountEditable && !isNameFocused {
                    CalculatorKeyboardView(
                        expression: $viewModel.expression,
                        evaluatedAmount: $viewModel.evaluatedAmount,
                        onDismiss: { collapseKeyboard() }
                    )
                    .transition(.move(edge: .bottom))
                    .background(Color(.systemGroupedBackground))
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isEditing {
                        typeBadge
                    } else {
                        typeSelector
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if viewModel.save(context: modelContext) {
                            HapticManager.shared.notification(type: .success)
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.isValid || viewModel.isSaving)
                }
            }
            .onChange(of: isNameFocused) { _, focused in
                if focused {
                    withAnimation(.easeInOut(duration: 0.2)) { showKeyboard = false }
                }
            }
            .onAppear {
                // A wallet is required (no track-only) — default to one in the
                // debt's currency, else the first available.
                if !viewModel.isEditing && viewModel.selectedWallet == nil {
                    viewModel.selectedWallet = wallets.first(where: { $0.currencyCode == viewModel.currencyCode }) ?? wallets.first
                }
            }
            .alert(L10n.Common.error, isPresented: $viewModel.showError) {
                Button(L10n.Common.ok, role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "common.errorOccurred".localized)
            }
        }
    }

    // MARK: - Type selector

    private var typeSelector: some View {
        Picker("common.type".localized, selection: $viewModel.type) {
            Text(L10n.Debt.owedToMe).tag(DebtType.owedToMe)
            Text(L10n.Debt.iOwe).tag(DebtType.iOwe)
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
    }

    private var typeBadge: some View {
        Text(viewModel.type.localizedTitle)
            .appFont(.subheadline, weight: .semibold)
            .foregroundStyle(accentColor)
    }

    // MARK: - Footers

    @ViewBuilder
    private var amountFooter: some View {
        if viewModel.isEditing && !viewModel.canEditAmount {
            Label("debt.editAmountLocked".localized, systemImage: "lock.fill")
                .appFont(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var walletFooter: some View {
        let amountStr = (viewModel.amount ?? 0).formattedAmount(for: viewModel.currencyCode)
        if let wallet = viewModel.selectedWallet {
            Text(viewModel.type == .iOwe
                 ? "debt.lendAddsToWallet".localized(with: amountStr, wallet.name)
                 : "debt.lendDeductsFromWallet".localized(with: amountStr, wallet.name))
                .appFont(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text("debt.willRecordOnly".localized)
                .appFont(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func collapseKeyboard() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showKeyboard = false
            isNameFocused = false
        }
    }
}
