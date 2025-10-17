import Foundation

struct CurrencyFormatter {
    // Static shared formatter to avoid repeated creation
    private static let sharedFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    
    static func format(_ amount: Double, currency: Currency, showSymbol: Bool = true) -> String {
        // Update the currency symbol, but reuse the formatter
        sharedFormatter.currencySymbol = showSymbol ? currency.symbol : ""
        
        return sharedFormatter.string(from: NSNumber(value: amount)) ?? "\(showSymbol ? currency.symbol : "")\(String(format: "%.2f", amount))"
    }
} 