import SwiftUI

struct CalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isShowing: Bool
    @State private var offset = CGSize.zero
    @GestureState private var dragOffset = CGSize.zero
    @State private var displayValue = "0"
    @State private var currentNumber = 0.0
    @State private var previousNumber = 0.0
    @State private var currentOperation: Operation? = nil
    @State private var newNumber = true
    @AppStorage("calculatorOpacity") private var opacity = 1.0
    @AppStorage("showCalculatorOpacity") private var showOpacityControl = false
    @State private var screenBounds = UIScreen.main.bounds
    @State private var velocity = CGSize.zero
    @State private var isDragging = false
    @State private var buttonPressed: CalculatorButton? = nil
    
    enum Operation {
        case add, subtract, multiply, divide
    }
    
    let buttons: [[CalculatorButton]] = [
        [.clear, .plusMinus, .percent, .divide],
        [.seven, .eight, .nine, .multiply],
        [.four, .five, .six, .subtract],
        [.one, .two, .three, .add],
        [.zero, .decimal, .equals]
    ]
    
    var body: some View {
        VStack(spacing: 6) {
            // Top bar - only close button
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowing = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 12)
            
            // Enhanced Display with better performance
            HStack {
                Spacer()
                Text(displayValue)
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 12)
                    .drawingGroup() // Performance optimization for text rendering
            }
            .padding(.trailing, 4)
            .padding(.bottom, 8)
            
            // Optimized Buttons Grid
            VStack(spacing: 8) {
                ForEach(Array(buttons.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 8) {
                        ForEach(Array(row.enumerated()), id: \.offset) { buttonIndex, button in
                            CalculatorButtonView(
                                button: button,
                                isPressed: buttonPressed == button,
                                action: {
                                    withAnimation(.easeInOut(duration: 0.1)) {
                                        buttonPressed = button
                                    }
                                    
                                    // Add haptic feedback for better UX
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    
                                    // Delay to show press animation
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        self.buttonTapped(button)
                                        buttonPressed = nil
                                    }
                                }
                            )
                            .frame(
                                width: button == .zero ? 96 : 45,
                                height: 45
                            )
                        }
                    }
                }
            }
            .drawingGroup() // Performance boost for button rendering
        }
        .padding(8)
        .background(Color.black.opacity(opacity))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                    if !isDragging {
                        isDragging = true
                    }
                }
                .onChanged { value in
                    velocity = value.velocity
                }
                .onEnded { value in
                    isDragging = false
                    
                    let predictedEndLocation = CGPoint(
                        x: offset.width + value.translation.width,
                        y: offset.height + value.translation.height
                    )
                    
                    // Enhanced velocity-based movement with better physics
                    let velocityMultiplier: CGFloat = 0.12
                    let projectedX = predictedEndLocation.x + (value.velocity.width * velocityMultiplier)
                    let projectedY = predictedEndLocation.y + (value.velocity.height * velocityMultiplier)
                    
                    // Improved bounds checking with better margins
                    let margin: CGFloat = 110
                    let finalX = min(max(projectedX, -screenBounds.width/2 + margin), screenBounds.width/2 - margin)
                    let finalY = min(max(projectedY, -screenBounds.height/2 + margin), screenBounds.height/2 - margin)
                    
                    // Optimized spring animation with better responsiveness
                    let velocityMagnitude = sqrt(pow(value.velocity.width, 2) + pow(value.velocity.height, 2))
                    
                    withAnimation(.interpolatingSpring(
                        mass: 0.8,
                        stiffness: 180,
                        damping: 16,
                        initialVelocity: velocityMagnitude / 600
                    )) {
                        offset = CGSize(width: finalX, height: finalY)
                    }
                }
        )
        .animation(.interpolatingSpring(
            mass: 0.6,
            stiffness: 400,
            damping: 22,
            initialVelocity: 0
        ), value: isDragging)
        .frame(width: 200)
    }
    
    private func buttonTapped(_ button: CalculatorButton) {
        switch button {
        case .number(let value):
            if newNumber {
                displayValue = String(value)
                newNumber = false
            } else {
                // Limit display length for better performance
                if displayValue.count < 12 {
                    displayValue += String(value)
                }
            }
            currentNumber = Double(displayValue) ?? 0
            
        case .clear:
            displayValue = "0"
            currentNumber = 0
            previousNumber = 0
            currentOperation = nil
            newNumber = true
            
        case .equals:
            calculateResult()
            
        case .decimal:
            if !displayValue.contains(".") && displayValue.count < 11 {
                displayValue += "."
            }
            
        case .delete:
            if displayValue.count > 1 {
                displayValue.removeLast()
            } else {
                displayValue = "0"
                newNumber = true
            }
            currentNumber = Double(displayValue) ?? 0
            
        case .plusMinus:
            if let number = Double(displayValue) {
                let result = -number
                displayValue = formatNumber(result)
                currentNumber = result
            }
            
        case .percent:
            if let number = Double(displayValue) {
                let percentValue = number / 100.0
                displayValue = formatNumber(percentValue)
                currentNumber = percentValue
            }
            
        case .operation(let op):
            if let current = Double(displayValue) {
                if currentOperation != nil {
                    calculateResult()
                }
                previousNumber = current
                currentOperation = op
                newNumber = true
            }
        }
    }
    
    // Optimized number formatting for better performance
    private func formatNumber(_ number: Double) -> String {
        // Handle special cases for better UX
        if number.isInfinite {
            return "Error"
        }
        if number.isNaN {
            return "Error"
        }
        
        // Format with appropriate precision
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        formatter.usesGroupingSeparator = false
        
        return formatter.string(from: NSNumber(value: number)) ?? String(format: "%.8g", number)
    }
    
    private func calculateResult() {
        guard let operation = currentOperation else { return }
        
        let result: Double
        switch operation {
        case .add:
            result = previousNumber + currentNumber
        case .subtract:
            result = previousNumber - currentNumber
        case .multiply:
            result = previousNumber * currentNumber
        case .divide:
            if currentNumber != 0 {
                result = previousNumber / currentNumber
            } else {
                displayValue = "Error"
                currentOperation = nil
                newNumber = true
                return
            }
        }
        
        currentNumber = result
        displayValue = formatNumber(result)
        currentOperation = nil
        newNumber = true
    }
}

