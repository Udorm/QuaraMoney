import SwiftUI

/// The "your data is moving between these two apps" header shared by both sides
/// of the MitraTrip ↔ QuaraMoney handoff.
///
/// The same composition ships in MitraTrip's export sheet, so the transfer reads
/// as one continuous flow rather than two unrelated screens that happen to
/// mention each other. What differs between the two copies is which endpoint is
/// marked as *here*: the app you are currently standing in is drawn at full
/// strength inside a tinted ring, and the caption names the direction, so you can
/// tell where you are and which way the money is travelling without reading a
/// single row of the form.
///
/// The artwork is not a trust signal. A custom URL scheme carries no proof of
/// origin, so the MitraTrip icon here says "this link claims to come from
/// MitraTrip", nothing more — which is why the caption describes the direction of
/// travel and never asserts that the sender is verified.
///
/// Deliberately not a shared package — the two apps are separate repos with
/// separate asset catalogues, and a 60-line view is cheaper to mirror than to
/// vendor.
struct AppHandoffVisual: View {
    /// Which end of the handoff the *hosting app* sits at.
    enum Role {
        case source
        case destination
    }

    let role: Role

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 56

    /// The gap the chevrons occupy between the two icons.
    ///
    /// A fixed width rather than `maxWidth: .infinity`: letting the indicator
    /// absorb every point of slack pushed both icons out to the screen edges.
    /// Sizing the gap instead keeps the pair reading as one centred cluster.
    @ScaledMetric(relativeTo: .body) private var flowWidth: CGFloat = 100

    /// An iOS app icon's corner is ~22.37% of its side. Deriving it keeps the
    /// squircle correct when Dynamic Type scales `iconSize`, which a literal
    /// radius would not.
    private var iconCorner: CGFloat { iconSize * 0.2237 }

    private let ringInset: CGFloat = 4

    private var caption: String {
        switch role {
        case .source: "split.handoff.sending".localized
        case .destination: "split.handoff.receiving".localized
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                endpoint(
                    asset: "MitraTripIcon",
                    name: "MitraTrip",
                    isHere: role == .source
                )

                FlowIndicator(isAnimated: !reduceMotion)
                    .frame(width: flowWidth)

                endpoint(
                    asset: "AppIconDisplay",
                    name: "QuaraMoney",
                    isHere: role == .destination
                )
            }
            .padding(.horizontal, ringInset)

            Text(caption)
                .appFont(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
    }

    private func endpoint(asset: String, name: String, isHere: Bool) -> some View {
        VStack(spacing: 7) {
            Image(asset)
                .resizable()
                .scaledToFill()
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconCorner, style: .continuous))
                .shadow(color: .black.opacity(0.14), radius: 5, y: 3)
                .overlay {
                    if isHere {
                        // Outset by `ringInset` on every side, so the ring's
                        // radius is the icon's plus that inset — concentric.
                        RoundedRectangle(cornerRadius: iconCorner + ringInset, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .frame(width: iconSize + ringInset * 2, height: iconSize + ringInset * 2)
                    }
                }
                .opacity(isHere ? 1 : 0.85)

            Text(name)
                .appFont(.caption2, weight: isHere ? .semibold : .regular)
                .foregroundStyle(isHere ? .primary : .secondary)
                .lineLimit(1)
        }
    }
}

/// A very light multi-colour wash that drifts left to right behind the handoff
/// header and reaches up under the toolbar.
///
/// Sits behind the *scroll view*, not inside a row, because a `listRowBackground`
/// cannot escape its row to reach the navigation bar. That means the host has to
/// hide the scroll content background and restore the grouped colour itself.
struct AppHandoffBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shift = false

    /// Three colours sampled from the two app icons: MitraTrip's mint pin, the
    /// blue both icons happen to share, and QuaraMoney's coral bar. Left to
    /// right they run MitraTrip → shared → QuaraMoney, so the wash belongs to
    /// this particular handoff rather than being generic decoration.
    ///
    /// Literal components rather than semantic colours — these are brand values
    /// lifted from the artwork, and at 6–7% they read as a tint, not a fill.
    ///
    /// Two copies plus a repeat of the first, so the pattern's period is exactly
    /// one view width and sliding by that width loops with no visible seam; a
    /// plain doubled array would jump on every repeat.
    private var strip: [Color] {
        let base: [Color] = [
            Color(red: 0.549, green: 0.761, blue: 0.725).opacity(0.07),  // #8CC2B9 MitraTrip mint
            Color(red: 0.349, green: 0.451, blue: 0.639).opacity(0.06),  // #5973A3 shared blue
            Color(red: 0.867, green: 0.467, blue: 0.318).opacity(0.07),  // #DD7751 QuaraMoney coral
        ]
        return base + base + [base[0]]
    }

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: strip, startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 2, height: geo.size.height)
                .offset(x: shift ? -geo.size.width : 0)
                .animation(
                    reduceMotion ? nil : .linear(duration: 18).repeatForever(autoreverses: false),
                    value: shift
                )
                .onAppear { shift = true }
        }
        // Fades out rather than stopping dead, so no hard edge cuts across the
        // list below the header.
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.62),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Three chevrons that pulse left-to-right to suggest travel between the icons.
private struct FlowIndicator: View {
    let isAnimated: Bool

    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "chevron.right")
                    .appFont(.caption, weight: .bold)
                    .foregroundStyle(Color.accentColor)
                    .opacity(opacity(at: index))
                    .animation(
                        isAnimated
                            ? .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.18)
                            : nil,
                        value: animating
                    )
            }
        }
        .onAppear { animating = isAnimated }
    }

    /// Reduce Motion gets the mid-travel frame — the same shape, held still.
    private func opacity(at index: Int) -> Double {
        guard isAnimated else { return 0.35 + Double(index) * 0.2 }
        return animating ? 1 : 0.25
    }
}

#Preview("Destination") {
    List {
        Section {
            AppHandoffVisual(role: .destination)
                .listRowBackground(Color.clear)
        }
    }
    .listStyle(.insetGrouped)
}
