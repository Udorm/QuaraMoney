import SwiftUI

// MARK: - Welcome Hero

/// App badge with gently floating feature chips orbiting it.
struct OnboardingWelcomeIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 230, height: 230)
                .blur(radius: 44)

            orbitBadge(offset: CGSize(width: -98, height: -66), drift: -8) {
                Image(systemName: "dollarsign")
                    .font(.app(.title3, weight: .bold))
                    .foregroundStyle(.green)
            }
            orbitBadge(offset: CGSize(width: 102, height: -44), drift: 8) {
                Text("៛")
                    .font(.app(.title3, weight: .bold))
                    .foregroundStyle(.purple)
            }
            orbitBadge(offset: CGSize(width: -84, height: 82), drift: 7) {
                Image(systemName: "chart.pie.fill")
                    .font(.app(.title3))
                    .foregroundStyle(.orange)
            }
            orbitBadge(offset: CGSize(width: 92, height: 92), drift: -7) {
                Image(systemName: "banknote.fill")
                    .font(.app(.title3))
                    .foregroundStyle(.blue)
            }

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 124, height: 124)
                .overlay(
                    Image(systemName: "wallet.pass.fill")
                        .font(.app(size: 54, weight: .medium))
                        .foregroundStyle(.white)
                )
                .shadow(color: Color.accentColor.opacity(0.35), radius: 20, y: 10)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
        .accessibilityHidden(true)
    }

    private func orbitBadge<Content: View>(
        offset: CGSize,
        drift: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: 54, height: 54)
            .background(
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            )
            .offset(offset)
            .offset(y: floating ? drift : 0)
    }
}

// MARK: - Track (Add Transaction Walkthrough)

