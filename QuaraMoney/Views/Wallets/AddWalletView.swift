import SwiftUI

struct AddWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel: AddWalletViewModel
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $viewModel.name)
                    
                    Picker("Currency", selection: $viewModel.currencyCode) {
                        Text("USD").tag("USD")
                        Text("EUR").tag("EUR")
                        Text("KHR").tag("KHR")
                        Text("JPY").tag("JPY")
                    }
                }
                
                Section("Appearance") {
                    // Visual Preview
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: viewModel.colorHex) ?? .blue)
                                    .frame(width: 80, height: 80)
                                    .shadow(radius: 5)
                                
                                Image(systemName: viewModel.icon)
                                    .font(.system(size: 36))
                                    .foregroundColor(.white)
                            }
                            
                            Text("Preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical)
                    .listRowBackground(Color.clear)
                    
                    NavigationLink {
                        ColorPickerView(selectedColorHex: $viewModel.colorHex)
                            .navigationTitle("Select Color")
                    } label: {
                        HStack {
                            Text("Color")
                            Spacer()
                            Circle()
                                .fill(Color(hex: viewModel.colorHex) ?? .blue)
                                .frame(width: 24, height: 24)
                        }
                    }
                    
                    NavigationLink {
                        IconPickerView(selectedIcon: $viewModel.icon, selectedColorHex: $viewModel.colorHex)
                            .navigationTitle("Select Icon")
                    } label: {
                        HStack {
                            Text("Icon")
                            Spacer()
                            Image(systemName: viewModel.icon)
                                .foregroundColor(Color(hex: viewModel.colorHex) ?? .blue)
                        }
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
                }
            }
        }
    }
}
