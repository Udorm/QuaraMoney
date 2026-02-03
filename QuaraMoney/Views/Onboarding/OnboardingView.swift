import SwiftUI

struct OnboardingView: View {
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false
    @ObservedObject private var currencyManager = CurrencyManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    
    @State private var currentStep: OnboardingStep = .welcome
    @Namespace private var animationNamespace
    
    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case currency = 1
        case theme = 2
        case final = 3
    }
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack {
                // Progress Indicator
                HStack(spacing: 8) {
                    ForEach(OnboardingStep.allCases, id: \.self) { step in
                        Capsule()
                            .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
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
                        Button("Back") {
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
                        Text(currentStep == .final ? "Get Started" : "Next")
                            .fontWeight(.bold)
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
            
            Text("Welcome to QuaraMoney")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text("Take control of your finances.\nTrack expenses, budget smarter, and save more.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
    
    private var currencyView: some View {
        VStack(spacing: 24) {
            Text("Select Currency")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Choose your default currency for reporting.\nYou can change this later.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 16) {
                    ForEach(currencyManager.availableCurrencies, id: \.self) { currency in
                        Button(action: {
                            withAnimation {
                                currencyManager.preferredCurrencyCode = currency
                            }
                        }) {
                            VStack {
                                Text(currency)
                                    .font(.headline)
                                    .foregroundColor(currencyManager.preferredCurrencyCode == currency ? .white : .primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(currencyManager.preferredCurrencyCode == currency ? Color.accentColor : Color(UIColor.secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.accentColor, lineWidth: currencyManager.preferredCurrencyCode == currency ? 0 : 0)
                            )
                        }
                    }
                }
                .padding()
            }
        }
        .padding()
    }
    
    private var themeView: some View {
        ScrollView {
            VStack(spacing: 32) {
                Text("Personalize Colors")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Choose colors for your income and expenses.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Income Color")
                        .font(.headline)
                    
                    ColorPickerView(selectedColorHex: $themeManager.incomeColorHex)
                        .frame(height: 150)
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Expense Color")
                        .font(.headline)
                    
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
            
            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Let's create your first wallet to get started.")
                .font(.body)
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
