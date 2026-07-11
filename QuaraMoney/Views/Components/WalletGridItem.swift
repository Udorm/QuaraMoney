import SwiftUI

/// Grid cell for picking a wallet in the Add/Edit Transaction flow.
///
/// Mirrors `CategoryGridItem`'s vertical layout (glyph tile on top, name below,
/// identical 46×46 frame) so the wallet and category selectors line up to the
/// same row height. Instead of the category circle, it draws a miniature wallet
/// card — a color-filled rounded rectangle with a white glyph — to echo the
/// wallet hero on `WalletDetailView`.
struct WalletGridItem: View {
    let wallet: Wallet
    let isSelected: Bool
    let action: () -> Void

    private var walletColor: Color {
        Color(hex: wallet.colorHex) ?? .accentColor
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    // Selection ring, sized to sit just outside the card.
                    if isSelected {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(walletColor, lineWidth: 2)
                            .frame(width: 46, height: 46)
                    }

                    // Miniature wallet card — same shape language as the wallet
                    // detail hero: color fill + white glyph, with the currency
                    // symbol reading as an embossed mark beneath it (like the
                    // currency on a real payment card).
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(walletColor.gradient)
                        .frame(width: 40, height: 40)
                        .overlay(
                            VStack(spacing: 1) {
                                Image(systemName: wallet.icon)
                                    .appFont(size: 16)
                                    .foregroundStyle(.white)
                                Text(String.currencySymbol(for: wallet.currencyCode))
                                    .appFont(size: 9, weight: .semibold)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.white.opacity(0.18), lineWidth: 0.5)
                        )
                        .shadow(color: walletColor.opacity(isSelected ? 0.35 : 0.15), radius: 3, y: 2)
                }
                .frame(width: 46, height: 46)

                Text(wallet.name)
                    .font(.app(.caption2, weight: isSelected ? .bold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? walletColor : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(wallet.name) wallet\(isSelected ? ", selected" : "")")
    }
}
