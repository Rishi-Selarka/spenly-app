import Foundation
import GoogleMobileAds
import UIKit
import SwiftUI
import AppTrackingTransparency

@MainActor
class AdMobManager {
    static let shared = AdMobManager()
    
    // Constants
    private struct AdUnitIDs {
        // Test IDs - Use these during development and testing
        // Banner Ads for different screens
        static let testHomeBannerID = "ca-app-pub-3940256099942544/2934735716"
        static let testAddTransactionBannerID = "ca-app-pub-3940256099942544/2934735716"
        static let testExportSettingsBannerID = "ca-app-pub-3940256099942544/2934735716"
        static let testStatisticsBannerID = "ca-app-pub-3940256099942544/2934735716"
        static let testSettingsBannerID = "ca-app-pub-3940256099942544/2934735716"
        
        // Interstitial Ads
        static let testInterstitialID = "ca-app-pub-3940256099942544/4411468910"
        static let testHomeToHistoryInterstitialID = "ca-app-pub-3940256099942544/4411468910" // Using test ID
        static let testHomeToCategoriesInterstitialID = "ca-app-pub-3940256099942544/4411468910" // Using test ID
        
        // Production IDs - Replace with your actual IDs from AdMob console before App Store submission
        // Banner Ads
        static let productionHomeBannerID = "ca-app-pub-1615735364940908/2542676894"
        static let productionAddTransactionBannerID = "ca-app-pub-1615735364940908/7551460994"
        static let productionExportSettingsBannerID = "ca-app-pub-1615735364940908/1229595225"
        static let productionStatisticsBannerID = "ca-app-pub-1615735364940908/5812446878"
        static let productionSettingsBannerID = "ca-app-pub-1615735364940908/4906559315"
        
        // Interstitial Ads
        static let productionInterstitialID = "ca-app-pub-1615735364940908/3556375663"
        static let productionHomeToHistoryInterstitialID = "ca-app-pub-1615735364940908/5469675836"
        static let productionHomeToCategoriesInterstitialID = "ca-app-pub-1615735364940908/3746881691"
    }
    
    // Set to false for production environment, true for testing
    #if DEBUG
    private let useTestAds = true
    #else
    private let useTestAds = false
    #endif
    
    // Banner ad placement types
    enum BannerAdPlacement {
        case home
        case addTransaction
        case exportSettings
        case statistics
        case settings
    }
    
    // Interstitial ad types
    enum InterstitialAdType {
        case homeToSettings
        case homeToHistory
        case homeToCategories
    }
    
    // Flag to track if ads are loaded and ready
    private var isInterstitialAdReady = false
    private var interstitialAd: InterstitialAd?
    private var currentAdType: InterstitialAdType = .homeToSettings
    
    // Strong reference to the delegate to prevent it from being deallocated
    private var interstitialAdDelegate: InterstitialAdDelegate?
    
