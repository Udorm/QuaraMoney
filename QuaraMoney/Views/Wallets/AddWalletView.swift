import SwiftUI

struct AddWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel: AddWalletViewModel
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header Section
                        VStack(spacing: 24) {
                            // Preview
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(hex: viewModel.colorHex) ?? .blue,
                                                (Color(hex: viewModel.colorHex) ?? .blue).opacity(0.7)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 100, height: 100)
                                    .shadow(color: (Color(hex: viewModel.colorHex) ?? .blue).opacity(0.3), radius: 10, x: 0, y: 5)
                                    .overlay(
                                        Circle()
                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                    )
                                
                                Image(systemName: viewModel.icon)
                                    .font(.system(size: 40, weight: .semibold))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.1), radius: 2)
                            }
                            .padding(.top, 20)
                            
                            VStack(spacing: 16) {
                                TextField("Wallet Name", text: $viewModel.name)
                                    .font(.title3.bold())
                                    .multilineTextAlignment(.center)
                                    .submitLabel(.done)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(12)
                                    .padding(.horizontal, 32)
                                
                                HStack {
                                    Text("Currency")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Picker("Currency", selection: $viewModel.currencyCode) {
                                        Text("USD ($)").tag("USD")
                                        Text("EUR (€)").tag("EUR")
                                        Text("KHR (៛)").tag("KHR")
                                        Text("JPY (¥)").tag("JPY")
                                    }
                                    .tint(.primary)
                                }
                                .padding(.horizontal, 32)
                                .padding(.bottom, 8)
                            }
                        }
                        
                        // Pickers
                        VStack(spacing: 24) {
                            ColorPickerContainer(selectedColorHex: $viewModel.colorHex)
                                .padding(.horizontal, 16)
                            
                            SymbolPickerContainer(selectedIcon: $viewModel.icon, selectedColorHex: viewModel.colorHex)
                                .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle(viewModel.isEditing ? "Edit Wallet" : "New Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isEditing ? "Save" : "Add") {
                        viewModel.saveWallet()
                        dismiss()
                    }
                    .disabled(!viewModel.isValid)
                    .fontWeight(.bold)
                }
            }
        }
    }
}
