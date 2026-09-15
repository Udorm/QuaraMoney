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
/// The header also carries the payload — the amount riding on the chevron run
/// between the two icons, the trip name inside the caption. Both used to sit in a summary
/// card underneath, which meant the screen stated the same transfer twice: once
/// as artwork, once as data. Folding the figures into the artwork removed a whole
/// card and lifted the screen's actual work — choosing a wallet, checking the
/// categories — further up.
///
/// The amount sits *on* the connector rather than above it. Stacking it cost a
/// line of height for a figure that belongs to the journey anyway, and a
/// full-width run has room for a long total in a way a 124pt gap never did.
///
/// It serves two routes. A `Route` of `.fromMitraTrip` draws the two apps; one of
/// `.betweenUsers` draws QuaraMoney's own icon at both ends, because a split sent
/// from one QuaraMoney user to another travels between *people*, not apps, and
/// two different logos would have been a lie about what is happening. There the
/// labels carry the distinction the artwork can't, and "You" always sits on the
/// end the screen belongs to.
///
/// The artwork is not a trust signal. A custom URL scheme carries no proof of
/// origin, so the MitraTrip icon here says "this link claims to come from
/// MitraTrip", nothing more — which is why the caption describes the direction of
/// travel and never asserts that the sender is verified, and why an unrecognised
/// claim falls back to `.betweenUsers`, which asserts nothing at all.
///
/// Deliberately not a shared package — the two apps are separate repos with
/// separate asset catalogues, and a 60-line view is cheaper to mirror than to
/// vendor.
struct AppHandoffVisual: View {
    /// Which end of the handoff the *hosting screen* sits at.
    enum Role {
        case source
        case destination
    }

    /// Who the two ends are.
    enum Route {
        /// MitraTrip on the left, QuaraMoney on the right — two apps.
        case fromMitraTrip

        /// One QuaraMoney user to another — the same app at both ends, so the
        /// same icon twice.
        case betweenUsers
    }

    let role: Role

    var route: Route = .fromMitraTrip

    /// The figure that is travelling, pre-formatted with its currency symbol.
    ///
    /// A formatted string rather than an amount + code pair on purpose: the
    /// symbol already identifies the money, so a separate currency chip was
    /// restating what the number's first character said.
    var amount: String?

    /// The trip the share belongs to, rendered inside the caption sentence so
    /// that naming it costs no line of its own. Still a sender-supplied claim,
    /// which is why the sentence describes it and never vouches for it.
    ///
    /// `.betweenUsers` ignores it: a split between two people has no trip, and
    /// what is being split is already spelled out in the rows below.
    var tripName: String?

    /// Supplied by hosts that have something to explain about the figure.
    ///
    /// When it is nil the amount is plain text and no badge is drawn — the
    /// affordance only appears where there is actually a screen behind it. The
    /// prose it opens used to be a permanent footer under the header; a line of
    /// small grey type that most people read once, sitting above the controls
    /// they came to use, is worth a tap instead.
    var onInfo: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 56

    /// The narrowest the connector is allowed to get.
    ///
    /// It otherwise takes `maxWidth: .infinity` — the opposite of the earlier
    /// fixed gap. Pushing both icons out to the row's edges is now the point:
    /// every point the icons give up is a point of run the amount can sit on,
    /// which is what lets a long total stay at full size.
    @ScaledMetric(relativeTo: .body) private var minFlowWidth: CGFloat = 72

    /// An iOS app icon's corner is ~22.37% of its side. Deriving it keeps the
    /// squircle correct when Dynamic Type scales `iconSize`, which a literal
    /// radius would not.
    private var iconCorner: CGFloat { iconSize * 0.2237 }

    private let ringInset: CGFloat = 4

    private var trimmedTripName: String? {
        guard let name = tripName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        return name
    }

    /// Naming the trip replaces "from MitraTrip" rather than being appended to
    /// it: the sender is already spelled out under the icon the chevrons come
    /// from, so the sentence can spend its width on the thing the artwork can't
    /// show.
    private var caption: String {
        switch route {
        case .betweenUsers:
            switch role {
            case .source: return "split.handoff.sharingPeer".localized
            case .destination: return "split.receivedSubtitle".localized
            }

        case .fromMitraTrip:
            if let trimmedTripName {
                switch role {
                case .source: return "split.handoff.sendingTrip".localized(with: trimmedTripName)
                case .destination: return "split.handoff.receivingTrip".localized(with: trimmedTripName)
                }
            }
            switch role {
            case .source: return "split.handoff.sending".localized
            case .destination: return "split.handoff.receiving".localized
            }
        }
    }

