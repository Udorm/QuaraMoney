import SwiftUI

struct OnboardingView: View {
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false
    @ObservedObject private var currencyManager = CurrencyManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    
    @State private var currentStep: OnboardingStep = .welcome
    @State private var searchText: String = ""
    @Namespace private var animationNamespace
    
    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case currency = 1
        case theme = 2
        case final = 3
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack {
                // Progress Indicator
                HStack(spacing: 8) {
                    ForEach(OnboardingStep.allCases, id: \.self) { step in
                        Capsule()
                            .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color(.systemGray4))
                            .frame(width: step == currentStep ? 24 : 8, height: 8)
                            .animation(.spring(), value: currentStep)
                    }
                }
                .padding(.top, 20)
                
                Spacer()
                
                // Content
                Group {
                    switch currentStep {
                    case .welcome:
                        welcomeView
                    case .currency:
                        currencyView
                    case .theme:
                        themeView
                    case .final:
                        finalView
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(currentStep)
                
                Spacer()
                
                // Navigation Buttons
                HStack {
                    if currentStep != .welcome {
                        Button(L10n.Common.back) {
                            withAnimation {
                                if let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) {
                                    currentStep = prev
                                }
                            }
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
                                currentStep = next
                            } else {
                                // Complete Onboarding
                                completeOnboarding()
                            }
                        }
                    }) {
                        Text(currentStep == .final ? L10n.Onboarding.getStarted : L10n.Common.next)
                            .font(.app(.body, weight: .bold))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 20)
            }
        }
    }
    
    // MARK: - Steps Views
    
    private var welcomeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wallet.pass.fill") // Placeholder for App Icon
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.accentColor)
                .padding(.bottom, 20)
            
                .padding(.bottom, 20)
            
            Text(L10n.Onboarding.welcomeTitle)
                .font(.app(.largeTitle, weight: .bold))
                .multilineTextAlignment(.center)
            
            Text(L10n.Onboarding.welcomeDescription)
                .font(.app(.body))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
    
    private var currencyView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(L10n.Onboarding.selectCurrency)
                    .font(.app(.title, weight: .bold))
                
                Text(L10n.Onboarding.currencyDescription)
                    .font(.app(.subheadline))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(L10n.Common.search, text: $searchText)
                    .font(.app(.body))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.bottom, 16)
            
            List {
                if searchText.isEmpty {
                    Section(header: Text("Common Currencies")) {
                        ForEach(["USD", "KHR", "EUR", "GBP", "JPY"], id: \.self) { code in
                            currencyRow(for: code)
                        }
                    }
                }
                
                Section(header: Text(searchText.isEmpty ? "All Currencies" : "Search Results")) {
                    ForEach(filteredCurrencies, id: \.id) { currency in
                        currencyRow(for: currency.id)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
    
    private var filteredCurrencies: [CurrencyManager.CurrencyInfo] {
        if searchText.isEmpty {
            return currencyManager.availableCurrencyInfos
        } else {
            return currencyManager.availableCurrencyInfos.filter { 
                $0.searchString.contains(searchText.lowercased())
            }
        }
    }
    
    private func currencyRow(for code: String) -> some View {
        let isSelected = currencyManager.preferredCurrencyCode == code
        let info = currencyManager.availableCurrencyInfos.first { $0.id == code }
        
        return Button(action: {
            withAnimation(.spring()) {
                currencyManager.preferredCurrencyCode = code
            }
        }) {
            HStack(spacing: 16) {
                // Symbol Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color(.systemGray6))
                        .frame(width: 44, height: 44)
                    
                    Text(info?.symbol ?? code)
                        .font(.app(.headline, weight: .bold))
                        .foregroundColor(isSelected ? .white : .primary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(info?.name ?? code)
                        .font(.app(.body, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(code)
                        .font(.app(.caption))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.title3)
                }
            }
            .padding(.vertical, 8)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
    }
    
    private var themeView: some View {
        ScrollView {
            VStack(spacing: 32) {
                Text(L10n.Onboarding.personalizeColors)
                    .font(.app(.title, weight: .bold))
                
                Text(L10n.Onboarding.themeDescription)
                    .font(.app(.subheadline))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.Onboarding.incomeColor)
                        .font(.app(.headline))
                    
                    ColorPickerView(selectedColorHex: $themeManager.incomeColorHex)
                        .frame(height: 150)
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.Onboarding.expenseColor)
                        .font(.app(.headline))
                    
                    ColorPickerView(selectedColorHex: $themeManager.expenseColorHex)
                        .frame(height: 150)
                }
            }
            .padding()
        }
    }
    
    private var finalView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.green)
                .padding(.bottom, 20)
            
                .padding(.bottom, 20)
            
            Text(L10n.Onboarding.finalTitle)
                .font(.app(.largeTitle, weight: .bold))
            
            Text(L10n.Onboarding.finalDescription)
                .font(.app(.body))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
    
    private func completeOnboarding() {
        withAnimation {
            isOnboardingCompleted = true
        }
    }
}

#Preview {
    OnboardingView()
}
