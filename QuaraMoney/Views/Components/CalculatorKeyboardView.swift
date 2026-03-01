import SwiftUI

// MARK: - Safe Expression Evaluator
struct ExpressionEvaluator {
    static func evaluate(_ expression: String) -> Decimal? {
        guard !expression.isEmpty else { return nil }
        
        var expr = expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
        
        while let lastChar = expr.last, "+-*/.".contains(lastChar) {
            expr.removeLast()
        }
        
        guard !expr.isEmpty else { return nil }
        
        let validChars = CharacterSet(charactersIn: "0123456789.+-*/")
        guard expr.unicodeScalars.allSatisfy({ validChars.contains($0) }) else {
            return nil
        }
        
        return safeEvaluate(expr)
    }
    
    private static func safeEvaluate(_ expr: String) -> Decimal? {
        var index = expr.startIndex
        return parseExpression(expr, &index)
    }
    
    private static func parseExpression(_ expr: String, _ index: inout String.Index) -> Decimal? {
        guard var left = parseTerm(expr, &index) else { return nil }
        
        while index < expr.endIndex {
            let op = expr[index]
            if op == "+" {
                index = expr.index(after: index)
                guard let right = parseTerm(expr, &index) else { return nil }
                left = left + right
            } else if op == "-" {
                index = expr.index(after: index)
                guard let right = parseTerm(expr, &index) else { return nil }
                left = left - right
            } else {
                break
            }
        }
        return left
    }
    
    private static func parseTerm(_ expr: String, _ index: inout String.Index) -> Decimal? {
        guard var left = parseFactor(expr, &index) else { return nil }
        
        while index < expr.endIndex {
            let op = expr[index]
            if op == "*" {
                index = expr.index(after: index)
                guard let right = parseFactor(expr, &index) else { return nil }
                left = left * right
            } else if op == "/" {
                index = expr.index(after: index)
                guard let right = parseFactor(expr, &index) else { return nil }
                if right == 0 { return nil }
                left = left / right
            } else {
                break
            }
        }
        return left
    }
    
    private static func parseFactor(_ expr: String, _ index: inout String.Index) -> Decimal? {
        var isNegative = false
        if index < expr.endIndex && expr[index] == "-" {
            isNegative = true
            index = expr.index(after: index)
        }
        
        var numStr = ""
        while index < expr.endIndex {
            let char = expr[index]
            if char.isNumber || char == "." {
                numStr.append(char)
                index = expr.index(after: index)
            } else {
                break
            }
        }
        
        guard !numStr.isEmpty, let value = Decimal(string: numStr) else { return nil }
        return isNegative ? -value : value
    }
}

// MARK: - Adaptive Calculator Colors
private enum CalcColors {
    static let background = Color(.systemGroupedBackground) // Adaptive background
    static let numberButton = Color(.secondarySystemGroupedBackground) // White (light) / Dark Gray (dark)
    static let functionButton = Color(.tertiarySystemFill) // Adaptive gray
    static let operatorButton = Color.orange
}

// MARK: - Calculator Keyboard View
struct CalculatorKeyboardView: View {
    @Binding var expression: String
    @Binding var evaluatedAmount: Decimal
    let onDismiss: (() -> Void)?
    
    init(expression: Binding<String>, evaluatedAmount: Binding<Decimal>, onDismiss: (() -> Void)? = nil) {
        self._expression = expression
        self._evaluatedAmount = evaluatedAmount
        self.onDismiss = onDismiss
    }
    
    // Layout:
    // Row 1: ⌫, C, Done, ÷
    // Row 2: 7, 8, 9, ×
    // Row 3: 4, 5, 6, −
    // Row 4: 1, 2, 3, +
    // Row 5: 00, 0, ., =
    
    private let buttonSpacing: CGFloat = 4 // Compact spacing
    private let buttonHeight: CGFloat = 34 // More compact height
    