    /// The two ends, left to right. `.betweenUsers` names them by who they are —
    /// the same icon twice would otherwise be two identical, unlabelled squares.
    private var endpoints: (leading: (asset: String, name: String), trailing: (asset: String, name: String)) {
        switch route {
        case .fromMitraTrip:
            return (("MitraTripIcon", "MitraTrip"), ("AppIconDisplay", "QuaraMoney"))

        case .betweenUsers:
            let icon = "AppIconDisplay"
            let leading = role == .source
                ? "split.handoff.you".localized
                : "split.handoff.sender".localized
            let trailing = role == .destination
                ? "split.handoff.you".localized
                : "split.handoff.recipient".localized
            return ((icon, leading), (icon, trailing))
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .iconCenter, spacing: 8) {
                let ends = endpoints

                endpoint(
                    asset: ends.leading.asset,
                    name: ends.leading.name,
                    isHere: role == .source
                )

                FlowConnector(amount: amount, onInfo: onInfo, isAnimated: !reduceMotion)
                    .frame(minWidth: minFlowWidth, maxWidth: .infinity)
                    .alignmentGuide(.iconCenter) { $0[VerticalAlignment.center] }

                endpoint(
                    asset: ends.trailing.asset,
                    name: ends.trailing.name,
                    isHere: role == .destination
                )
            }
            // Room for the two things that draw outside their column: the
            // selection ring (`ringInset`) and the longer app name, which
            // overhangs its icon-width column by a few points when it is the
            // semibold "here" endpoint.
            .padding(.horizontal, ringInset + 5)

            Text(caption)
                .appFont(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                // A long trip name wraps a line early rather than running into
                // the card's edge.
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        // Not one collapsed element any more: the amount is a control when the
        // host passes `onInfo`, and a control inside an `.ignore` container is
        // unreachable. The artwork hides itself instead, leaving the amount and
        // the caption — the only two things here that carry information — as the
        // two stops VoiceOver makes.
        .accessibilityElement(children: .contain)
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
                .alignmentGuide(.iconCenter) { $0[VerticalAlignment.center] }

            Text(name)
                .appFont(.caption2, weight: isHere ? .semibold : .regular)
                .foregroundStyle(isHere ? .primary : .secondary)
                .lineLimit(1)
                // Takes its ideal width and overhangs the column by the point or
                // two it needs. Shrinking it to fit instead left "QuaraMoney"
                // visibly smaller than "MitraTrip"; the overhang costs nothing,
                // because the only thing beside it at that height is empty space.
                .fixedSize()
        }
        // The column is the icon's width, not the name's. Letting the longer name
        // set it left a gap at each end the chevrons visibly failed to cross.
        .frame(width: iconSize)
        // Which app is which is already in the caption sentence.
        .accessibilityHidden(true)
    }
}

/// The chevron run between the two icons, with the amount riding on it.
///
/// The chevrons repeat the whole distance rather than clustering in the middle:
/// the span *is* the handoff, and a three-chevron stub floating in the gap read
/// as decoration next to the artwork it was meant to be joining.
///
/// They are solid where they leave one icon and arrive at the other, and thin to
/// almost nothing as they approach the amount. The ends are what say "these two
/// apps are connected"; the middle belongs to the figure.
private struct FlowConnector: View {
    let amount: String?
    let onInfo: (() -> Void)?
    let isAnimated: Bool

    @State private var animating = false

    /// Roughly one chevron per this many points. Deriving the count from the
    /// measured width rather than fixing it keeps the repeat looking the same on
    /// a small phone and a Max — and keeps it from crowding when a long total
    /// steals width from the run.
    private let pitch: CGFloat = 10

    /// Tall enough for the amount, which is the taller of the two things stacked
    /// here. Fixed because the chevron run measures itself and would otherwise
    /// have no height of its own to report.
    @ScaledMetric(relativeTo: .title3) private var runHeight: CGFloat = 26

    private var label: String? {
        guard let amount, !amount.isEmpty else { return nil }
        return amount
    }

