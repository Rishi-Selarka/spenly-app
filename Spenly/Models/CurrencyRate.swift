import Foundation

struct CurrencyRate: Codable, Identifiable {
    let id: UUID
    let fromCurrency: String
    let toCurrency: String
    let rate: Double
    let lastUpdated: Date
    
    var displayName: String {
        "\(fromCurrency)/\(toCurrency)"
    }
    
    var formattedRate: String {
        String(format: "%.2f", rate)
    }
    
    init(fromCurrency: String, toCurrency: String, rate: Double, lastUpdated: Date = Date()) {
        self.id = UUID()
        self.fromCurrency = fromCurrency
        self.toCurrency = toCurrency
        self.rate = rate
        self.lastUpdated = lastUpdated
    }
}

struct CurrencyRateResponse: Codable {
    let rates: [String: Double]
    let base: String
    let date: String
}

// Default currency pairs
extension CurrencyRate {
    static let defaultPairs = [
        ("USD", "INR"),
        ("GBP", "INR"),
        ("EUR", "INR")
    ]
    
    static func mockRates() -> [CurrencyRate] {
        // Realistic fallback rates (updated frequently)
        return [
            CurrencyRate(fromCurrency: "USD", toCurrency: "INR", rate: 83.25),
            CurrencyRate(fromCurrency: "GBP", toCurrency: "INR", rate: 105.80),
            CurrencyRate(fromCurrency: "EUR", toCurrency: "INR", rate: 89.95)
        ]
    }
} 