
import SwiftUI
import SwiftData

struct DebtDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var debt: Debt
    
    @Query(sort: \Wallet.name) private var wallets: [Wallet]
    
    @State private var showPaymentSheet = false
    @State private var transactionToEdit: Transaction?
    @State private var statusErrorMessage: String?
    @State private var showStatusError = false
    
    private let completionTolerance: Decimal = 0.000001
    
    private var debtTransactions: [Transaction] {
        debt.transactions ?? []
    }
    
    private var hasRemainingBalance: Bool {
        debt.remainingAmount > completionTolerance
    }
    
    var body: some View {
        List {
            // Header Section
            Section {
                VStack(alignment: .center, spacing: 8) {
                    Text(debt.personName)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(debt.type.title)
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(debt.type == .iOwe ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                        .foregroundStyle(debt.type == .iOwe ? .red : .green)
                        .cornerRadius(6)
                    
                    Text(debt.isCompleted ? L10n.Debt.paid : "Active")
                        .font(.caption)
                        .foregroundStyle(debt.isCompleted ? .green : .secondary)
                    
                    Divider()
                        .padding(.vertical)
                    
                    HStack {
                        VStack {
                            Text(L10n.Debt.total)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(debt.totalAmount, format: .currency(code: debt.currencyCode))
                                .fontWeight(.semibold)
                        }
                        
                        Spacer()
                        
                        VStack {
                            Text(L10n.Debt.paid)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(debt.amountPaid, format: .currency(code: debt.currencyCode))
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                        }
                        
                        Spacer()
                        
                        VStack {
                            Text(L10n.Debt.remaining)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(debt.remainingAmount, format: .currency(code: debt.currencyCode))
                                .fontWeight(.bold)
                                .foregroundStyle(debt.remainingAmount > 0 ? .primary : .secondary)
                        }
                    }
                }
                .padding(.vertical)
            }
            
            if let note = debt.note {
                Section(L10n.Transaction.note) {
                    Text(note)
                }
            }
            
            if debtTransactions.isEmpty {
                Section(L10n.Debt.history) {
                    Text("No transactions recorded yet.")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            } else {
                TransactionListView(
                    transactions: debtTransactions,
                    listHeader: L10n.Debt.history,
                    onEdit: { txn in
                        transactionToEdit = txn
                    },
                    onDelete: { txn in
                        deleteTransaction(txn)
                    }
                )
            }
            
            // Actions
            Section {
                Button {
                    showPaymentSheet = true
                } label: {
                    Label(L10n.Debt.recordPayment, systemImage: "banknote")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(debt.remainingAmount <= 0)
                
                if debt.isCompleted && hasRemainingBalance {
                    Button {
                        setActive()
                    } label: {
                        Label("Mark as Active", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                } else if !debt.isCompleted && !hasRemainingBalance {
                    Button {
                        setCompleted()
                    } label: {
                        Label(L10n.Debt.markCompleted, systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaymentSheet) {
            AddPaymentView(debt: debt, wallets: wallets)
        }
        .sheet(item: $transactionToEdit) { txn in
            AddTransactionView(
                viewModel: AddTransactionViewModel(
                    dataService: SwiftDataService(modelContext: modelContext),
                    initialWallet: txn.sourceWallet,
                    transaction: txn
                ),
                isNewTransaction: false
            )
        }
        .alert("Status Error", isPresented: $showStatusError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(statusErrorMessage ?? "Failed to update debt status.")
        }
        .onAppear {
            syncStatusIfNeeded()
        }
    }
    
    private func deleteTransaction(_ transaction: Transaction) {
        transaction.sourceWallet?.invalidateBalanceCache()
        transaction.destinationWallet?.invalidateBalanceCache()
        modelContext.delete(transaction)

        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            syncStatusIfNeeded()
        } catch {
            statusErrorMessage = error.localizedDescription
            showStatusError = true
        }
    }
    
    private func syncStatusIfNeeded() {
        do {
            try DebtService(modelContext: modelContext).syncCompletionStatus(for: debt)
        } catch {
            statusErrorMessage = error.localizedDescription
            showStatusError = true
        }
    }
    
    private func setCompleted() {
        do {
            try DebtService(modelContext: modelContext).setCompletion(for: debt, isCompleted: true)
        } catch {
            statusErrorMessage = error.localizedDescription
            showStatusError = true
        }
    }
    
    private func setActive() {
        do {
            try DebtService(modelContext: modelContext).setCompletion(for: debt, isCompleted: false)
        } catch {
            statusErrorMessage = error.localizedDescription
            showStatusError = true
        }
    }
}

struct AddPaymentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let debt: Debt
    let wallets: [Wallet]
    
    @State private var amount: Decimal?
    @State private var date = Date()
    @State private var selectedWallet: Wallet?
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(L10n.Transaction.amount)
                        Spacer()
                        TextField("0.00", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    DatePicker(L10n.Transaction.date, selection: $date)
                    
                    Picker("Wallet (Optional)", selection: $selectedWallet) {
                        Text("None").tag(Optional<Wallet>.none)
                        ForEach(wallets) { wallet in
                            Text(wallet.name).tag(Optional(wallet))
                        }
                    }
                } footer: {
                    if let wallet = selectedWallet {
                        Text(debt.type == .iOwe 
                             ? "This will deduct money from \(wallet.name) (Expense)."
                             : "This will add money to \(wallet.name) (Income).")
                    }
                }
            }
            .navigationTitle(L10n.Debt.recordPayment)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save) {
                        savePayment()
                    }
                    .disabled((amount ?? 0) <= 0)
                }
            }
            .onAppear {
                // Auto-fill remaining amount
                if debt.remainingAmount > 0 {
                    amount = debt.remainingAmount
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Failed to save payment.")
            }
        }
    }
    
    @MainActor
    private func savePayment() {
        guard let amount = amount, amount > 0 else { return }

        showError = false
        errorMessage = nil
        do {
            let service = DebtService(modelContext: modelContext)
            try service.recordRepayment(for: debt, amount: amount, sourceWallet: selectedWallet, date: date)
            HapticManager.shared.notification(type: .success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            HapticManager.shared.notification(type: .error)
        }
    }
}
