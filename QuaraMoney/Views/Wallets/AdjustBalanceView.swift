import SwiftUI

struct AdjustBalanceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AdjustBalanceViewModel

    init(wallet: Wallet, dataService: DataService) {
        _viewModel = State(wrappedValue: AdjustBalanceViewModel(wallet: wallet, dataService: dataService))
    }

    var body: some View {
        NavigationStack {
            Form {
                // Current Balance Section (Read-only)
                Section {
                    HStack {
                        Text("wallet.currentBalance".localized)
                        Spacer()
                        Text(viewModel.currentBalance.formattedAmount(for: viewModel.wallet.currencyCode))
                            .foregroundStyle(.secondary)
                    }
                }

                // Target Balance Input
                Section {
                    HStack {
                        Text(viewModel.wallet.currencyCode)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        TextField("wallet.newBalance".localized, text: $viewModel.targetBalanceString)
                            .keyboardType(.decimalPad)
                            .font(.app(.title3))
                    }

                    if viewModel.targetBalance != nil {
                        HStack {
                            Text("wallet.difference".localized)
                            Spacer()
                            let sign = viewModel.difference >= 0 ? "+" : ""
                            Text("\(sign)\(viewModel.difference.formattedAmount(for: viewModel.wallet.currencyCode))")
                                .foregroundStyle(viewModel.difference >= 0 ? .green : .red)
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
        }
    }
}
