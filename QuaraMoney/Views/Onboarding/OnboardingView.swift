import SwiftUI
import SwiftData

/// Redesigned onboarding: pick a language, then a short guided tour of the
/// app's core flows (add a transaction, wallets, insights). Setup is kept to
/// a single choice — the main currency — everything else uses defaults and a
/// starter Cash wallet is created automatically.
struct OnboardingView: View {
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var currencyManager = CurrencyManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    private enum Stage {
        case language
        case tour
    }

    private enum TourPage: Int, CaseIterable {
        case welcome = 0
        case track
        case wallets
        case insights
        case ready
    }

    // TEMP DEBUG: allow jumping straight to a tour page for screenshots
    @State private var stage: Stage = ProcessInfo.processInfo.environment["ONB_PAGE"] != nil ? .tour : .language
    @State private var page: TourPage = TourPage(rawValue: Int(ProcessInfo.processInfo.environment["ONB_PAGE"] ?? "") ?? 0) ?? .welcome

    var body: some View {
        ZStack {
            background

            switch stage {
            case .language:
                languageStage
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .tour:
                tourStage
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
    }

    private var background: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            RadialGradient(
                colors: [Color.accentColor.opacity(0.12), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 440
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Language selection

    /// Shown before a language is chosen, so its fixed labels are bilingual.
    private var languageStage: some View {
        VStack(spacing: 0) {
            Spacer()

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 96, height: 96)
                .overlay(
                    Image(systemName: "wallet.pass.fill")
                        .font(.app(size: 42, weight: .medium))
                        .foregroundStyle(.white)
                )
                .shadow(color: Color.accentColor.opacity(0.35), radius: 18, y: 10)

            Text("QuaraMoney")
                .font(.app(.largeTitle, weight: .bold))
                .padding(.top, 20)

            VStack(spacing: 3) {
                Text("Choose your language")
                Text("ជ្រើសរើសភាសារបស់អ្នក")
            }
            .font(.app(.subheadline))
            .foregroundStyle(.secondary)
            .padding(.top, 24)

            VStack(spacing: 14) {
                languageCard(
                    title: "English",
                    subtitle: "Continue in English",
                    glyph: "Aa",
                    language: .english
                )
                languageCard(
                    title: "ភាសាខ្មែរ",
                    subtitle: "បន្តជាភាសាខ្មែរ",
                    glyph: "កខ",
                    language: .khmer
                )
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            Spacer()
            Spacer()
        }
    }

    private func languageCard(
        title: String,
        subtitle: String,
        glyph: String,
        language: LanguageManager.Language
    ) -> some View {
        Button {
            HapticManager.shared.selection()
            languageManager.selectedLanguage = language
            withAnimation(.spring(duration: 0.5)) {
                stage = .tour
            }
        } label: {
            HStack(spacing: 14) {
                Text(glyph)
                    .font(.app(.title3, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.accentColor.opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.app(.body, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Guided tour

    private var tourStage: some View {
        VStack(spacing: 0) {
            tourTopBar

            TabView(selection: $page) {
                tourPage(
                    title: "onboarding.welcomeTitle".localized,
                    description: "onboarding.welcomeDescription".localized
                ) {
                    OnboardingWelcomeIllustration()
                }
                .tag(TourPage.welcome)

                tourPage(
                    title: "onboarding.track.title".localized,
                    description: "onboarding.track.description".localized
                ) {
                    OnboardingTrackIllustration()
                }
                .tag(TourPage.track)

                tourPage(
                    title: "onboarding.wallets.title".localized,
                    description: "onboarding.wallets.description".localized
                ) {
                    OnboardingWalletsIllustration()
                }
                .tag(TourPage.wallets)

                tourPage(
                    title: "onboarding.insights.title".localized,
                    description: "onboarding.insights.description".localized
                ) {
                    OnboardingInsightsIllustration()
                }
                .tag(TourPage.insights)

                readyPage
                    .tag(TourPage.ready)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            Button {
                HapticManager.shared.impact(style: .light)
                if page == .ready {
                    completeOnboarding()
                } else {
                    withAnimation(.spring(duration: 0.45)) {
                        page = TourPage(rawValue: page.rawValue + 1) ?? .ready
                    }
                }
            } label: {
                Text(page == .ready ? "onboarding.getStarted".localized : "onboarding.continue".localized)
                    .font(.app(.body, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(.accentColor)
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private var tourTopBar: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(TourPage.allCases, id: \.self) { step in
                    Capsule()
                        .fill(step == page ? Color.accentColor : Color(.systemGray4))
                        .frame(width: step == page ? 22 : 7, height: 7)
                }
            }
            .animation(.spring(duration: 0.4), value: page)

            HStack {
                Button {
                    HapticManager.shared.selection()
                    if page == .welcome {
                        withAnimation(.spring(duration: 0.5)) {
                            stage = .language
                        }
                    } else {
                        withAnimation(.spring(duration: 0.45)) {
                            page = TourPage(rawValue: page.rawValue - 1) ?? .welcome
                        }
                    }
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.app(.subheadline, weight: .semibold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(Text(L10n.Common.back))

                Spacer()

                Button {
                    withAnimation(.spring(duration: 0.45)) {
                        page = .ready
                    }
                } label: {
                    Text("onboarding.skip".localized)
                        .font(.app(.subheadline, weight: .semibold))
                        .padding(.horizontal, 6)
                        .frame(height: 38)
                }
                .buttonStyle(.glass)
                .opacity(page == .ready ? 0 : 1)
                .disabled(page == .ready)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func tourPage<Illustration: View>(
        title: String,
        description: String,
        @ViewBuilder illustration: () -> Illustration
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            illustration()
                .frame(maxWidth: .infinity)

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Text(title)
                    .font(.app(.title, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(description)
                    .font(.app(.body))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 28)
        }
    }

    // MARK: - Ready page (single setup choice: currency)

    private var readyPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            readySeal

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Text("onboarding.finalTitle".localized)
                    .font(.app(.title, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("onboarding.ready.description".localized)
                    .font(.app(.body))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            HStack(spacing: 12) {
                currencyCard(code: "USD", symbol: "$", name: "onboarding.ready.usd".localized)
                currencyCard(code: "KHR", symbol: "៛", name: "onboarding.ready.khr".localized)
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)

            Text("onboarding.ready.changeLater".localized)
                .font(.app(.caption))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .padding(.horizontal, 32)

            Spacer(minLength: 28)
        }
        .onAppear {
            // The tour only offers the two market currencies; anything else
            // (stale UserDefaults value) falls back to USD.
            if !["USD", "KHR"].contains(currencyManager.preferredCurrencyCode) {
                currencyManager.preferredCurrencyCode = "USD"
            }
        }
    }

    private var readySeal: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.12))
                .frame(width: 150, height: 150)
            Circle()
                .fill(Color.green.opacity(0.18))
                .frame(width: 112, height: 112)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.green, Color.green.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 84, height: 84)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.app(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                )
                .shadow(color: Color.green.opacity(0.35), radius: 16, y: 8)
        }
        .accessibilityHidden(true)
    }

    private func currencyCard(code: String, symbol: String, name: String) -> some View {
        let isSelected = currencyManager.preferredCurrencyCode == code
        return Button {
            HapticManager.shared.selection()
            withAnimation(.spring(duration: 0.35)) {
                currencyManager.preferredCurrencyCode = code
            }
        } label: {
            VStack(spacing: 8) {
                Text(symbol)
                    .font(.app(.title2, weight: .bold))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12)))
                Text(name)
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(code)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Completion

    private func completeOnboarding() {
        createFirstWalletIfNeeded()
        HapticManager.shared.success()
        withAnimation {
            isOnboardingCompleted = true
        }
    }

    /// Creates a starter wallet in the chosen currency, named "Cash" in the
    /// chosen language. Skipped when wallets already exist (e.g. a reinstall
    /// whose store was restored or cloud-synced) — ContentView's create-wallet
    /// sheet remains as the fallback for stores that end up empty some other way.
    private func createFirstWalletIfNeeded() {
        let name = "onboarding.wallet.defaultName".localized
        let descriptor = FetchDescriptor<Wallet>(predicate: #Predicate { $0.deletedAt == nil })
        let existingCount = (try? modelContext.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        let wallet = Wallet(
            name: name,
            currencyCode: currencyManager.preferredCurrencyCode,
            icon: "wallet.pass",
            colorHex: "#007AFF"
        )
        modelContext.insert(wallet)
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
        } catch {
            #if DEBUG
            print("Error creating onboarding wallet: \(error)")
            #endif
        }
    }
}

#Preview {
    OnboardingView()
}
