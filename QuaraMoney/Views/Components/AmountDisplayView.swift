import SwiftUI

struct AmountDisplayView: View {
    let amount: Decimal
    @Binding var currencyCode: String
    let expression: String
    let isEditing: Bool
    var exchangeRateInfo: String? = nil
    
    init(amount: Decimal, currencyCode: Binding<String>, expression: String = "", isEditing: Bool = false, exchangeRateInfo: String? = nil) {
        self.amount = amount
        self._currencyCode = currencyCode
        self.expression = expression
        self.isEditing = isEditing
        self.exchangeRateInfo = exchangeRateInfo
    }
    
    /// Display the raw expression when editing, formatted amount when finalized
    private var displayText: String {
        if isEditing && !expression.isEmpty {
            // Show expression with thousand separators for readability
            return formatExpressionForDisplay(expression)
        } else if amount > 0 {
            return formatAmount(amount)
        } else {
            return "0"
        }
    }
    
    /// Format expression: add thousand separators to numbers while preserving operators
    private func formatExpressionForDisplay(_ expr: String) -> String {
        // Split by operators, format each number, rejoin
        var result = ""
        var currentNumber = ""
        
        for char in expr {
            if char.isNumber || char == "." {
                currentNumber.append(char)
            } else if "+-×÷".contains(char) {
                if !currentNumber.isEmpty {
                    result += formatNumberString(currentNumber)
                    currentNumber = ""
                }
                result.append(char)
            }
        }
        
        // Append remaining number
        if !currentNumber.isEmpty {
            result += formatNumberString(currentNumber)
        }
        
        return result
    }
    
    /// Format a number string with thousand separators
    private func formatNumberString(_ numStr: String) -> String {
        // Split by decimal
        let parts = numStr.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let intPart = parts.first else { return numStr }
        
        // Format integer part with thousand separators
        let reversed = String(intPart.reversed())
        var formatted = ""
        for (index, char) in reversed.enumerated() {
            if index > 0 && index % 3 == 0 {
                formatted.append(",")
            }
            formatted.append(char)
        }
        let intFormatted = String(formatted.reversed())
        
        // Add decimal part if exists
        if parts.count > 1 {
            let decimalPart = parts[1]
            return "\(intFormatted).\(decimalPart)"
        } else if numStr.hasSuffix(".") {
            return "\(intFormatted)."
        }
        
        return intFormatted
    }
    
    /// Format final amount with 2 decimal places
    private func formatAmount(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        return formatter.string(from: NSNumber(value: doubleValue)) ?? "0"
    }
    
    /// Check if expression has operators (showing pending calculation)
    private var hasOperators: Bool {
        let operators = CharacterSet(charactersIn: "+-×÷")
        return expression.rangeOfCharacter(from: operators) != nil
    }
    
    @State private var showCurrencyPicker = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Currency Selection & Rate
            HStack(spacing: 8) {
                Button {
                    showCurrencyPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(currencyCode)
                            .font(.app(.subheadline, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.secondarySystemBackground))
                    .foregroundColor(.primary)
                    .clipShape(Capsule())
                }
                .sheet(isPresented: $showCurrencyPicker) {
                    NavigationStack {
                        CurrencySelectionView(selection: $currencyCode)
                    }
                    .presentationDetents([.medium, .large])
                }
                
                if let info = exchangeRateInfo {
                    Text(info)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            
            // Main amount/expression display
            HStack(alignment: .center, spacing: 4) {
                Text(displayText)
                    .font(.app(size: 48, weight: .bold))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    // Use ternary for color based on amount/expression
                    .foregroundStyle((expression.isEmpty && amount == 0) ? Color.secondary.opacity(0.5) : Color.primary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.1), value: displayText)
                
                // Blinking cursor when editing
                if isEditing {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 32)
                        .opacity(1)
                }
            }
            
            // Calculation preview when operators present
            if hasOperators && amount > 0 {
                Text("= \(formatAmount(amount))")
                    .font(.app(.callout))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.15), value: hasOperators)
    }
}

// MARK: - Preview
#Preview("Editing - No Decimal") {
    AmountDisplayView(
        amount: 1234,
        currencyCode: .constant("USD"),
        expression: "1234",
        isEditing: true
    )
}

#Preview("Editing - With Decimal") {
    AmountDisplayView(
        amount: 123.45,
        currencyCode: .constant("USD"),
        expression: "123.45",
        isEditing: true
    )
}

#Preview("Editing - Expression") {
    AmountDisplayView(
        amount: 250,
        currencyCode: .constant("USD"),
        expression: "150+100",
        isEditing: true
    )
}

#Preview("Finalized") {
    AmountDisplayView(
        amount: 1234.56,
        currencyCode: .constant("USD"),
        expression: "",
        isEditing: false
    )
}

#Preview("Empty") {
    AmountDisplayView(
        amount: 0,
        currencyCode: .constant("USD"),
        expression: "",
        isEditing: true
    )
}
