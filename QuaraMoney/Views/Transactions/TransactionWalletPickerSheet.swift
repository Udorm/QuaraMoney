import SwiftUI

/// Full-height wallet picker sheet, matching the style of `TransactionCategoryPickerSheet`.
struct TransactionWalletPickerSheet: View {
    let wallets: [Wallet]
    let selectedWalletID: UUID?
    let onSelect: (Wallet) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var displayWallets: [Wallet] {
        guard !searchText.isEmpty else { return wallets }
        return wallets.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.currencyCode.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if displayWallets.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(displayWallets) { wallet in
                            WalletColorRow(
                                wallet: wallet,
                                isSelected: selectedWalletID == wallet.id
                            ) {
                                onSelect(wallet)
                            }
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 52 }
                        }
                    }
                } header: {
                    sectionHeader(L10n.Wallet.selectWallet)
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L10n.Wallet.selectWallet)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.Common.cancel)
                }
            }
            .safeAreaBar(edge: .bottom) {
                searchBar
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .appFont(.body)
                .foregroundStyle(.secondary)

            TextField("transaction.searchWallets".localized, text: $searchText)
                .appFont(.body)
                .autocorrectionDisabled()
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Common.cancel)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 16)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .appFont(.headline)
            .foregroundStyle(.primary)
            .textCase(nil)
    }
}

// MARK: - Color-coded wallet row

struct WalletColorRow: View {
    let wallet: Wallet
    let isSelected: Bool
    let action: () -> Void

    private var color: Color { Color(hex: wallet.colorHex) ?? .blue }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: wallet.icon)
                    .appFont(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(
                            colors: [color, color.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(wallet.name)
                        .appFont(.body)
                        .foregroundStyle(.primary)
                    Text(wallet.currencyCode)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(wallet.name)\(isSelected ? ", selected" : "")")
    }
}
