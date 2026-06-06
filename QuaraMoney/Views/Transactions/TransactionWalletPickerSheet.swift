import SwiftUI

/// Full-height wallet picker sheet, matching the style of `TransactionCategoryPickerSheet`.
struct TransactionWalletPickerSheet: View {
    let wallets: [Wallet]
    let selectedWalletID: UUID?
    let onSelect: (Wallet) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""

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
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 44 }
                        }
                    }
                } header: {
                    sectionHeader(L10n.Wallet.selectWallet)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.Wallet.selectWallet)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .toolbar,
                prompt: "transaction.searchWallets".localized
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.Common.cancel)
                }
                if #available(iOS 26, *) {
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.app(.headline))
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
                    .font(.app(.subheadline))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(color)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(wallet.name)
                        .font(.app(.body))
                        .foregroundStyle(.primary)
                    Text(wallet.currencyCode)
                        .font(.app(.caption))
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
