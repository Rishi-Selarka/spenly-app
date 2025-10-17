import SwiftUI
import CoreData
import UserNotifications
import GoogleMobileAds
import UIKit

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var accountManager: AccountManager
    @AppStorage("hasRequestedNotifications") private var hasRequestedNotifications = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("showNotificationSettingsPrompt") private var showNotificationSettingsPrompt = false
    @Environment(\.colorScheme) private var colorScheme
    
    // Tab and ad management
    @State private var selectedTab = 0
    @State private var previousTab = 0
    @State private var showInterstitialAd = false
    @State private var targetTab = 0
    @StateObject private var tabAdManager = TabNavigationAdManager.shared
    
    // Add transaction sheet state
    @State private var showingAddTransaction = false
    
    // Track the type of interstitial ad to show
    @State private var currentAdType: AdMobManager.InterstitialAdType = .homeToSettings
    
    // Track if an ad is currently being displayed
    @State private var isShowingAd = false
    
    // Track if we're in the middle of a tab change that should show an ad
    @State private var pendingAdTabChange = false
    
    @State private var showNotificationAlert = false
    
    var body: some View {
        ZStack {
            // Main content area with padding for tab bar
            Group {
                switch selectedTab {
                case 0:
                    HomeView()
                case 1:
                    TransactionHistoryView()
                case 2:
                    BudgetView()
                case 3:
                    SettingsView()
                default:
                    HomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 65) // Reduced padding for shorter tab bar
            .ignoresSafeArea(.keyboard, edges: .bottom)
            
            // Custom tab bar fixed at bottom
            VStack {
                Spacer()
                CustomTabBar(selectedTab: $selectedTab, showingAddTransaction: $showingAddTransaction, showAddButton: selectedTab == 0)
                    .background(Color.black)
                    .ignoresSafeArea(.container, edges: .bottom) // Extend to bottom edge
            }
            .ignoresSafeArea(.keyboard, edges: .all)
        }
        .preferredColorScheme(.dark)
        .accentColor(themeManager.getAccentColor(for: colorScheme))
        .onChange(of: selectedTab) { newTab in
            // Only process tab changes that aren't triggered by ad completion
            if !pendingAdTabChange && !isShowingAd {
                handleTabChange(from: previousTab, to: newTab)
            }
            previousTab = newTab
        }
        .sheet(isPresented: $showingAddTransaction) {
            AddTransactionView()
        }
        .showInterstitialAd(when: $showInterstitialAd, adType: currentAdType) {
            // After ad is shown or skipped, navigate to the target tab
            DispatchQueue.main.async {
                // Reset the appropriate counter now that the ad has been shown
                tabAdManager.resetCountersAfterAdShown(for: currentAdType)
                
                pendingAdTabChange = true
                selectedTab = targetTab
                // Reset the pending flag after the tab change is complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pendingAdTabChange = false
                }
            }
        }
        .onPreferenceChange(AdPresentationPreferenceKey.self) { isShowing in
            isShowingAd = isShowing
        }
        // Navigate to Transactions tab and re-post contact filter when requested
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowTransactionsForContact"))) { notification in
            guard let contact = notification.object as? Contact else { return }
            // Switch to Transactions tab without triggering ads
            pendingAdTabChange = true
            selectedTab = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                pendingAdTabChange = false
                // Re-post after tab switch so TransactionHistoryView receives it reliably
                NotificationCenter.default.post(name: NSNotification.Name("ShowTransactionsForContact"), object: contact)
            }
        }
        .task {
            // Only initialize if no valid account is currently loaded
            if accountManager.currentAccount == nil || 
               accountManager.currentAccount?.managedObjectContext == nil ||
               accountManager.currentAccount?.isDeleted == true {
                accountManager.ensureAccountInitialized(context: viewContext)
            }
            
            // Pre-load just one ad type at startup - others will load as needed
            AdMobManager.shared.loadInterstitialAd(type: .homeToSettings)
        }
        .onAppear {
            // Check if we should request notifications (only if already logged in and hasn't been requested)
            if authManager.isSignedIn && !hasRequestedNotifications {
                requestNotificationPermission()
            } else if authManager.isSignedIn && hasRequestedNotifications && showNotificationSettingsPrompt {
                // Check if we should show the prompt about enabling notifications in settings
                authManager.checkNotificationStatus { authorized in
                    if !authorized {
                        showNotificationAlert = true
                    }
                }
            }
            
            // Only reset this flag on app launch, not the persisted counter
            tabAdManager.adShownThisSession = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TransactionUpdated"))) { _ in
            // Force immediate refresh of Core Data context when transaction is updated
            viewContext.refreshAllObjects()
        }
        .alert("Enable Notifications", isPresented: $showNotificationAlert) {
            Button("Settings", role: .none) {
                authManager.openNotificationSettings()
                showNotificationSettingsPrompt = false
            }
            Button("Not Now", role: .cancel) {
                showNotificationSettingsPrompt = false
            }
        } message: {
            Text("Enable notifications in Settings to get reminders about your transactions and budget updates.")
        }
        // Add preference here as part of the view modifier chain
        .preference(key: AdPresentationPreferenceKey.self, value: isShowingAd)
        // Add data restoration alert
        .alert("Previous Data Found", isPresented: $authManager.showDataRestorationAlert) {
            Button("Restore Data", role: .none) {
                authManager.handleDataRestorationChoice(shouldRestore: true)
            }
            Button("Start Fresh", role: .destructive) {
                authManager.handleDataRestorationChoice(shouldRestore: false)
            }
        } message: {
            Text("We found your previous data (\(authManager.estimatedDataCount)) from this Apple ID. Would you like to restore it or start fresh?\n\nRestoring data will enable iCloud sync and may require restarting the app.")
        }
        // Add restart prompt listener
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowRestartPrompt"))) { notification in
            if let userInfo = notification.userInfo,
               let title = userInfo["title"] as? String,
               let message = userInfo["message"] as? String,
               let showRestartButton = userInfo["showRestartButton"] as? Bool {
                
                // Show restart alert
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                    
                    if showRestartButton {
                        alert.addAction(UIAlertAction(title: "Close App", style: .default) { _ in
                            // Guide user to manually restart - App Store compliant
                            let restartAlert = UIAlertController(
                                title: "Please Restart",
                                message: "Please close the app and reopen it for optimal performance. You can do this by double-tapping the home button (or swiping up) and swiping up on Spenly.",
                                preferredStyle: .alert
                            )
                            restartAlert.addAction(UIAlertAction(title: "OK", style: .default))
                            
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let rootViewController = windowScene.windows.first?.rootViewController {
                                rootViewController.present(restartAlert, animated: true)
                            }
                        })
                        alert.addAction(UIAlertAction(title: "Continue", style: .cancel))
                    } else {
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                    }
                    
                    // Present the alert
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootViewController = windowScene.windows.first?.rootViewController {
                        rootViewController.present(alert, animated: true)
                    }
                }
            }
        }
    }
    
    /// Handle tab changes and trigger interstitial ads when appropriate
    private func handleTabChange(from oldTab: Int, to newTab: Int) {
        // Prevent processing if we're already showing an ad
        if isShowingAd {
            return
        }
        
        if tabAdManager.handleTabChange(from: oldTab, to: newTab) {
            // Determine which type of ad to show based on the navigation
            if oldTab == 0 && newTab == 3 {
                // Home to Settings
                currentAdType = .homeToSettings
            } else if oldTab == 0 && newTab == 1 {
                // Home to History
                currentAdType = .homeToHistory
            } else if oldTab == 0 && newTab == 2 {
                // Home to Categories
                currentAdType = .homeToCategories
            }
            
            // If we should show an ad, store the target tab
            targetTab = newTab
            
            // Set isShowingAd to true as we prepare to show the ad
            isShowingAd = true
            
            // Load and show ad - but stay on the current tab until ad completes
            AdMobManager.shared.loadInterstitialAd(type: currentAdType) { success in
                if success {
                    // Trigger the ad display - it will show over the current tab
                    DispatchQueue.main.async {
                        self.showInterstitialAd = true
                    }
                } else {
                    // If ad failed to load, continue to the target tab
                    DispatchQueue.main.async {
                        self.pendingAdTabChange = true
                        self.selectedTab = self.targetTab
                        // Reset the pending flag after the tab change is complete
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.pendingAdTabChange = false
                            self.isShowingAd = false
                        }
                    }
                }
            }
        }
    }
    
    func requestNotificationPermission() {
        // Defer notification permission until after login (handled by AuthManager)
        hasRequestedNotifications = true
        notificationsEnabled = true
    }
}