enum CalculatorButton: Hashable {
    case number(Int)
    case operation(CalculatorView.Operation)
    case clear, delete, percent, decimal, equals, plusMinus
    
    static let zero = CalculatorButton.number(0)
    static let one = CalculatorButton.number(1)
    static let two = CalculatorButton.number(2)
    static let three = CalculatorButton.number(3)
    static let four = CalculatorButton.number(4)
    static let five = CalculatorButton.number(5)
    static let six = CalculatorButton.number(6)
    static let seven = CalculatorButton.number(7)
    static let eight = CalculatorButton.number(8)
    static let nine = CalculatorButton.number(9)
    
    static let multiply = CalculatorButton.operation(.multiply)
    static let divide = CalculatorButton.operation(.divide)
    static let add = CalculatorButton.operation(.add)
    static let subtract = CalculatorButton.operation(.subtract)
}

struct CalculatorButtonView: View {
    let button: CalculatorButton
    let isPressed: Bool
    let action: () -> Void
    
    // Pre-computed properties for better performance
    private var buttonShape: AnyShape {
        button == .zero ? AnyShape(Capsule()) : AnyShape(Circle())
    }
    
    private var buttonTitle: String {
        switch button {
        case .number(let value): return String(value)
        case .operation(let op):
            switch op {
            case .add: return "+"
            case .subtract: return "−"
            case .multiply: return "×"
            case .divide: return "÷"
            }
        case .clear: return "C"
        case .delete: return "⌫"
        case .percent: return "%"
        case .decimal: return "."
        case .equals: return "="
        case .plusMinus: return "+/-"
        }
    }
    
    private var buttonColor: Color {
        switch button {
        case .operation: return .orange
        case .clear, .plusMinus, .percent: return Color(.lightGray)
        default: return Color(.darkGray)
        }
    }
    
    var body: some View {
        Button(action: action) {
            Text(buttonTitle)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    buttonColor
                        .brightness(isPressed ? -0.2 : 0.0)
                        .animation(.easeInOut(duration: 0.1), value: isPressed)
                )
                .clipShape(buttonShape)
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle()) // Remove default button animations
    }
}