/// Looping mini-app demo: tap +, type the amount, pick a category, saved.
struct OnboardingTrackIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var themeManager = ThemeManager.shared

    /// 0 = home screen (tap +), 1 = keypad typing, 2 = category pick, 3 = saved
    @State private var phase = 0
    @State private var typed = ""
    @State private var pressedKey: String?
    @State private var categoryPicked = false
    @State private var fabPressed = false

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]
    private let keystrokes = ["4", ".", "5", "0"]

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                homeScreen
                    .opacity(phase == 0 ? 1 : 0)
                addScreen
                    .opacity(phase == 0 ? 0 : 1)
            }
            .frame(width: 252, height: 296)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.10), radius: 22, y: 12)
            )

            stepCaption
        }
        .task { await runLoop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("onboarding.track.title".localized))
    }

    // MARK: Mini home screen

    private var homeScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("onboarding.demo.totalBalance".localized)
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
                Text("$248.00")
                    .font(.app(.title3, weight: .bold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )

            placeholderRow(icon: "cart.fill", tint: .orange)
            placeholderRow(icon: "bus.fill", tint: .blue)
            Spacer(minLength: 0)
        }
        .padding(16)
        .overlay(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
                    .frame(width: 62, height: 62)
                    .scaleEffect(fabPressed ? 1.5 : 1)
                    .opacity(fabPressed ? 0 : 0.8)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.app(.title3, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .scaleEffect(fabPressed ? 0.85 : 1)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 10, y: 5)
            }
            .padding(14)
        }
    }

    private func placeholderRow(icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: icon)
                        .font(.app(.caption))
                        .foregroundStyle(tint)
                )
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(Color(.systemFill)).frame(width: 88, height: 8)
                Capsule().fill(Color(.systemFill).opacity(0.6)).frame(width: 54, height: 8)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Mini add-transaction screen

    private var addScreen: some View {
        VStack(spacing: 12) {
            Text("$" + (typed.isEmpty ? "0" : typed))
                .font(.app(size: 36, weight: .bold))
                .foregroundStyle(typed.isEmpty ? Color.secondary : Color.primary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            HStack(spacing: 6) {
                categoryChip("fork.knife", "onboarding.demo.food".localized, selected: categoryPicked)
                categoryChip("bus.fill", "onboarding.demo.transport".localized, selected: false)
                categoryChip("cup.and.saucer.fill", "onboarding.demo.coffee".localized, selected: false)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(keys, id: \.self) { key in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(pressedKey == key ? Color.accentColor.opacity(0.3) : Color(.tertiarySystemFill))
                        .frame(height: 32)
                        .overlay(
                            Text(key)
                                .font(.app(.subheadline, weight: .semibold))
                        )
                        .scaleEffect(pressedKey == key ? 0.9 : 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .overlay {
            if phase == 3 {
                savedOverlay
            }
        }
    }

    private func categoryChip(_ icon: String, _ title: String, selected: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.app(.caption2))
            Text(title)
                .font(.app(.caption2, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Capsule().fill(selected ? Color.accentColor : Color(.tertiarySystemFill)))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .scaleEffect(selected ? 1.06 : 1)
    }

    private var savedOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.app(size: 56))
                .foregroundStyle(themeManager.incomeColor)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            Text("−$4.50 · " + "onboarding.demo.food".localized)
                .font(.app(.subheadline, weight: .semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: Step caption

    private var stepText: String {
        switch phase {
        case 0: return "onboarding.track.step1".localized
        case 1: return "onboarding.track.step2".localized
        case 2: return "onboarding.track.step3".localized
        default: return "onboarding.demo.saved".localized
        }
    }

    private var stepCaption: some View {
        HStack(spacing: 6) {
            Image(systemName: phase == 3 ? "checkmark.circle.fill" : "hand.tap.fill")
            Text(stepText)
        }
        .font(.app(.footnote, weight: .semibold))
        .foregroundStyle(phase == 3 ? themeManager.incomeColor : Color.accentColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
        .animation(.easeInOut(duration: 0.25), value: phase)
    }

    // MARK: Animation loop

    /// Sleeps and reports whether the task is still alive.
    private func pause(_ seconds: Double) async -> Bool {
        (try? await Task.sleep(for: .seconds(seconds))) != nil
    }

    @MainActor
    private func runLoop() async {
        if reduceMotion {
            phase = 2
            typed = "4.50"
            categoryPicked = true
            return
        }
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.3)) {
                phase = 0
                typed = ""
                categoryPicked = false
                pressedKey = nil
            }
            guard await pause(1.1) else { return }

            withAnimation(.easeOut(duration: 0.45)) { fabPressed = true }
            guard await pause(0.45) else { return }
            fabPressed = false

            withAnimation(.easeInOut(duration: 0.35)) { phase = 1 }
            guard await pause(0.6) else { return }

            for key in keystrokes {
                withAnimation(.spring(duration: 0.2)) {
                    pressedKey = key
                    typed += key
                }
                guard await pause(0.22) else { return }
                withAnimation(.easeOut(duration: 0.15)) { pressedKey = nil }
                guard await pause(0.12) else { return }
            }
            guard await pause(0.5) else { return }

            withAnimation(.easeInOut(duration: 0.3)) { phase = 2 }
            guard await pause(0.4) else { return }
            withAnimation(.spring(duration: 0.4, bounce: 0.4)) { categoryPicked = true }
            guard await pause(0.9) else { return }

            withAnimation(.spring(duration: 0.45, bounce: 0.4)) { phase = 3 }
            guard await pause(2.0) else { return }
        }
    }
}

// MARK: - Wallets (card shuffle)

/// Two wallet cards that periodically swap, hinting at swipe-to-switch on Home.
struct OnboardingWalletsIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frontIndex = 0
    @State private var hintSway = false

    private struct DemoWallet {
        let nameKey: String
        let icon: String
        let colors: [Color]
        let amount: String
    }

    private let demoWallets = [
        DemoWallet(
            nameKey: "onboarding.wallet.defaultName",
            icon: "banknote.fill",
            colors: [.blue, .indigo],
            amount: "$128.50"
        ),
        DemoWallet(
            nameKey: "onboarding.demo.bank",
            icon: "building.columns.fill",
            colors: [.teal, .green],
            amount: "៛ 1,250,000"
        )
    ]

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                ForEach(demoWallets.indices, id: \.self) { index in
                    let isFront = frontIndex == index
                    walletCard(demoWallets[index])
                        .scaleEffect(isFront ? 1 : 0.88)
                        .offset(y: isFront ? 28 : -34)
                        .opacity(isFront ? 1 : 0.55)
                        .zIndex(isFront ? 1 : 0)
                }
            }
            .frame(height: 214)

            HStack(spacing: 8) {
                Image(systemName: "hand.draw.fill")
                Text("onboarding.demo.swipeHint".localized)
            }
            .font(.app(.footnote, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(.secondarySystemBackground)))
            .offset(x: hintSway ? 7 : -7)
        }
        .task { await runLoop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("onboarding.wallets.title".localized))
    }

    private func walletCard(_ wallet: DemoWallet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: wallet.icon)
                    .font(.app(.subheadline, weight: .semibold))
                Text(wallet.nameKey.localized)
                    .font(.app(.subheadline, weight: .semibold))
                Spacer()
                Image(systemName: "creditcard.fill")
                    .font(.app(.caption))
                    .opacity(0.6)
            }
            .foregroundStyle(.white.opacity(0.92))
            Spacer()
            Text(wallet.amount)
                .font(.app(.title, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(18)
        .frame(width: 256, height: 142)
        .background(
            ZStack {
                LinearGradient(colors: wallet.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 150, height: 150)
                    .offset(x: 96, y: -58)
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 90, height: 90)
                    .offset(x: -100, y: 62)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
        .shadow(color: (wallet.colors.first ?? .blue).opacity(0.35), radius: 16, y: 8)
    }

    @MainActor
    private func runLoop() async {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            hintSway = true
        }
        while !Task.isCancelled {
            guard (try? await Task.sleep(for: .seconds(2.4))) != nil else { return }
            withAnimation(.spring(duration: 0.7, bounce: 0.25)) {
                frontIndex = 1 - frontIndex
            }
        }
    }
}

