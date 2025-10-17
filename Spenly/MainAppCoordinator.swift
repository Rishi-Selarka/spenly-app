import SwiftUI
import CoreData

struct MainAppCoordinator: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var showSplash = true
    @State private var forceUpdate = false
    @State private var loginCompleted = false
    @State private var showAuthError = false
    @State private var authErrorMessage = ""
    
    // Add flag to track when showing an ad to prevent splash from appearing
    @State private var isShowingAd = false
    
    // TEMPLATE FIX: Track if app has been fully initialized to prevent unnecessary splash
    @State private var hasBeenInitialized = false
    
    private let adMobManager = AdMobManager.shared
    
    var body: some View {
        ZStack {
            // Main app content
            Group {
                if !authManager.isSignedIn {
                    // Show login when not signed in
                    LoginView()
                        .opacity(showSplash ? 0 : 1)
                        .animation(.easeIn, value: showSplash)
                } else {
                    // Show main app when signed in
                    ContentView()
                        .environmentObject(AccountManager.shared)
                        .opacity(showSplash || !loginCompleted ? 0 : 1)
                        .animation(.easeIn, value: showSplash || !loginCompleted)
                        .onPreferenceChange(AdPresentationPreferenceKey.self) { isShowingAd in
                            self.isShowingAd = isShowingAd
                        }
                }
            }
            .id(forceUpdate) // Force view refresh when this changes
            
            // Splash screen overlay - don't show during ad presentation
            if showSplash && !isShowingAd {
                SplashView(showSplash: $showSplash)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .preferredColorScheme(.dark)
        .accentColor(themeManager.getAccentColor(for: .dark))
        .onAppear {
            // TEMPLATE FIX: Only show splash on first launch, not on subsequent UIKit presentations
            if !hasBeenInitialized && !isShowingAd {
                // Show splash only on initial app launch
                showSplash = true
                hasBeenInitialized = true
            } else {
                // For subsequent appearances (like after UIKit presentations), don't show splash
                showSplash = false
            }
            
            // For existing auth state, update login completed
            if authManager.isSignedIn {
                // Short delay to allow view to setup
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    loginCompleted = true
                }
            }
            
            // Listen for auth state changes
            setupNotifications()
        }
        .onDisappear {
            // Remove notification observers when view disappears
            NotificationCenter.default.removeObserver(
                self,
                name: NSNotification.Name("AuthStateChanged"),
                object: nil
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSNotification.Name("CloudKitSetupCompleted"),
                object: nil
            )
            NotificationCenter.default.removeObserver(
                self,
                name: .adWillPresent,
                object: nil
            )
            NotificationCenter.default.removeObserver(
                self,
                name: .adDidDismiss,
                object: nil
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSNotification.Name("AccountsLoaded"),
                object: nil
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSNotification.Name("RefreshMainUI"),
                object: nil
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSNotification.Name("AuthenticationError"),
                object: nil
            )
        }
        .alert("Authentication Error", isPresented: $showAuthError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authErrorMessage)
        }
        // Add data restoration alert at app level
        .alert("Previous Data Found", isPresented: $authManager.showDataRestorationAlert) {
            Button("Restore Data", role: .none) {
                authManager.handleDataRestorationChoice(shouldRestore: true)
            }
            Button("Start Fresh", role: .destructive) {
                authManager.handleDataRestorationChoice(shouldRestore: false)
            }
        } message: {
            Text("We found your previous data (\(authManager.estimatedDataCount)) from this Apple ID.\n\nWould you like to restore it or start fresh?\n\nNote: Restoring data will enable iCloud sync and may require restarting the app for optimal performance.")
        }
        // Add restart prompt listener at app level
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
    
    private func setupNotifications() {
        // Listen for ad presentation events
        NotificationCenter.default.addObserver(
            forName: .adWillPresent,
            object: nil,
            queue: .main
        ) { _ in
            self.isShowingAd = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .adDidDismiss,
            object: nil,
            queue: .main
        ) { _ in
            self.isShowingAd = false
        }
        
        // Listen for auth state changes to refresh view
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AuthStateChanged"),
            object: nil,
            queue: .main
        ) { notification in
            // Ensure authentication has properly updated
            if self.authManager.isSignedIn {
                // Delay to allow views to update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Force refresh the view hierarchy
                    self.forceUpdate.toggle()
                    
                    // Always dismiss splash screen if auth successful
                    if self.showSplash {
                        withAnimation {
                            self.showSplash = false
                        }
                    }
                    
                    // Delay transition to main app to avoid flashes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation {
                            self.loginCompleted = true
                        }
                    }
                }
            } else {
                // Force refresh when signing out too
                self.forceUpdate.toggle()
                
                // Set login as incomplete - forces transition back to login screen
                withAnimation {
                self.loginCompleted = false
                }
                
                // For guest sign-out, ensure we fully reset the UI state
                let wasGuest = notification.userInfo?["wasGuest"] as? Bool ?? false
                if wasGuest {
                    // Delay to ensure state is properly cleared before UI updates
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // Force one more UI refresh after guest data is cleared
                        self.forceUpdate.toggle()
                    }
                }
            }
        }
        
        // Listen for CloudKit setup completion
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CloudKitSetupCompleted"),
            object: nil,
            queue: .main
        ) { _ in
            // Final confirmation that login is complete
            if !self.loginCompleted && self.authManager.isSignedIn {
                withAnimation {
                    self.loginCompleted = true
                }
            }
        }
        
        // Listen for auth errors
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AuthenticationError"),
            object: nil,
            queue: .main
        ) { notification in
            if let errorMessage = notification.userInfo?["message"] as? String {
                self.authErrorMessage = errorMessage
                self.showAuthError = true
            }
        }
        
        // Listen for account loading completion
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AccountsLoaded"),
            object: nil,
            queue: .main
        ) { _ in
            // Force UI refresh when accounts are loaded
            self.forceUpdate.toggle()
            print("🔄 UI refreshed due to accounts loaded")
        }
        
        // Listen for explicit UI refresh requests
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RefreshMainUI"),
            object: nil,
            queue: .main
        ) { _ in
            // Force UI refresh
            self.forceUpdate.toggle()
            print("🔄 UI refreshed due to refresh request")
        }
    }
}

// Preference key for communicating ad presentation state
struct AdPresentationPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct MainAppCoordinator_Previews: PreviewProvider {
    static var previews: some View {
        MainAppCoordinator()
            .environmentObject(AuthManager.shared)
            .environmentObject(ThemeManager.shared)
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
} 