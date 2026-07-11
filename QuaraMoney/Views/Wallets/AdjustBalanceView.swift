import SwiftUI

struct AdjustBalanceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AdjustBalanceViewModel

    /// Calculator keyboard visibility (shown by default, like the expense screen).
    @State private var showKeyboard = true
    /// Whether the date/time/exclude "Details" disclosure is expanded.
    @State private var showOptions = false
    @FocusState private var isNoteFocused: Bool

    init(wallet: Wallet, dataService: DataService) {
        _viewModel = State(wrappedValue: AdjustBalanceViewModel(wallet: wallet, dataService: dataService))
    }

    private var walletColor: Color {
        Color(hex: viewModel.wallet.colorHex) ?? .blue
    }

    /// Green when the balance goes up, red when it goes down, neutral while the
    /// field is empty or the target matches the current balance.
    private var directionColor: Color {
        guard viewModel.isValid else { return .secondary }
        return viewModel.difference > 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    /// The value shown in the "New Balance" column: the typed target once there
    /// is input, otherwise the current balance (so an empty field reads as "no change").
    private var previewNewBalance: Decimal {
        viewModel.hasInput ? viewModel.targetBalance : viewModel.currentBalance
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Amount input + note (grouped together)
                Section {
                    AmountDisplayView(
                        amount: viewModel.evaluatedAmount,
                        currencyCode: .constant(viewModel.wallet.currencyCode),
                        expression: viewModel.expression,
                        isEditing: showKeyboard,
                        showsCurrencyPicker: false,
                        showsCurrencyHeader: false,
                        showsCalculationPreview: false,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showKeyboard = true
                                isNoteFocused = false
                            }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    // Tinted only for a valid change; otherwise the default,
                    // theme-adaptive row color.
                    .listRowBackground(
                        viewModel.isValid
                            ? AnyView(directionColor.opacity(0.12))
                            : AnyView(Color(.secondarySystemGroupedBackground))
                    )

                    // Note sits right beneath the amount so it reads as part of
                    // the same entry, not a detached field at the bottom.
                    HStack(spacing: 10) {
                        Image(systemName: "note.text")
                            .font(.app(.footnote, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        TextField("transaction.noteOptional".localized, text: $viewModel.note)
                            .focused($isNoteFocused)
                            .submitLabel(.done)
                            .font(.app(.subheadline))
                    }
                    .listRowSeparator(.hidden)
                }

                // MARK: - Preview: current  →  new
                Section {
                    balancePreview
                        .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                }

                // MARK: - Details (date / time / exclude) — hidden until requested
                Section {
                    DisclosureGroup(isExpanded: $showOptions) {
                        DatePicker(
                            "transaction.date".localized,
                            selection: $viewModel.date,
                            displayedComponents: [.date, .hourAndMinute]
                        )

                        Toggle("transaction.excludeFromReports".localized, isOn: $viewModel.excludeFromReports)
                    } label: {
                        Label("common.details".localized, systemImage: "slider.horizontal.3")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("wallet.adjustBalance".localized)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if showKeyboard && !isNoteFocused {
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        viewModel.save()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.isValid)
                    .accessibilityLabel(L10n.Common.save)
                }
            }
            .onChange(of: isNoteFocused) { _, focused in
                // Typing a note swaps the calculator for the system keyboard.
                if focused {
                    withAnimation(.easeInOut(duration: 0.2)) { showKeyboard = false }
                }
            }
            .onChange(of: showOptions) { _, expanded in
                // Reveal the pickers by clearing the calculator out of the way.
                if expanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showKeyboard = false
                        isNoteFocused = false
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Balance preview (current → new)

    private var balancePreview: some View {
        HStack(spacing: 8) {
            balanceColumn(
                label: "wallet.currentBalance".localized,
                value: viewModel.currentBalance,
                tint: .secondary
            )

            ZStack {
                Circle()
                    .fill(directionColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: "arrow.right")
                    .font(.app(.footnote, weight: .bold))
                    .foregroundStyle(directionColor)
            }
            .accessibilityHidden(true)

            balanceColumn(
                label: "wallet.newBalance".localized,
                value: previewNewBalance,
                tint: viewModel.isValid ? directionColor : .primary
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func balanceColumn(label: String, value: Decimal, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.app(.caption2, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value.formattedAmount(for: viewModel.wallet.currencyCode))
                .font(.app(.title3, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.15), value: value)
        }
        .frame(maxWidth: .infinity)
    }
}
