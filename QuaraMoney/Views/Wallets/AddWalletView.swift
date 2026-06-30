import SwiftUI

struct AddWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: AddWalletViewModel
    
    // Focus state for keyboard
    @FocusState private var isNameFocused: Bool
    @State private var showingDeleteAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Card Preview Section
                Section {
                    VStack(alignment: .center, spacing: 20) {
                        // Card Preview
                        ZStack {
                            // Card Background
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            (Color(hex: viewModel.colorHex) ?? .blue),
                                            (Color(hex: viewModel.colorHex) ?? .blue).opacity(0.8)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: (Color(hex: viewModel.colorHex) ?? .blue).opacity(0.4), radius: 10, x: 0, y: 5)
                                .frame(height: 200)
                            
                            // Card Content
                            VStack(spacing: 15) {
                                // Icon Circle
                                ZStack {
                                    Circle()
                                        .fill(.white.opacity(0.2))
                                        .frame(width: 80, height: 80)
                                    
                                    Image(systemName: viewModel.icon)
                                        .appFont(size: 40) // Use appFont wrapper for custom sized font
                                        .foregroundStyle(.white)
                                }
                                
                                // Name
                                Text(viewModel.name.isEmpty ? L10n.Wallet.name : viewModel.name)
                                    .font(.app(.title2, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                
                                // Currency Badge
                                Text(viewModel.currencyCode)
                                    .font(.app(.caption, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.white.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                            .padding()
                        }
                        .padding(.top, 10)
                        
                        Text(L10n.Common.preview)
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                
                // MARK: - Input Fields
                Section(L10n.Wallet.details) {
                    TextField(L10n.Wallet.name, text: $viewModel.name)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                    
                    Picker(L10n.Wallet.currency, selection: $viewModel.currencyCode) {
                        Text("USD").tag("USD")
                        Text("KHR").tag("KHR")
                        Text("EUR").tag("EUR")
                        Text("JPY").tag("JPY")
                    }
                }
                
                Section(L10n.Wallet.appearance) {
                    NavigationLink {
                        ColorPickerView(selectedColorHex: $viewModel.colorHex)
                            .navigationTitle(L10n.Category.selectColor)
                    } label: {
                        HStack {
                            Text(L10n.Wallet.color)
                            Spacer()
                            Circle()
                                .fill(Color(hex: viewModel.colorHex) ?? .blue)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                        }
                    }
                    
                    NavigationLink {
                        IconPickerView(selectedIcon: $viewModel.icon, selectedColorHex: $viewModel.colorHex)
                            .navigationTitle(L10n.Category.selectIcon)
                    } label: {
                        HStack {
                            Text(L10n.Wallet.icon)
                            Spacer()
                            Image(systemName: viewModel.icon)
                                .foregroundColor(Color(hex: viewModel.colorHex) ?? .blue)
                        }
                    }
                }
                
                // MARK: - Actions (only when editing)
                if viewModel.isEditing {
                    Section {
                        Toggle(isOn: Binding(
                            get: { viewModel.isArchived },
                            set: { newValue in
                                if newValue {
                                    viewModel.archiveWallet()
                                } else {
                                    viewModel.unarchiveWallet()
                                }
                            }
                        )) {
                            Label(L10n.Wallet.archive, systemImage: "archivebox")
                        }
                        
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label(L10n.Common.delete, systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(viewModel.isEditing ? L10n.Wallet.edit : L10n.Wallet.new)
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
                        viewModel.saveWallet()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.isValid)
                }
            }
            .onAppear {
                if !viewModel.isEditing {
                    isNameFocused = true
                }
            }
            .alert(L10n.Common.delete, isPresented: $showingDeleteAlert) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Common.delete, role: .destructive) {
                    viewModel.deleteWallet()
                    dismiss()
                }
            } message: {
                Text(L10n.Wallet.deleteRelatedTransactionsWarning((viewModel.walletToEdit?.outgoingTransactions ?? []).filter { $0.deletedAt == nil }.count))
            }
        }
    }
}
