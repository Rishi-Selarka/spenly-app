import SwiftUI
import Foundation

class TabNavigationAdManager: ObservableObject {
    static let shared = TabNavigationAdManager()
    
    // Flags to track ad visibility state
    @Published var adShownThisSession = false
    private var previousTab = 0
    
    // Targets for when to show ads
    private let sourceTab = 0 // Home tab
    private let destinationTab = 3 // Settings tab
    
    // HomeView to TransactionHistory tracking - persist across app sessions using @AppStorage
    @AppStorage("homeToHistoryCount") private(set) var homeToHistoryCount = 0
    private let homeToHistoryMaxCount = 3 // Show ad after 3 navigations
    
    // HomeView to CategoriesView tracking - persist across app sessions using @AppStorage
    @AppStorage("homeToCategoriesCount") private(set) var homeToCategoriesCount = 0
    private let homeToCategoriesMaxCount = 3 // Show ad after 3 navigations
    
    // Flag to track which counter needs to be reset after ad is shown
    private var shouldResetHistoryCounter = false
    private var shouldResetCategoriesCounter = false
    
    // Private init for singleton
    private init() {
        // Current counts: HomeToHistory \(homeToHistoryCount)/\(homeToHistoryMaxCount), HomeToCategories \(homeToCategoriesCount)/\(homeToCategoriesMaxCount)
    }
    
    /// Handle tab change and determine if we should show an ad
    /// Returns true if an ad should be shown
    func handleTabChange(from oldTab: Int, to newTab: Int) -> Bool {
        // Reset flags
        shouldResetHistoryCounter = false
        shouldResetCategoriesCounter = false
        
        // Handle Home to Settings ad (once per session)
        if oldTab == sourceTab && newTab == destinationTab {
            // Skip if an ad has already been shown this session
            if !adShownThisSession {
                adShownThisSession = true
                return true
            }
            return false
        }
        
        // Handle Home to TransactionHistory ad (counts persist across sessions)
        if oldTab == 0 && newTab == 1 {
            homeToHistoryCount += 1
            
            // Check if we've reached the threshold
            if homeToHistoryCount >= homeToHistoryMaxCount {
                shouldResetHistoryCounter = true
                return true // Show ad
            }
        }
        
        // Handle Home to Categories ad (counts persist across sessions)
        if oldTab == 0 && newTab == 2 {
            homeToCategoriesCount += 1
            
            // Check if we've reached the threshold
            if homeToCategoriesCount >= homeToCategoriesMaxCount {
                shouldResetCategoriesCounter = true
                return true // Show ad
            }
        }
        
        return false
    }
    
    /// Reset counters after ad is successfully shown
    func resetCountersAfterAdShown(for type: AdMobManager.InterstitialAdType) {
        switch type {
        case .homeToHistory:
            if shouldResetHistoryCounter {
                homeToHistoryCount = 0
            }
        case .homeToCategories:
            if shouldResetCategoriesCounter {
                homeToCategoriesCount = 0
            }
        default:
            break
        }
        
        // Reset flags
        shouldResetHistoryCounter = false
        shouldResetCategoriesCounter = false
    }
    
    /// Reset session tracking (useful for testing)
    func resetSession() {
        adShownThisSession = false
        homeToHistoryCount = 0
        homeToCategoriesCount = 0
        shouldResetHistoryCounter = false
        shouldResetCategoriesCounter = false
    }
    
    /// Get the current HomeToHistory count (useful for UI or debugging)
    func getHomeToHistoryCount() -> Int {
        return homeToHistoryCount
    }
    
    /// Get the current HomeToCategories count (useful for UI or debugging)
    func getHomeToCategoriesCount() -> Int {
        return homeToCategoriesCount
    }
    
    /// Get the number of navigations remaining before showing an ad (History)
    func getRemainingHistoryNavigationsBeforeAd() -> Int {
        return max(0, homeToHistoryMaxCount - homeToHistoryCount)
    }
    
    /// Get the number of navigations remaining before showing an ad (Categories)
    func getRemainingCategoriesNavigationsBeforeAd() -> Int {
        return max(0, homeToCategoriesMaxCount - homeToCategoriesCount)
    }
} 
