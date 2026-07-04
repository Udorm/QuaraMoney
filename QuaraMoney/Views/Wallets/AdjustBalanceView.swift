import SwiftUI

struct AdjustBalanceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AdjustBalanceViewModel
    @FocusState private var isAmountFocused: Bool

    init(wallet: Wallet, dataService: DataService) {
        _viewModel = State(wrappedValue: AdjustBalanceViewModel(wallet: wallet, dataService: dataService))
    }

    private var walletColor: Color {
        Color(hex: viewModel.wallet.colorHex) ?? .blue
    }

    private var differenceColor: Color {
        viewModel.difference >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    var body: some View {
        NavigationStack {
            Form {
                // Current balance header
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: viewModel.wallet.icon)
                            .font(.app(.title3))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                LinearGradient(
                                    colors: [walletColor, walletColor.opacity(0.72)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )

                        VStack(spacing: 2) {
                            Text("wallet.currentBalance".localized)
                                .font(.app(.caption, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(viewModel.currentBalance.formattedAmount(for: viewModel.wallet.currencyCode))
                                .font(.app(.title, weight: .bold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                // Target Balance Input
                Section {
                    HStack {
                        Text(viewModel.wallet.currencyCode)
                            .font(.app(.subheadline, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("wallet.newBalance".localized, text: $viewModel.targetBalanceString)
                            .keyboardType(.decimalPad)
                            .font(.app(.title3, weight: .semibold))
                            .monospacedDigit()
                            .focused($isAmountFocused)
                    }

                    if viewModel.targetBalance != nil {
                        HStack {
                            Text("wallet.difference".localized)
                            Spacer()
                            HStack(spacing: 3) {
                                Image(systemName: viewModel.difference >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.app(.caption2, weight: .bold))
                                let sign = viewModel.difference >= 0 ? "+" : ""
                                Text("\(sign)\(viewModel.difference.formattedAmount(for: viewModel.wallet.currencyCode))")
                                    .font(.app(.subheadline, weight: .semibold))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(differenceColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(differenceColor.opacity(0.12), in: Capsule())
                        }
                    }
                } header: {
                    Text("wallet.newBalance".localized)
                } footer: {
                    Text("wallet.adjustFooter".localized)
                }

                Section {
                    DatePicker("transaction.date".localized, selection: $viewModel.date, displayedComponents: [.date, .hourAndMinute])

                    Toggle("transaction.excludeFromReports".localized, isOn: $viewModel.excludeFromReports)
                } header: {
                    Text("common.details".localized)
                }

                Section {
                    TextField("transaction.noteOptional".localized, text: $viewModel.note)
                }
            }
            .navigationTitle("wallet.adjustBalance".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save) {
                        viewModel.save()
                        dismiss()
                    }
                    .disabled(!viewModel.isValid)
                }
            }
            .onAppear {
                isAmountFocused = true
            }
        }
    }
}
