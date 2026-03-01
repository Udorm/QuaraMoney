import SwiftUI

struct AdjustBalanceView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AdjustBalanceViewModel
    
    init(wallet: Wallet, dataService: DataService) {
        _viewModel = StateObject(wrappedValue: AdjustBalanceViewModel(wallet: wallet, dataService: dataService))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Current Balance Section (Read-only)
                Section {
                    HStack {
                        Text("Current Balance")
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
                        TextField("New Balance", text: $viewModel.targetBalanceString)
                            .keyboardType(.decimalPad)
                            .font(.app(.title3))
                    }
                    
                    if viewModel.targetBalance != nil {
                        HStack {
                            Text("Difference")
                            Spacer()
                            let sign = viewModel.difference >= 0 ? "+" : ""
                            Text("\(sign)\(viewModel.difference.formattedAmount(for: viewModel.wallet.currencyCode))")
                                .foregroundStyle(viewModel.difference >= 0 ? .green : .red)
                        }
                    }
                } header: {
                    Text("New Balance")
                } footer: {
                    Text("Enter the actual amount currently in your wallet. The app will create a transaction to adjust the difference.")
                }
                
                Section {
                    DatePicker("Date", selection: $viewModel.date, displayedComponents: [.date, .hourAndMinute])
                    
                    Toggle("Exclude from Reports", isOn: $viewModel.excludeFromReports)
                } header: {
                    Text("Details")
                }
                
                Section {
                    TextField("Note (Optional)", text: $viewModel.note)
                }
            }
            .navigationTitle("Adjust Balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.save()
                        dismiss()
                    }
                    .disabled(!viewModel.isValid)
                }
            }
        }
    }
}