// MARK: - Insights (chart + budget)

/// Mini analytics card: weekly bars grow in, a budget bar fills to 65%.
struct OnboardingInsightsIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var themeManager = ThemeManager.shared
    @State private var grow = false

    private let bars: [CGFloat] = [0.35, 0.55, 0.4, 0.95, 0.5, 0.7, 0.3]
    private let highlightIndex = 3

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("onboarding.demo.thisMonth".localized)
                        .font(.app(.caption2))
                        .foregroundStyle(.secondary)
                    Text("$412.80")
                        .font(.app(.title3, weight: .bold))
                }
                Spacer()
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: "chart.bar.fill")
                            .font(.app(.caption))
                            .foregroundStyle(Color.accentColor)
                    )
            }

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(bars.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == highlightIndex ? Color.accentColor : Color.accentColor.opacity(0.25))
                        .frame(height: grow ? bars[index] * 96 : 6)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .top) {
                            if index == highlightIndex {
                                Text("$86")
                                    .font(.app(.caption2, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.accentColor))
                                    .fixedSize()
                                    .offset(y: -24)
                                    .opacity(grow ? 1 : 0)
                                    .animation(.easeOut(duration: 0.4).delay(0.8), value: grow)
                            }
                        }
                        .animation(.spring(duration: 0.7, bounce: 0.3).delay(Double(index) * 0.07), value: grow)
                }
            }
            .frame(height: 112, alignment: .bottom)
            .padding(.top, 14)

            Divider()

            HStack(spacing: 10) {
                Circle()
                    .fill(Color.orange.opacity(0.18))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "fork.knife")
                            .font(.app(.caption))
                            .foregroundStyle(.orange)
                    )
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("onboarding.demo.foodBudget".localized)
                            .font(.app(.footnote, weight: .semibold))
                        Spacer()
                        Text("$35 " + "onboarding.demo.left".localized)
                            .font(.app(.caption2, weight: .semibold))
                            .foregroundStyle(themeManager.incomeColor)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemFill))
                            Capsule()
                                .fill(Color.orange)
                                .frame(width: geo.size.width * (grow ? 0.65 : 0))
                                .animation(.spring(duration: 0.9, bounce: 0.2).delay(0.5), value: grow)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .padding(18)
        .frame(width: 262)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.hero, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.10), radius: 22, y: 12)
        )
        .task { await runLoop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("onboarding.insights.title".localized))
    }

    @MainActor
    private func runLoop() async {
        if reduceMotion {
            grow = true
            return
        }
        while !Task.isCancelled {
            grow = true
            guard (try? await Task.sleep(for: .seconds(3.6))) != nil else { return }
            withAnimation(.easeIn(duration: 0.3)) { grow = false }
            guard (try? await Task.sleep(for: .seconds(0.7))) != nil else { return }
        }
    }
}

#Preview("Welcome") {
    OnboardingWelcomeIllustration()
}

#Preview("Track") {
    OnboardingTrackIllustration()
}

#Preview("Wallets") {
    OnboardingWalletsIllustration()
}

#Preview("Insights") {
    OnboardingInsightsIllustration()
}
