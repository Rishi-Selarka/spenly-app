import SwiftUI

struct BalanceCard: View {
    let title: String
    let amount: Double
    let trend: Double
    let color: Color
    let icon: String
    var isCompact: Bool = false
    var showIcon: Bool = true
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    private var amountColor: Color {
        switch title {
        case "Income":
            return .green
        case "Expenses":
            return .red
        default:
            return .primary
        }
    }
    
    var body: some View {
        VStack(spacing: isCompact ? 8 : 12) {
            HStack {
                if showIcon && !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: isCompact ? 18 : 24))
                        .foregroundColor(color)
                }
                
                if !showIcon {
                    Spacer(minLength: 0)
                }
                
                Spacer()
                
                if trend != 0 {
                    HStack(spacing: 4) {
                        Image(systemName: trend > 0 ? "arrow.up.right" : "arrow.down.right")
                        Text("\(abs(trend), specifier: "%.1f")%")
                            .font(selectedFont.font(size: 12))
                    }
                    .foregroundColor(trend > 0 ? .green : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(trend > 0 ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    )
                }
            }
            
            VStack(spacing: 4) {
                Text(title)
                    .font(selectedFont.font(size: isCompact ? 14 : 16))
                    .foregroundColor(.secondary)
                
                Text(CurrencyFormatter.format(amount, currency: selectedCurrency))
                    .font(selectedFont.font(size: isCompact ? 20 : 24))
                    .fontWeight(.semibold)
                    .foregroundColor(amountColor)
            }
        }
        .padding(16)
                .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: color.opacity(0.1), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(color.opacity(0.1), lineWidth: 1)
        )
    }
}