// Custom Tab Bar View
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @Binding var showingAddTransaction: Bool
    let showAddButton: Bool
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @State private var addPressed: Bool = false
    @State private var rippleTrigger: Int = 0
    
    // MARK: - Computed Properties for Tab Buttons
    private var homeTabButton: some View {
        TabBarButton(
            icon: "house.fill",
            title: "Home",
            isSelected: selectedTab == 0
        ) {
            selectedTab = 0
        }
        .frame(maxWidth: .infinity)
    }
    
    private var historyTabButton: some View {
        TabBarButton(
            icon: "clock.fill",
            title: "History",
            isSelected: selectedTab == 1
        ) {
            selectedTab = 1
        }
        .frame(maxWidth: .infinity)
    }
    
    private var addTransactionButton: some View {
        VStack {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                rippleTrigger += 1
                showingAddTransaction = true
            } label: {
                ZStack {
                    // Liquid glass base (simplified, no inner fills)
                    Circle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.65)
                        .frame(width: 58, height: 58)
                        .overlay(
                            // Subtle rim for definition
                            Circle()
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                        )
                        .overlay(
                            // Soft highlight
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(addPressed ? 0.10 : 0.08),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(Circle())
                        )
                        .background(
                            // Subtle themed halo
                            Circle()
                                .fill(themeManager.getAccentColor(for: colorScheme).opacity(0.12))
                                .blur(radius: 10)
                                .scaleEffect(1.12)
                        )
                        .shadow(color: Color.black.opacity(addPressed ? 0.28 : 0.22), radius: addPressed ? 10 : 12, x: 0, y: 6)
                        .shadow(color: themeManager.getAccentColor(for: colorScheme).opacity(addPressed ? 0.08 : 0.05), radius: addPressed ? 16 : 12)
                    
                    // Bubble ripple waves
                    RippleWaves(color: themeManager.getAccentColor(for: colorScheme))
                        .id(rippleTrigger)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                        .shadow(color: themeManager.getAccentColor(for: colorScheme).opacity(addPressed ? 0.35 : 0.22), radius: addPressed ? 4 : 2)
                }
                .scaleEffect(addPressed ? 0.96 : 1.0)
            }
            .offset(y: -15)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: 50, pressing: { isPressing in
                withAnimation(.easeOut(duration: 0.12)) {
                    addPressed = isPressing
                }
            }, perform: {})
            
            Spacer()
                .frame(height: 15)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var categoriesTabButton: some View {
        TabBarButton(
            icon: "chart.pie.fill",
            title: "Budget",
            isSelected: selectedTab == 2
        ) {
            selectedTab = 2
        }
        .frame(maxWidth: .infinity)
    }
    
    private var settingsTabButton: some View {
        TabBarButton(
            icon: "gear",
            title: "Settings",
            isSelected: selectedTab == 3
        ) {
            selectedTab = 3
        }
        .frame(maxWidth: .infinity)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab bar content with smooth transitions
            HStack(spacing: 0) {
                if showAddButton {
                    // 5-section layout (with add button)
                    homeTabButton
                    historyTabButton
                    addTransactionButton
                    categoriesTabButton
                    settingsTabButton
                } else {
                    // 4-section layout (without add button) - evenly spaced
                    TabBarButton(
                        icon: "house.fill",
                        title: "Home",
                        isSelected: selectedTab == 0
                    ) {
                        selectedTab = 0
                    }
                    .frame(maxWidth: .infinity)
                    
                    TabBarButton(
                        icon: "clock.fill",
                        title: "History",
                        isSelected: selectedTab == 1
                    ) {
                        selectedTab = 1
                    }
                    .frame(maxWidth: .infinity)
                    
                    TabBarButton(
                        icon: "chart.pie.fill",
                        title: "Budget",
                        isSelected: selectedTab == 2
                    ) {
                        selectedTab = 2
                    }
                    .frame(maxWidth: .infinity)
                    
                    TabBarButton(
                        icon: "gear",
                        title: "Settings",
                        isSelected: selectedTab == 3
                    ) {
                        selectedTab = 3
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .animation(.easeInOut(duration: 0.1), value: showAddButton) // Smooth transition
            .frame(height: 65)
            .background(Color.black)
            
            // Safe area padding for home indicator
            Rectangle()
                .fill(Color.black)
                .frame(height: 0)
                .background(Color.black)
        }
        .background(Color.black) // Ensure full black background
    }
}

// Individual Tab Bar Button
struct TabBarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22)) // Increased by 10% (20px -> 22px)
                    .foregroundColor(isSelected ? themeManager.getAccentColor(for: colorScheme) : .gray)
                
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? themeManager.getAccentColor(for: colorScheme) : .gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 8) // Move icons slightly down while maintaining center alignment
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct RippleWaves: View {
    let color: Color
    @State private var animate1 = false
    @State private var animate2 = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.35), lineWidth: 2)
                .frame(width: 58, height: 58)
                .scaleEffect(animate1 ? 1.5 : 0.6)
                .opacity(animate1 ? 0.0 : 1.0)
                .animation(.easeOut(duration: 0.6), value: animate1)
            Circle()
                .stroke(color.opacity(0.25), lineWidth: 2)
                .frame(width: 58, height: 58)
                .scaleEffect(animate2 ? 1.7 : 0.6)
                .opacity(animate2 ? 0.0 : 1.0)
                .animation(.easeOut(duration: 0.8).delay(0.05), value: animate2)
        }
        .allowsHitTesting(false)
        .onAppear {
            animate1 = true
            animate2 = true
        }
    }
}
