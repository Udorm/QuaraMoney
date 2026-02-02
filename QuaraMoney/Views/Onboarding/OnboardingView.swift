import SwiftUI
import SwiftData

struct OnboardingView: View {
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted: Bool = false
    @Environment(\.modelContext) private var modelContext // Added modelContext
    @ObservedObject private var currencyManager = CurrencyManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    
    @State private var currentStep: OnboardingStep = .welcome
    @State private var isMovingBack = false
    @Namespace private var animationNamespace

    
    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case currency = 1
        case theme = 2
        case categories = 3 // Added categories step
        case final = 4
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
                    case .categories: // Added categories view case
                        categoriesView
                    case .final:
                        finalView
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: isMovingBack ? .leading : .trailing).combined(with: .opacity),
                    removal: .move(edge: isMovingBack ? .trailing : .leading).combined(with: .opacity)
                ))
                .id(currentStep)
                
                Spacer()
                
                // Navigation Buttons
                HStack {
                    if currentStep != .welcome {
                        Button("Back") {
                            isMovingBack = true
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
                        isMovingBack = false
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
    
    private var categoriesView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Default Categories")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("We've set up some common categories for you.\nYou can edit these later.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(PredefinedCategory.defaults, id: \.name) { category in
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: category.colorHex)?.opacity(0.1) ?? .gray.opacity(0.1))
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: category.icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color(hex: category.colorHex) ?? .gray)
                            }
                            
                            Text(category.name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(height: 32, alignment: .top) // Fixed height for text
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 4)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                    }
                }
                .padding()
            }
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
        // Create Default Categories
        let existingCategories = try? modelContext.fetch(FetchDescriptor<Category>())
        
        if existingCategories?.isEmpty ?? true {
            for category in PredefinedCategory.defaults {
                let newCategory = Category(
                    name: category.name,
                    icon: category.icon,
                    colorHex: category.colorHex,
                    type: category.type
                )
                modelContext.insert(newCategory)
            }
        }
        
        withAnimation {
            isOnboardingCompleted = true
        }
    }
}

#Preview {
    OnboardingView()
}