    var body: some View {
        ZStack {
            // The run, with the amount's footprint punched out of it, so the
            // figure reads on clear ground instead of over half a chevron.
            //
            // The eraser is blurred rather than hard-edged: a crisp capsule cut
            // whichever glyph happened to fall on its boundary in half, leaving a
            // sliver of chevron beside the number. A soft edge dissolves them
            // instead, which is also what the run does at the ends.
            ZStack {
                chevrons

                if let label {
                    // The *unwrapped* label, so the hole matches what is drawn
                    // even when the visible copy is wearing a Button.
                    amountLabel(label)
                        .hidden()
                        .padding(.horizontal, 7)
                        .background(Capsule().fill(Color.black).blur(radius: 5))
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
            .accessibilityHidden(true)

            if let label {
                if let onInfo {
                    // The whole figure is the target, not the 13pt badge beside
                    // it: an `info.circle` on its own is a quarter of the 44pt
                    // minimum, and the amount is what someone would reach for
                    // anyway when asking "what is this number".
                    Button(action: onInfo) {
                        amountLabel(label)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label)
                    .accessibilityHint("Shows what this figure includes")
                } else {
                    amountLabel(label)
                        .accessibilityLabel(label)
                }
            }
        }
        .frame(height: runHeight)
        .animation(.snappy, value: amount)
    }

    private var chevrons: some View {
        GeometryReader { geo in
            let count = max(3, Int(geo.size.width / pitch))

            HStack(spacing: 0) {
                ForEach(Array(0..<count), id: \.self) { index in
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .opacity(opacity(at: index))
                        .animation(
                            isAnimated
                                ? .easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true)
                                    // Modulo, not the raw index: the wave has to
                                    // keep the same three-phase rhythm whether
                                    // the run fits eight chevrons or twenty-five.
                                    .delay(Double(index % 3) * 0.18)
                                : nil,
                            value: animating
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.18), location: 0.5),
                        .init(color: .black, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .onAppear { animating = isAnimated }
    }

    /// Reduce Motion gets the mid-travel frame — the same shape, held still.
    private func opacity(at index: Int) -> Double {
        guard isAnimated else { return 0.35 + Double(index % 3) * 0.2 }
        return animating ? 1 : 0.25
    }

    /// The figure, and the badge that says there is more to know about it.
    ///
    /// `.title3` is as large as it goes before it starts competing with the two
    /// 56pt icons it sits between — the old summary card's `.title` did exactly
    /// that. It scales down hard rather than truncating, because a total that
    /// has lost its last two digits is worse than a small one.
    private func amountLabel(_ text: String) -> some View {
        HStack(spacing: 5) {
            Text(text)
                .appFont(.title3, weight: .bold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            if onInfo != nil {
                Image(systemName: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Lines the chevrons up with the *icons'* centres rather than with the centre of
/// the icon-plus-name column.
///
/// Centring the connector on the icon-plus-name column instead would run the
/// chevrons ten points below the icons they are joining — visibly hitting them
/// off centre. Pinning them to the icon centre lands them where the artwork says
/// they should be.
private extension VerticalAlignment {
    enum IconCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    static let iconCenter = VerticalAlignment(IconCenter.self)
}

/// A very light multi-colour wash that drifts left to right behind the handoff
/// header and reaches up under the toolbar.
///
/// Sits behind the *scroll view*, not inside a row, because a `listRowBackground`
/// cannot escape its row to reach the navigation bar. That means the host has to
/// hide the scroll content background and restore the grouped colour itself.
struct AppHandoffBackdrop: View {
    var route: AppHandoffVisual.Route = .fromMitraTrip

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
        let mint = Color(red: 0.549, green: 0.761, blue: 0.725).opacity(0.07)   // #8CC2B9 MitraTrip
        let blue = Color(red: 0.349, green: 0.451, blue: 0.639).opacity(0.06)   // #5973A3 shared
        let coral = Color(red: 0.867, green: 0.467, blue: 0.318).opacity(0.07)  // #DD7751 QuaraMoney

        // A user-to-user split has no second brand to travel towards, so the
        // wash is QuaraMoney's own two colours and runs symmetrically — the
        // same shape the artwork above it has.
        let base: [Color] = switch route {
        case .fromMitraTrip: [mint, blue, coral]
        case .betweenUsers: [coral, blue, coral]
        }
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

#Preview("Destination") {
    List {
        Section {
            AppHandoffVisual(role: .destination, amount: "฿12,480.50", tripName: "Chiang Mai & Pai")
                .listRowBackground(Color.clear)
        } footer: {
            Text("Total Bill: ฿49,922.00 (4 people)").sectionFooter()
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("Between users — sharing") {
    List {
        Section {
            AppHandoffVisual(role: .source, route: .betweenUsers, amount: "$24.50")
                .listRowBackground(Color.clear)
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("Between users — receiving") {
    List {
        Section {
            AppHandoffVisual(role: .destination, route: .betweenUsers, amount: "$24.50")
                .listRowBackground(Color.clear)
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("No payload") {
    List {
        Section {
            AppHandoffVisual(role: .destination)
                .listRowBackground(Color.clear)
        }
    }
    .listStyle(.insetGrouped)
}