    var body: some View {
        VStack(spacing: buttonSpacing) {
            // Row 1: ⌫, C, Done, ÷
            HStack(spacing: buttonSpacing) {
                CalcButton(systemImage: "delete.backward", color: CalcColors.functionButton) { handleBackspace() }
                CalcButton(text: "C", color: CalcColors.functionButton) { handleClear() }
                CalcButton(text: "common.done".localized, color: CalcColors.functionButton) { finalizeAndDismiss() }
                CalcButton(text: "÷", color: CalcColors.operatorButton) { handleOperator("÷") }
            }
            
            // Row 2: 7, 8, 9, ×
            HStack(spacing: buttonSpacing) {
                CalcButton(text: "7", color: CalcColors.numberButton) { handleNumber("7") }
                CalcButton(text: "8", color: CalcColors.numberButton) { handleNumber("8") }
                CalcButton(text: "9", color: CalcColors.numberButton) { handleNumber("9") }
                CalcButton(text: "×", color: CalcColors.operatorButton) { handleOperator("×") }
            }
            
            // Row 3: 4, 5, 6, −
            HStack(spacing: buttonSpacing) {
                CalcButton(text: "4", color: CalcColors.numberButton) { handleNumber("4") }
                CalcButton(text: "5", color: CalcColors.numberButton) { handleNumber("5") }
                CalcButton(text: "6", color: CalcColors.numberButton) { handleNumber("6") }
                CalcButton(text: "−", color: CalcColors.operatorButton) { handleOperator("-") }
            }
            
            // Row 4: 1, 2, 3, +
            HStack(spacing: buttonSpacing) {
                CalcButton(text: "1", color: CalcColors.numberButton) { handleNumber("1") }
                CalcButton(text: "2", color: CalcColors.numberButton) { handleNumber("2") }
                CalcButton(text: "3", color: CalcColors.numberButton) { handleNumber("3") }
                CalcButton(text: "+", color: CalcColors.operatorButton) { handleOperator("+") }
            }
            
            // Row 5: 00, 0, ., =
            HStack(spacing: buttonSpacing) {
                CalcButton(text: "00", color: CalcColors.numberButton) { handleNumber("00") }
                CalcButton(text: "0", color: CalcColors.numberButton) { handleNumber("0") }
                CalcButton(text: ".", color: CalcColors.numberButton) { handleDecimal() }
                CalcButton(text: "=", color: CalcColors.operatorButton) { handleEquals() }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(CalcColors.background)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 12))
        .background {
            CalcColors.background
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .overlay(alignment: .top) {
            Divider()
        }
    }
    

    // MARK: - Button Handlers
    
    private func updateEvaluation() {
        if let result = ExpressionEvaluator.evaluate(expression) {
            evaluatedAmount = abs(result)
        } else if expression.isEmpty {
            evaluatedAmount = 0
        }
    }
    
    private func handleNumber(_ num: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        expression += num
        updateEvaluation()
    }
    
    private func handleOperator(_ op: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if expression.isEmpty {
            if op == "-" { 
                expression = "-" 
                updateEvaluation()
            }
            return
        }
        if expression.last == "." { return }
        if let lastChar = expression.last, "+-×÷".contains(lastChar) {
            expression.removeLast()
        }
        expression += op
        updateEvaluation()
    }
    
    private func handleDecimal() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if expression.isEmpty {
            expression = "0."
            updateEvaluation()
            return
        }
        
        let operators = CharacterSet(charactersIn: "+-×÷")
        let components = expression.unicodeScalars.split { operators.contains($0) }
        
        if let lastComponent = components.last {
            if !String(lastComponent).contains(".") {
                expression += "."
            }
        } else {
            expression += "0."
        }
        updateEvaluation()
    }
    
    private func handleClear() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        expression = ""
        evaluatedAmount = 0
    }
    
    private func handleBackspace() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if !expression.isEmpty {
            expression.removeLast()
            updateEvaluation()
        }
    }
    
    private func handleEquals() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let result = ExpressionEvaluator.evaluate(expression) {
            evaluatedAmount = abs(result)
            expression = formatResult(abs(result))
        }
    }
    
    private func finalizeAndDismiss() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let result = ExpressionEvaluator.evaluate(expression) {
            evaluatedAmount = abs(result)
            expression = formatResult(abs(result))
        }
        onDismiss?()
    }
    
    private func formatResult(_ value: Decimal) -> String {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        if doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", doubleValue)
        } else {
            return String(format: "%.2f", doubleValue)
        }
    }
}

// MARK: - Calculator Button (Native Style)
struct CalcButton: View {
    let text: String?
    let systemImage: String?
    let color: Color
    let action: () -> Void
    
    init(text: String, color: Color, action: @escaping () -> Void) {
        self.text = text
        self.systemImage = nil
        self.color = color
        self.action = action
    }
    
    init(systemImage: String, color: Color, action: @escaping () -> Void) {
        self.text = nil
        self.systemImage = systemImage
        self.color = color
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.app(.headline, weight: .medium))
                } else if let text = text {
                    Text(text)
                        .font(.app(.headline, weight: .medium))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34) // Compact height
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .foregroundColor(color == CalcColors.operatorButton ? .white : .primary) // Adaptive text color
    }
}

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @State private var expression = ""
        @State private var amount: Decimal = 0
        
        var body: some View {
            VStack {
                Text("Expression: \(expression.isEmpty ? "0" : expression)")
                    .font(.app(.largeTitle))
                Text("Amount: \(amount.formatted())")
                Spacer()
                CalculatorKeyboardView(
                    expression: $expression,
                    evaluatedAmount: $amount,
                    onDismiss: { print("Dismiss") }
                )
            }
            .background(Color(.systemBackground))
        }
    }
    return PreviewWrapper()
}
