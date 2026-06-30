import SwiftUI

/// Lets the user pick a destination wallet to receive a soon-to-be-deleted
/// wallet's transactions, instead of deleting them. Transfers have their stored
/// rate recomputed for the new wallet's currency (handled in SoftDeleteService).
struct MoveTransactionsSheet: View {
    let sourceWallet: Wallet
    let candidates: [Wallet]
    let onSelect: (Wallet) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates) { wallet in
                        Button {
                            onSelect(wallet)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: wallet.icon)
                                    .frame(width: 32, height: 32)
                                    .background(Color(hex: wallet.colorHex) ?? .gray)
                                    .foregroundStyle(.white)
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(wallet.name)
                                        .appFont(size: 16, weight: .medium)
                                    Text(wallet.currencyCode)
                                        .appFont(size: 13)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("wallet.moveTransactionsPrompt".localized(with: sourceWallet.name))
                        .textCase(nil)
                }
            }
            .navigationTitle("wallet.moveTransactionsTitle".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
            }
        }
    }
}
