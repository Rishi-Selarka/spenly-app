import SwiftUI
import GoogleMobileAds
import UIKit

@MainActor
struct InterstitialAdCoordinator {
    // This is a helper struct to allow SwiftUI views to show interstitial ads
    
    // Flag to track if we've shown an interstitial ad recently
    // This helps prevent too many ads being shown to the user
    private static var lastAdShownTime: Date?
    private static let minimumTimeBetweenAds: TimeInterval = 60 // 1 minute
    
    // For HomeToHistory ad, we want to be more lenient to ensure it's shown after the count threshold
    private static let minimumTimeBetweenHistoryAds: TimeInterval = 5 // 5 seconds
    
    // Track the last ad type shown to be more lenient when showing different types
    private static var lastAdTypeShown: AdMobManager.InterstitialAdType?
    
    /// Shows an interstitial ad if one is available and it's been at least the minimum time since the last ad
    static func showAdIfAvailable(adType: AdMobManager.InterstitialAdType = .homeToSettings, isShowingAd: Binding<Bool>? = nil, completion: (() -> Void)? = nil) {
        // Determine the minimum time based on ad type
        let minimumTime: TimeInterval
        switch adType {
        case .homeToSettings:
            minimumTime = minimumTimeBetweenAds
        case .homeToHistory, .homeToCategories:
            minimumTime = minimumTimeBetweenHistoryAds
        }
        
        // More lenient check if it's a different ad type than the last one shown
        let isDifferentAdType = lastAdTypeShown != adType
        
        // Check if we've shown an ad recently - this check is more lenient for different ad types
        if let lastShown = lastAdShownTime,
           Date().timeIntervalSince(lastShown) < minimumTime,
           !isDifferentAdType {
            // Skip showing an ad if we've shown one too recently of the same type
            completion?()
            return
        }
        
        // Set the isShowingAd flag to true
        DispatchQueue.main.async {
            if let isShowingAd = isShowingAd {
                isShowingAd.wrappedValue = true
            }
        }
        
        // Show the ad (AdMobManager will handle getting the root view controller)
        AdMobManager.shared.showInterstitialAd(type: adType) {
            // Update the last shown time and type
            lastAdShownTime = Date()
            lastAdTypeShown = adType
            
            // Reset the isShowingAd flag
            DispatchQueue.main.async {
                if let isShowingAd = isShowingAd {
                    isShowingAd.wrappedValue = false
                }
            }
            
            // Call completion handler
            completion?()
        }
    }
}

// Example extension to add a modifier for showing interstitial ads
extension View {
    /// Adds a trigger to show an interstitial ad when a condition is true
    func showInterstitialAd(when condition: Binding<Bool>, adType: AdMobManager.InterstitialAdType = .homeToSettings, completion: (() -> Void)? = nil) -> some View {
        return self
            .onChange(of: condition.wrappedValue) { newValue in
                if newValue {
                    // Track the ad presentation state for the view
                    let isShowingAd = Binding<Bool>(
                        get: { condition.wrappedValue },
                        set: { condition.wrappedValue = $0 }
                    )
                    
                    InterstitialAdCoordinator.showAdIfAvailable(adType: adType, isShowingAd: isShowingAd) {
                        // Reset the condition after the ad is shown or skipped
                        DispatchQueue.main.async {
                            condition.wrappedValue = false
                            completion?()
                        }
                    }
                }
            }
            .preference(key: AdPresentationPreferenceKey.self, value: condition.wrappedValue)
    }
} 