    // Initialize the manager
    private init() {
        // Preload an interstitial ad on initialization
        loadInterstitialAd(type: .homeToSettings)
        NotificationCenter.default.addObserver(self, selector: #selector(onAdsRemovedChanged), name: NSNotification.Name("AdsRemovedChanged"), object: nil)
    }

    private var adsRemoved: Bool { IAPManager.shared.isAdsRemoved }

    @objc private func onAdsRemovedChanged() {
        // Optionally clear loaded ads when premium is unlocked
        interstitialAd = nil
        isInterstitialAdReady = false
    }
    
    // MARK: - App Tracking Transparency
    
    /// Request App Tracking Transparency permission
    func requestTrackingAuthorization(completion: @escaping (ATTrackingManager.AuthorizationStatus) -> Void) {
        DispatchQueue.main.async {
            // Check current status first to avoid duplicate requests
            let currentStatus = ATTrackingManager.trackingAuthorizationStatus
            
            // Only request if status is not determined
            if currentStatus == .notDetermined {
            ATTrackingManager.requestTrackingAuthorization { status in
                    DispatchQueue.main.async {
                        completion(status)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion(currentStatus)
                }
            }
        }
    }
    
    // MARK: - Interstitial Ads
    
    /// Get the appropriate interstitial ad ID based on type
    func getInterstitialAdUnitID(for type: InterstitialAdType = .homeToSettings) -> String {
        if useTestAds {
            // Use test IDs in development
        switch type {
        case .homeToSettings:
            return AdUnitIDs.testInterstitialID
        case .homeToHistory:
            return AdUnitIDs.testHomeToHistoryInterstitialID
        case .homeToCategories:
            return AdUnitIDs.testHomeToCategoriesInterstitialID
            }
        } else {
            // Use production IDs
            switch type {
            case .homeToSettings:
                return AdUnitIDs.productionInterstitialID
            case .homeToHistory:
                return AdUnitIDs.productionHomeToHistoryInterstitialID
            case .homeToCategories:
                return AdUnitIDs.productionHomeToCategoriesInterstitialID
            }
        }
    }
    
    /// Load interstitial ad
    func loadInterstitialAd(type: InterstitialAdType = .homeToSettings, completion: ((Bool) -> Void)? = nil) {
        if adsRemoved {
            // Ensure no ad remains in memory when premium is active
            interstitialAd = nil
            isInterstitialAdReady = false
            completion?(false)
            return
        }
        // Skip if an ad is already loaded
        if isInterstitialAdReady && interstitialAd != nil {
            completion?(true)
            return
        }
        
        // Create a request
        let request = Request()
        
        // Load the interstitial ad
        InterstitialAd.load(
            with: getInterstitialAdUnitID(for: type), // Use the appropriate ad unit ID
            request: request,
            completionHandler: { [weak self] ad, error in
                Task { @MainActor [weak self] in
                    if let error = error {
                        #if DEBUG
                        print("Failed to load interstitial ad: \(error)")
                        #endif
                        self?.isInterstitialAdReady = false
                        completion?(false)
                        return
                    }
                    
                    self?.interstitialAd = ad
                    self?.isInterstitialAdReady = true
                    self?.currentAdType = type
                    completion?(true)
                }
            }
        )
    }
    
    /// Show the loaded interstitial ad
    func showInterstitialAd(type: InterstitialAdType = .homeToSettings, completion: (() -> Void)? = nil) {
        if adsRemoved {
            // Do not show and ensure internal state is cleared
            interstitialAd = nil
            isInterstitialAdReady = false
            completion?()
            return
        }
        guard let interstitialAd = interstitialAd, isInterstitialAdReady else {
            // Try loading a new ad if none is ready
            loadInterstitialAd(type: type) { [weak self] success in
                guard let self = self else {
                    completion?()
                    return
                }
                
                if success {
                    // Try showing the ad again after loading
                    self.showInterstitialAd(type: type, completion: completion)
                } else {
                    completion?()
                }
            }
            return
        }
        
        guard let rootViewController = getRootViewController() else {
            completion?()
            return
        }
        
        // Create and retain a delegate
        let delegate = InterstitialAdDelegate(completion: { [weak self] in
            // Ensure we're on the main thread
            DispatchQueue.main.async {
                // Preload the next ad after this one is dismissed
                self?.loadInterstitialAd(type: type)
                
                // Call the original completion handler
                completion?()
            }
        })
        self.interstitialAdDelegate = delegate
        
        // Present the ad
        interstitialAd.fullScreenContentDelegate = delegate
        interstitialAd.present(from: rootViewController)
        
        // Reset the state
        isInterstitialAdReady = false
        self.interstitialAd = nil
        
        // Set a timer to clear the delegate reference after a reasonable time
        // This prevents memory leaks if the ad never gets dismissed
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            if self?.interstitialAdDelegate === delegate {
                self?.interstitialAdDelegate = nil
            }
        }
    }
    
    // MARK: - Banner Ads
    
    /// Get the banner ad unit ID based on placement
    func getBannerAdUnitID(for placement: BannerAdPlacement = .home) -> String {
        if useTestAds {
            // Use test IDs in development
        switch placement {
        case .home:
            return AdUnitIDs.testHomeBannerID
        case .addTransaction:
            return AdUnitIDs.testAddTransactionBannerID
        case .exportSettings:
            return AdUnitIDs.testExportSettingsBannerID
        case .statistics:
            return AdUnitIDs.testStatisticsBannerID
        case .settings:
            return AdUnitIDs.testSettingsBannerID
            }
        } else {
            // Use production IDs
            switch placement {
            case .home:
                return AdUnitIDs.productionHomeBannerID
            case .addTransaction:
                return AdUnitIDs.productionAddTransactionBannerID
            case .exportSettings:
                return AdUnitIDs.productionExportSettingsBannerID
            case .statistics:
                return AdUnitIDs.productionStatisticsBannerID
            case .settings:
                return AdUnitIDs.productionSettingsBannerID
            }
        }
    }
    
    /// Create a new banner view with specific placement
    func createBannerView(for placement: BannerAdPlacement = .home) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = getBannerAdUnitID(for: placement)
        
        // Load the ad
        banner.load(Request())
        
        return banner
    }
    
    /// Helper method to get the root view controller
    func getRootViewController() -> UIViewController? {
        // For iOS 15 and newer
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        let window = windowScene?.windows.first
        return window?.rootViewController
    }
}

// Delegate to handle interstitial ad events
class InterstitialAdDelegate: NSObject, FullScreenContentDelegate {
    private var completion: (() -> Void)?
    
    init(completion: (() -> Void)? = nil) {
        self.completion = completion
        super.init()
    }
    
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        // Make sure we're on the main thread
        DispatchQueue.main.async { [weak self] in
            // Post a notification that can be observed by views to prevent splash screen
            NotificationCenter.default.post(name: .adDidDismiss, object: nil)
            
            // Call the completion handler
            self?.completion?()
            self?.completion = nil
        }
    }
    
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        #if DEBUG
        print("Interstitial ad failed to present: \(error)")
        #endif
        
        DispatchQueue.main.async { [weak self] in
            // Post a notification for ad failure
            NotificationCenter.default.post(name: .adDidDismiss, object: nil)
            
            self?.completion?()
            self?.completion = nil
        }
    }
    
    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        // Post a notification that ad is presenting
        NotificationCenter.default.post(name: .adWillPresent, object: nil)
    }
    
            deinit {
            // Cleanup completed
        }
}

// MARK: - Notification Names
extension Notification.Name {
    static let adWillPresent = Notification.Name("AdWillPresent")
    static let adDidDismiss = Notification.Name("AdDidDismiss")
}

// MARK: - SwiftUI Integration

/// A SwiftUI wrapper for a BannerView
struct BannerAdView: UIViewRepresentable {
    var placement: AdMobManager.BannerAdPlacement = .home
    
    func makeUIView(context: Context) -> BannerView {
        let banner = AdMobManager.shared.createBannerView(for: placement)
        if let root = AdMobManager.shared.getRootViewController() {
            banner.rootViewController = root
        }
        banner.load(Request())
        return banner
    }
    
    func updateUIView(_ uiView: BannerView, context: Context) {
        // Nothing to do here
    }
} 

