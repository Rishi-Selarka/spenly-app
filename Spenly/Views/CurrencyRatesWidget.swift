import SwiftUI

struct CurrencyRatesWidget: View {
    @StateObject private var currencyManager = CurrencyRateManager.shared
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @State private var showingEditSheet = false
    @State private var hasAppeared = false
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Global Rates")
                    .font(selectedFont.font(size: 20, bold: true))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    showingEditSheet = true
                }) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
            }
            
            if currencyManager.isLoading {
                // Loading State
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Updating rates...")
                            .font(selectedFont.font(size: 14))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if currencyManager.currencyRates.isEmpty {
                // Empty State
                VStack(spacing: 12) {
                    Image(systemName: "dollarsign.circle")
                        .font(.system(size: 40))
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                    
                    Text("No currency rates available")
                        .font(selectedFont.font(size: 16))
                        .foregroundColor(.secondary)
                    
                    Button("Refresh") {
                        currencyManager.refreshRates()
                    }
                    .font(selectedFont.font(size: 14))
                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // Currency Rates Grid
                HStack(spacing: 20) {
                    ForEach(currencyManager.currencyRates.prefix(3)) { rate in
                        CurrencyRateItem(rate: rate)
                    }
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    themeManager.getAccentColor(for: colorScheme).opacity(0.18),
                    themeManager.getAccentColor(for: colorScheme).opacity(0.08)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .shadow(color: themeManager.getAccentColor(for: colorScheme).opacity(0.15), radius: 8, x: 0, y: 4)
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            
            // Refresh rates if they're older than 15 minutes (practical for real API)
            if let lastUpdated = currencyManager.lastUpdated,
               Date().timeIntervalSince(lastUpdated) > 900 {
                currencyManager.refreshRates()
            } else if currencyManager.currencyRates.isEmpty {
                // Initial load if no cached data
                currencyManager.fetchRates()
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            CurrencyRateEditView()
        }
    }
}

struct CurrencyRateItem: View {
    let rate: CurrencyRate
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    var body: some View {
        VStack(spacing: 8) {
            Text(rate.displayName)
                .font(selectedFont.font(size: 14))
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            
            Text(rate.formattedRate)
                .font(selectedFont.font(size: 18, bold: true))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct CurrencyRateEditView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var currencyManager = CurrencyRateManager.shared
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedPairs: [(String, String)] = []
    
    // Use comprehensive currency list with 80+ currencies
    private let availableCurrencies = CurrencyInfo.getCurrencyCodes()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Enhanced gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black,
                        Color.black.opacity(0.92),
                        themeManager.getAccentColor(for: colorScheme).opacity(0.2)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 28) {
                        // Enhanced header section
                        VStack(spacing: 12) {
                            // Icon header
                            ZStack {
                                Circle()
                                    .fill(themeManager.getAccentColor(for: colorScheme).opacity(0.2))
                                    .frame(width: 60, height: 60)
                                
                                Image(systemName: "coloncurrencysign.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                            }
                            .padding(.top, 10)
                            
                            Text("Currency Rate Configuration")
                                .font(selectedFont.font(size: 26, bold: true))
                                .foregroundColor(.white)
                            
                            Text("Select up to 3 currency pairs to display in the widget")
                                .font(selectedFont.font(size: 15))
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .padding(.top, 10)
                        
                        // Three separate containers for currency pairs
                        ForEach(0..<3, id: \.self) { index in
                            if index < selectedPairs.count {
                                CurrencyPairContainer(
                                    index: index,
                                    fromCurrency: Binding(
                                        get: { selectedPairs[index].0 },
                                        set: { newValue in
                                            selectedPairs[index].0 = newValue
                                        }
                                    ),
                                    toCurrency: Binding(
                                        get: { selectedPairs[index].1 },
                                        set: { newValue in
                                            selectedPairs[index].1 = newValue
                                        }
                                    ),
                                    availableCurrencies: availableCurrencies
                                )
                            }
                        }
                        
                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle("Currency Rates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                            Text("Cancel")
                        }
                    }
                    .foregroundColor(.white.opacity(0.9))
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        currencyManager.updateSelectedPairs(selectedPairs)
                        dismiss()
                    }) {
                        HStack(spacing: 4) {
                            Text("Save")
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                        }
                    }
                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            selectedPairs = currencyManager.selectedPairs
            // Ensure we have exactly 3 pairs for the UI
            while selectedPairs.count < 3 {
                selectedPairs.append(("USD", "INR"))
            }
        }
    }
}

struct CurrencyPairContainer: View {
    let index: Int
    @Binding var fromCurrency: String
    @Binding var toCurrency: String
    let availableCurrencies: [String]
    
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    // Filter currencies to prevent selecting the same currency for both from and to
    private var availableFirstCurrencies: [String] {
        availableCurrencies.filter { $0 != toCurrency }
    }
    
    private var availableSecondCurrencies: [String] {
        availableCurrencies.filter { $0 != fromCurrency }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Enhanced container header
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(themeManager.getAccentColor(for: colorScheme).opacity(0.2))
                            .frame(width: 32, height: 32)
                        
                        Text("\(index + 1)")
                            .font(selectedFont.font(size: 14, bold: true))
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                    }
                    
                    Text("Currency Pair")
                        .font(selectedFont.font(size: 18, bold: true))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundColor(themeManager.getAccentColor(for: colorScheme).opacity(0.7))
                    .font(.system(size: 22))
            }
            
            // Currency selection section with enhanced styling
            VStack(spacing: 20) {
                // From Currency
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                            .font(.system(size: 14))
                        
                        Text("From Currency")
                            .font(selectedFont.font(size: 14))
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    Menu {
                        ForEach(availableFirstCurrencies, id: \.self) { currency in
                            Button(action: {
                                fromCurrency = currency
                            }) {
                                HStack {
                                    Text(currency)
                                        .fontWeight(.semibold)
                                    if let info = CurrencyInfo.getCurrencyInfo(for: currency) {
                                        Text("- \(info.name)")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(fromCurrency)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            if let info = CurrencyInfo.getCurrencyInfo(for: fromCurrency) {
                                Text("- \(info.name)")
                                    .font(selectedFont.font(size: 13))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.down.circle.fill")
                                .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                                .font(.system(size: 16))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(themeManager.getAccentColor(for: colorScheme).opacity(0.4), lineWidth: 1)
                                )
                        )
                    }
                }
                
                // Exchange arrow indicator
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(themeManager.getAccentColor(for: colorScheme).opacity(0.15))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                            .font(.system(size: 14, weight: .bold))
                    }
                    Spacer()
                }
                .padding(.vertical, -6)
                
                // To Currency
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                            .font(.system(size: 14))
                        
                        Text("To Currency")
                            .font(selectedFont.font(size: 14))
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    Menu {
                        ForEach(availableSecondCurrencies, id: \.self) { currency in
                            Button(action: {
                                toCurrency = currency
                            }) {
                                HStack {
                                    Text(currency)
                                        .fontWeight(.semibold)
                                    if let info = CurrencyInfo.getCurrencyInfo(for: currency) {
                                        Text("- \(info.name)")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(toCurrency)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            if let info = CurrencyInfo.getCurrencyInfo(for: toCurrency) {
                                Text("- \(info.name)")
                                    .font(selectedFont.font(size: 13))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.down.circle.fill")
                                .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                                .font(.system(size: 16))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(themeManager.getAccentColor(for: colorScheme).opacity(0.4), lineWidth: 1)
                                )
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.06)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    themeManager.getAccentColor(for: colorScheme).opacity(0.5),
                                    themeManager.getAccentColor(for: colorScheme).opacity(0.2)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
        .shadow(color: themeManager.getAccentColor(for: colorScheme).opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    CurrencyRatesWidget()
        .padding()
        .background(Color(.systemBackground))
} 
