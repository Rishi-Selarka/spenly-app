import Foundation
import SwiftUI
import Combine

@MainActor
public class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @AppStorage("selectedTheme") var selectedTheme: Theme = .ocean
    
    init() {
        setColorScheme()
        
        // Listen for premium status changes to revalidate theme
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PremiumEntitlementChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.validateAndFixTheme()
            }
        }
        
        // Delay validation until IAP is configured
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { @MainActor in
                self.validateAndFixTheme()
            }
        }
    }
    
    private func validateAndFixTheme() {
        let isPremiumUnlocked = IAPManager.shared.isPremiumUnlocked
        // Ensure non-premium users can't have premium themes selected
        if selectedTheme.isPremium && !isPremiumUnlocked {
            print("⚠️ Resetting premium theme '\(selectedTheme.rawValue)' to Ocean for non-premium user")
            selectedTheme = .ocean // Reset to free theme
        }
        
        // Also validate and fix font selection
        validateAndFixFont()
    }
    
    private func validateAndFixFont() {
        let currentFont = AppFont(rawValue: UserDefaults.standard.string(forKey: "selectedFont") ?? "System") ?? .system
        let isPremiumUnlocked = IAPManager.shared.isPremiumUnlocked
        
        // Ensure non-premium users can't have premium fonts selected
        if currentFont.isPremium && !isPremiumUnlocked {
            print("⚠️ Resetting premium font '\(currentFont.rawValue)' to System for non-premium user")
            UserDefaults.standard.set(AppFont.system.rawValue, forKey: "selectedFont")
        }
    }
    
    var preferredColorScheme: ColorScheme {  // Changed to non-optional, always returns dark
        .dark
    }
    
    func setTheme(_ theme: Theme) {
        let isPremiumUnlocked = IAPManager.shared.isPremiumUnlocked
        // Validate theme access before setting
        if theme.isPremium && !isPremiumUnlocked {
            // Don't set premium themes for non-premium users
            return
        }
        selectedTheme = theme
        setColorScheme()
    }
    
    private func setColorScheme() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.windows.forEach { window in
                window.overrideUserInterfaceStyle = .dark  // Always set to dark
            }
        }
    }
    
    func getAccentColor(for colorScheme: ColorScheme) -> Color {
        selectedTheme.colors(for: .dark).accent  // Always use dark mode colors
    }
    
    func getToggleColor(for colorScheme: ColorScheme) -> Color {
        selectedTheme.colors(for: .dark).accent  // Always use dark mode colors
    }
}

struct ThemeColors {
    let accent: Color
    let background: Color
    let secondaryBackground: Color
    let text: Color
    let secondaryText: Color
} 
