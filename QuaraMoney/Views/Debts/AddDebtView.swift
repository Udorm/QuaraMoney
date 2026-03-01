
import SwiftUI
import SwiftData

struct AddDebtView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: DebtFormViewModel

    @Query(sort: \Wallet.name) private var wallets: [Wallet]

    init(debtToEdit: Debt? = nil) {
        _viewModel = StateObject(wrappedValue: DebtFormViewModel(debt: debtToEdit))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.Debt.personName, text: $viewModel.personName)

                    HStack {
                        TextField(L10n.Transaction.amount, text: $viewModel.amountText)
                            .keyboardType(.decimalPad)

                        Text(viewModel.currencyCode)
                            .foregroundStyle(.secondary)
                    }
                    .disabled(viewModel.isEditing)

                    Picker("Type", selection: $viewModel.type) {
                        ForEach(DebtType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .disabled(viewModel.isEditing)
                } header: {
                    Text(L10n.DebtAdditional.details)
                } footer: {
                    if viewModel.isEditing {
                        Text(L10n.DebtAdditional.amountFixedWarning)
                    }
                }

                Section(L10n.Transaction.note) {
                    Toggle("Has Due Date", isOn: $viewModel.hasDueDate)
                    if viewModel.hasDueDate {
                        DatePicker(L10n.Debt.dueDate, selection: $viewModel.dueDate, displayedComponents: .date)
                    }

                    TextField(L10n.Transaction.note, text: $viewModel.note)
                }

                if !viewModel.isEditing {
                    Section(L10n.DebtAdditional.initialTransaction) {
                        Picker(L10n.Wallet.selectWallet, selection: $viewModel.selectedWallet) {
                            Text(L10n.DebtAdditional.noneTrackOnly).tag(Optional<Wallet>.none)
                            ForEach(wallets) { wallet in
                                Text(wallet.name).tag(Optional(wallet))
                            }
                        }

                        if let wallet = viewModel.selectedWallet {
                            Text(viewModel.type == .iOwe
                                 ? "A 'Loan' (Income) transaction of \(viewModel.amount?.formattedAmount(for: viewModel.currencyCode) ?? "0") will be added to \(wallet.name)."
                                 : "A 'Debt' (Expense) transaction of \(viewModel.amount?.formattedAmount(for: viewModel.currencyCode) ?? "0") will be deducted from \(wallet.name).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Text(L10n.DebtAdditional.initialTransactionHelpText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(viewModel.isEditing ? L10n.Common.edit : L10n.Debt.add)
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
            .alert(L10n.Common.error, isPresented: $viewModel.showError) {
                Button(L10n.Common.ok, role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
        }
    }
}
