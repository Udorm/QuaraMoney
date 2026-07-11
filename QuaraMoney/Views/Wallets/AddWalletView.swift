import SwiftUI

struct AddWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: AddWalletViewModel

    // Focus state for keyboard
    @FocusState private var isNameFocused: Bool
    @State private var showingDeleteAlert = false
    @State private var showingCurrencyPicker = false
    @State private var showingIconPicker = false

    private var walletColor: Color {
        Color(hex: viewModel.colorHex) ?? .blue
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Card Preview Section
                Section {
                    cardPreview
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets()) // Full-width card — aligns with sections below
                        .listRowSeparator(.hidden)
                }

                // MARK: - Input Fields
                Section(L10n.Wallet.details) {
                    TextField(L10n.Wallet.name, text: $viewModel.name)
                        .focused($isNameFocused)
                        .submitLabel(.done)

                    Button {
                        showingCurrencyPicker = true
                    } label: {
                        HStack {
                            Text(L10n.Wallet.currency)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(viewModel.currencyCode)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.app(.footnote, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section(L10n.Wallet.appearance) {
                    colorSwatches

                    Button {
                        showingIconPicker = true
                    } label: {
                        HStack {
                            Text(L10n.Wallet.icon)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: viewModel.icon)
                                .foregroundStyle(walletColor)
                            Image(systemName: "chevron.right")
                                .font(.app(.footnote, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
            .sheet(isPresented: $showingCurrencyPicker) {
                NavigationStack {
                    CurrencySelectionView(selection: $viewModel.currencyCode, quickSelectCurrencies: ["USD", "KHR"])
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(.systemGroupedBackground))
            }
            .sheet(isPresented: $showingIconPicker) {
                NavigationStack {
                    IconPickerView(selectedIcon: $viewModel.icon, selectedColorHex: $viewModel.colorHex)
                        .navigationTitle(L10n.Category.selectIcon)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L10n.Common.done) {
                                    showingIconPicker = false
                                }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Live card preview

    private var cardPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.isEditing ? L10n.Wallet.edit : L10n.Wallet.new)
                        .font(.app(.caption2, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .textCase(.uppercase)
                    Text(viewModel.name.isEmpty ? L10n.Wallet.name : viewModel.name)
                        .font(.app(.title2, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer()

                Image(systemName: viewModel.icon)
                    .appFont(size: 22)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Spacer()

            HStack {
                Text(viewModel.currencyCode)
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.2), in: Capsule())

                Spacer()

                Text("QuaraMoney")
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(20)
        .frame(height: 180)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [walletColor, walletColor.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    // Subtle texture so the card reads as a card, not a slab.
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.08))
                            .frame(width: 190, height: 190)
                            .offset(x: 130, y: -90)
                        Circle()
                            .fill(.white.opacity(0.05))
                            .frame(width: 240, height: 240)
                            .offset(x: -140, y: 110)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                )
                .shadow(color: walletColor.opacity(0.35), radius: 12, x: 0, y: 6)
        )
        .animation(.snappy, value: viewModel.colorHex)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L10n.Common.preview): \(viewModel.name.isEmpty ? L10n.Wallet.name : viewModel.name), \(viewModel.currencyCode)")
    }

    // MARK: - Inline color swatches

    private var colorSwatches: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(AppTheme.colors, id: \.self) { colorHex in
                    let isSelected = colorHex.caseInsensitiveCompare(viewModel.colorHex) == .orderedSame
                    Button {
                        viewModel.colorHex = colorHex
                        HapticManager.shared.selection()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: colorHex) ?? .gray)
                                .frame(width: 32, height: 32)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.app(.caption, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? (Color(hex: colorHex) ?? .gray).opacity(0.35) : .clear, lineWidth: 3)
                                .frame(width: 40, height: 40)
                        )
                        .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(colorHex)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}
