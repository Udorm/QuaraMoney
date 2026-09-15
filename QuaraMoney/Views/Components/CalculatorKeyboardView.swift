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
    /// Value access goes through closures, never `@Binding`.
    ///
    /// Installing a `@Binding` makes SwiftUI read the bound value while the
    /// *caller's* body is being evaluated, which registers the caller as an
    /// observer of the amount it edits. On the compact entry screen that meant
    /// every digit invalidated the keypad wrapper, rebuilt this view, and with
    /// it all twenty keys. Nothing below reads a value during `body`; the
    /// handlers read and write at event time instead.
    private let readExpression: () -> String
    private let writeExpression: (String) -> Void
    private let writeEvaluatedAmount: (Decimal) -> Void
    let onDismiss: (() -> Void)?
    /// When set, the keypad runs in persistent mode: "Done" is replaced by "="
    /// in the function row and the bottom-right key becomes a prominent Save
    /// key (the keypad never dismisses, so save lives in the thumb zone).
    let onSave: (() -> Void)?
    /// Deferred rather than a plain `Bool` so the validity read happens inside
    /// `SaveKey`'s body instead of the caller's. Callers derive it from the
    /// amount, so evaluating it up here made every keystroke rebuild all twenty
    /// keys; now it only rebuilds the one key that can actually change.
    let isSaveDisabled: () -> Bool

    /// Binding-based entry point, kept for callers whose amount lives in local
    /// `@State`. Prefer the closure initializer below when the value lives on an
    /// `@Observable` model — see the note on `readExpression`.
    init(
        expression: Binding<String>,
        evaluatedAmount: Binding<Decimal>,
        onDismiss: (() -> Void)? = nil,
        onSave: (() -> Void)? = nil,
        isSaveDisabled: @autoclosure @escaping () -> Bool = false
    ) {
        self.init(
            readExpression: { expression.wrappedValue },
            writeExpression: { expression.wrappedValue = $0 },
            writeEvaluatedAmount: { evaluatedAmount.wrappedValue = $0 },
            onDismiss: onDismiss,
            onSave: onSave,
            isSaveDisabled: isSaveDisabled
        )
    }

    init(
        readExpression: @escaping () -> String,
        writeExpression: @escaping (String) -> Void,
        writeEvaluatedAmount: @escaping (Decimal) -> Void,
        onDismiss: (() -> Void)? = nil,
        onSave: (() -> Void)? = nil,
        isSaveDisabled: @escaping () -> Bool = { false }
    ) {
        self.readExpression = readExpression
        self.writeExpression = writeExpression
        self.writeEvaluatedAmount = writeEvaluatedAmount
        self.onDismiss = onDismiss
        self.onSave = onSave
        self.isSaveDisabled = isSaveDisabled
    }

    // Layout:
    // Row 1: ⌫, C, Done, ÷        (persistent mode: ⌫, C, =, ÷)
    // Row 2: 7, 8, 9, ×
    // Row 3: 4, 5, 6, −
    // Row 4: 1, 2, 3, +
    // Row 5: 00, 0, ., =          (persistent mode: 00, 0, ., ✓ Save)
    
    private let buttonSpacing: CGFloat = 4 // Compact spacing
    private let buttonHeight: CGFloat = 34 // More compact height
    
    var body: some View {
        VStack(spacing: buttonSpacing) {
            // Row 1: ⌫, C, Done/=, ÷
            HStack(spacing: buttonSpacing) {
                CalcButton(systemImage: "delete.backward", color: CalcColors.functionButton) { handleBackspace() }.equatable()
                CalcButton(text: "C", color: CalcColors.functionButton) { handleClear() }.equatable()
                if onSave == nil {
                    CalcButton(text: "common.done".localized, color: CalcColors.functionButton) { finalizeAndDismiss() }.equatable()
                } else {
                    CalcButton(text: "=", color: CalcColors.functionButton) { handleEquals() }.equatable()
                }
                CalcButton(text: "÷", color: CalcColors.operatorButton) { handleOperator("÷") }.equatable()
            }
            
            // Row 2: 7, 8, 9, ×
            HStack(spacing: buttonSpacing) {
                CalcButton(text: "7", color: CalcColors.numberButton) { handleNumber("7") }.equatable()
                CalcButton(text: "8", color: CalcColors.numberButton) { handleNumber("8") }.equatable()
                CalcButton(text: "9", color: CalcColors.numberButton) { handleNumber("9") }.equatable()
                CalcButton(text: "×", color: CalcColors.operatorButton) { handleOperator("×") }.equatable()
            }
            
            // Row 3: 4, 5, 6, −
            HStack(spacing: buttonSpacing) {
                CalcButton(text: "4", color: CalcColors.numberButton) { handleNumber("4") }.equatable()
                CalcButton(text: "5", color: CalcColors.numberButton) { handleNumber("5") }.equatable()
                CalcButton(text: "6", color: CalcColors.numberButton) { handleNumber("6") }.equatable()
                CalcButton(text: "−", color: CalcColors.operatorButton) { handleOperator("-") }.equatable()
            }
            
            // Row 4: 1, 2, 3, +
            HStack(spacing: buttonSpacing) {
                CalcButton(text: "1", color: CalcColors.numberButton) { handleNumber("1") }.equatable()
                CalcButton(text: "2", color: CalcColors.numberButton) { handleNumber("2") }.equatable()
                CalcButton(text: "3", color: CalcColors.numberButton) { handleNumber("3") }.equatable()
                CalcButton(text: "+", color: CalcColors.operatorButton) { handleOperator("+") }.equatable()
            }
            
            // Row 5: 00, 0, ., = (or ✓ Save in persistent mode)
            HStack(spacing: buttonSpacing) {
                CalcButton(text: "00", color: CalcColors.numberButton) { handleNumber("00") }.equatable()
                CalcButton(text: "0", color: CalcColors.numberButton) { handleNumber("0") }.equatable()
                CalcButton(text: ".", color: CalcColors.numberButton) { handleDecimal() }.equatable()
                if let onSave {
                    SaveKey(isDisabled: isSaveDisabled, action: onSave)
                } else {
                    CalcButton(text: "=", color: CalcColors.operatorButton) { handleEquals() }.equatable()
                }
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
    
    private func updateEvaluation(_ expression: String) {
        if let result = ExpressionEvaluator.evaluate(expression) {
            writeEvaluatedAmount(abs(result))
        } else if expression.isEmpty {
            writeEvaluatedAmount(0)
        }
    }

    /// Writes the new expression and re-evaluates it in one step. The handlers
    /// below all follow read → transform → commit, because there is no stored
    /// binding to mutate in place any more.
    private func commit(_ expression: String) {
        writeExpression(expression)
        updateEvaluation(expression)
    }

    private func handleNumber(_ num: String) {
        HapticManager.shared.impact(style: .light)
        commit(readExpression() + num)
    }

    private func handleOperator(_ op: String) {
        HapticManager.shared.impact(style: .light)
        var expression = readExpression()
        if expression.isEmpty {
            if op == "-" {
                commit("-")
            }
            return
        }
        if expression.last == "." { return }
        if let lastChar = expression.last, "+-×÷".contains(lastChar) {
            expression.removeLast()
        }
        commit(expression + op)
    }

    private func handleDecimal() {
        HapticManager.shared.impact(style: .light)
        let expression = readExpression()
        if expression.isEmpty {
            commit("0.")
            return
        }

        let operators = CharacterSet(charactersIn: "+-×÷")
        let components = expression.unicodeScalars.split { operators.contains($0) }

        if let lastComponent = components.last {
            if !String(lastComponent).contains(".") {
                commit(expression + ".")
            }
        } else {
            commit(expression + "0.")
        }
    }

    private func handleClear() {
        HapticManager.shared.impact(style: .medium)
        writeExpression("")
        writeEvaluatedAmount(0)
    }

    private func handleBackspace() {
        HapticManager.shared.impact(style: .light)
        var expression = readExpression()
        if !expression.isEmpty {
            expression.removeLast()
            commit(expression)
        }
    }

    private func handleEquals() {
        HapticManager.shared.impact(style: .medium)
        if let result = ExpressionEvaluator.evaluate(readExpression()) {
            writeEvaluatedAmount(abs(result))
            writeExpression(formatResult(abs(result)))
        }
    }

    private func finalizeAndDismiss() {
        HapticManager.shared.impact(style: .medium)
        if let result = ExpressionEvaluator.evaluate(readExpression()) {
            writeEvaluatedAmount(abs(result))
            writeExpression(formatResult(abs(result)))
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

// MARK: - Save Key (isolated validity reader)

/// The prominent save key in persistent mode. Its own `View` purely so the
/// `isDisabled` read — which depends on the amount the keypad is editing —
/// lands here rather than in `CalculatorKeyboardView.body`, leaving the other
/// nineteen keys untouched by a keystroke.
private struct SaveKey: View {
    let isDisabled: () -> Bool
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.shared.impact(style: .medium)
            action()
        } label: {
            Image(systemName: "checkmark")
                .appFont(.headline, weight: .semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .foregroundColor(.white)
        .disabled(isDisabled())
        .accessibilityLabel("common.save".localized)
    }
}

// MARK: - Calculator Button (Native Style)

/// `Equatable` so a re-evaluated keypad doesn't rebuild all twenty keys. A key's
/// appearance is fully described by its label and colour, and its action is a
/// pure function of that label, so the closure is deliberately excluded from the
/// comparison. Applied through `.equatable()` at the use sites.
struct CalcButton: View, Equatable {
    let text: String?
    let systemImage: String?
    let color: Color
    let action: () -> Void

    static func == (lhs: CalcButton, rhs: CalcButton) -> Bool {
        lhs.text == rhs.text && lhs.systemImage == rhs.systemImage && lhs.color == rhs.color
    }
    
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
                        .appFont(.headline, weight: .medium)
                } else if let text = text {
                    Text(text)
                        .appFont(.headline, weight: .medium)
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
                    .appFont(.largeTitle)
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
