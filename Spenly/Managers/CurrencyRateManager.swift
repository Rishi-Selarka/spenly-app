import Foundation
import Combine

class CurrencyRateManager: ObservableObject {
    static let shared = CurrencyRateManager()
    
    @Published var currencyRates: [CurrencyRate] = []
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    
    private var cancellables = Set<AnyCancellable>()
    // NOTE: Do not hardcode keys in release. Keep placeholder or use Info.plist
    private let apiKey = "YOUR_EXCHANGE_API_KEY_HERE"
    private let baseURL = "https://api.exchangerate-api.com/v4/latest"
    
    // UserDefaults keys
    private let selectedPairsKey = "selectedCurrencyPairs"
    private let lastUpdateKey = "currencyRatesLastUpdate"
    private let cachedRatesKey = "cachedCurrencyRates"
    
    init() {
        loadCachedRates()
        loadSelectedPairs()
    }
    
    // MARK: - Public Methods
    
    func fetchRates() {
        guard !isLoading else { return }
        
        isLoading = true
        
        // Try to fetch real data from API, fallback to mock data if needed
        fetchRatesFromAPI()
    }
    
    func refreshRates() {
        fetchRates()
    }
    
    // MARK: - Currency Pair Management
    
    var selectedPairs: [(String, String)] {
        get {
            if let data = UserDefaults.standard.data(forKey: selectedPairsKey),
               let pairStrings = try? JSONDecoder().decode([String].self, from: data) {
                // Convert back from "USD-INR" format to ("USD", "INR") tuples
                return pairStrings.compactMap { pairString in
                    let components = pairString.components(separatedBy: "-")
                    guard components.count == 2 else { return nil }
                    return (components[0], components[1])
                }
            }
            return CurrencyRate.defaultPairs
        }
        set {
            // Convert tuples to "USD-INR" format for encoding
            let pairStrings = newValue.map { "\($0.0)-\($0.1)" }
            if let data = try? JSONEncoder().encode(pairStrings) {
                UserDefaults.standard.set(data, forKey: selectedPairsKey)
            }
        }
    }
    
    func updateSelectedPairs(_ pairs: [(String, String)]) {
        selectedPairs = pairs
        fetchRates()
    }
    
    // MARK: - Caching
    
    private func cacheRates() {
        if let data = try? JSONEncoder().encode(currencyRates) {
            UserDefaults.standard.set(data, forKey: cachedRatesKey)
            UserDefaults.standard.set(Date(), forKey: lastUpdateKey)
        }
    }
    
    private func loadCachedRates() {
        if let data = UserDefaults.standard.data(forKey: cachedRatesKey),
           let rates = try? JSONDecoder().decode([CurrencyRate].self, from: data) {
            currencyRates = rates
            lastUpdated = UserDefaults.standard.object(forKey: lastUpdateKey) as? Date
        }
    }
    
    private func loadSelectedPairs() {
        // This will trigger fetchRates if needed
        if currencyRates.isEmpty {
            fetchRates()
        }
    }
    
    // MARK: - Real API Implementation (for future use)
    
    private func fetchRatesFromAPI() {
        // Use free exchangerate-api.com service
        guard let url = URL(string: "\(baseURL)/USD") else { 
            fallbackToMockData()
            return 
        }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: CurrencyRateResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    self.isLoading = false
                    
                    if case .failure(let error) = completion {
                        print("⚠️ Currency API error: \(error.localizedDescription)")
                        print("📱 Using cached/mock data as fallback")
                        self.fallbackToMockData()
                    }
                },
                receiveValue: { [weak self] response in
                    self?.processAPIResponse(response)
                }
            )
            .store(in: &cancellables)
    }
    
    private func fallbackToMockData() {
        print("📊 Loading mock currency data")
        currencyRates = CurrencyRate.mockRates()
        lastUpdated = Date()
        isLoading = false
        cacheRates()
    }
    
    private func processAPIResponse(_ response: CurrencyRateResponse) {
        print("✅ Successfully fetched live currency rates")
        
        let rates: [CurrencyRate] = selectedPairs.compactMap { pair in
            // Handle different base currencies
            let rate: Double
            if pair.0 == "USD" {
                // Direct USD to target currency
                rate = response.rates[pair.1] ?? 1.0
            } else if pair.1 == "USD" {
                // Target currency to USD (inverse)
                if let targetRate = response.rates[pair.0] {
                    rate = 1.0 / targetRate
                } else {
                    return nil
                }
            } else {
                // Cross currency calculation
                guard let fromRate = response.rates[pair.0],
                      let toRate = response.rates[pair.1] else {
                    return nil
                }
                rate = toRate / fromRate
            }
            
            return CurrencyRate(fromCurrency: pair.0, toCurrency: pair.1, rate: rate)
        }
        
        // Only update if we got valid rates
        if !rates.isEmpty {
            currencyRates = rates
            lastUpdated = Date()
            cacheRates()
            print("💰 Updated \(rates.count) currency pairs")
        } else {
            print("⚠️ No valid rates received, keeping existing data")
            fallbackToMockData()
        }
        
        isLoading = false
    }
} 
