import UIKit
import SwiftUI
import AppTrackingTransparency

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            
            // Create the SwiftUI view that provides the window contents
            let contentView = MainAppCoordinator()
                .environmentObject(AuthManager.shared)
                .environmentObject(ThemeManager.shared)
                .environmentObject(AccountManager.shared)
                .environmentObject(CloudKitSyncManager.shared)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            
            // Use a UIHostingController as window root view controller
            window.rootViewController = UIHostingController(rootView: contentView)
            self.window = window
            window.makeKeyAndVisible()
            
            // Perform additional setup that would normally be in SpenlyApp
            setupAppEnvironment()
        }
    }

    private func setupAppEnvironment() {
        // Reset session state for fresh app launch
        AccountManager.shared.resetSessionState()
        
        // Configure tab bar appearance to have solid black background
        if #available(iOS 15.0, *) {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .black
            
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        } else {
            // For iOS 14 and earlier
            UITabBar.appearance().barTintColor = .black
            UITabBar.appearance().isTranslucent = false
        }

        // Hide scroll indicators globally for all scroll views/lists
        UIScrollView.appearance().showsVerticalScrollIndicator = false
        UIScrollView.appearance().showsHorizontalScrollIndicator = false
        
        // Setup notification delegate
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        
        // CRITICAL: Initialize ReminderManager to ensure default 9pm notification is set up
        _ = ReminderManager.shared
        
        // Verify default reminder is working
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            ReminderManager.shared.checkDefaultReminderStatus()
        }
        
        // Clean up category duplicates every time the app launches
        CategoryManager.shared.cleanupAllDuplicateCategories(
            context: PersistenceController.shared.container.viewContext
        )

        // Configure StoreKit / IAP
        Task { await IAPManager.shared.configure() }
        
        // Process month-end balances when app launches
        if let currentAccount = AccountManager.shared.currentAccount {
            CarryOverManager.shared.processMonthEndBalance(
                context: PersistenceController.shared.container.viewContext,
                account: currentAccount
            )
        }
        
        // Observe auth state changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AuthStateChanged"),
            object: nil,
            queue: .main
        ) { notification in
            // Ensure ViewContext is refreshed
            PersistenceController.shared.container.viewContext.refreshAllObjects()
            
            // If needed, reset or initialize account data
            if let isGuest = notification.userInfo?["isGuest"] as? Bool, isGuest {
                // For guest login, account setup is handled in signInAsGuest
            } else if let isAppleID = notification.userInfo?["isAppleID"] as? Bool, isAppleID {
                // For Apple ID login, ensure account is initialized
                AccountManager.shared.ensureAccountInitialized(context: PersistenceController.shared.container.viewContext)
            }
        }
        
        // Listen for account changes to process carry-over for the new account
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AccountChanged"),
            object: nil,
            queue: .main
        ) { notification in
            // Process carry-over for the new account
            if let account = notification.object as? Account {
                DispatchQueue.main.async {
                    CarryOverManager.shared.processMonthEndBalance(
                        context: PersistenceController.shared.container.viewContext,
                        account: account
                    )
                }
            }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called when the scene is disconnected
        // Save data if needed
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene becomes active
        // App Tracking Transparency request moved to post-sign in
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will resign active state
        // Pause ongoing tasks, disable timers, etc.
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Quietly refresh entitlements without triggering App Store sign-in prompts
        Task { @MainActor in
            await IAPManager.shared.refreshEntitlements()
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background
        // Save data, free up resources, etc.
        (UIApplication.shared.delegate as? AppDelegate)?.saveContext()
    }
} 