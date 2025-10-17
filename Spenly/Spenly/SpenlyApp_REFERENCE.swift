import SwiftUI
import CoreData
import UserNotifications

struct SpenlyApp: App {
    // Use shared instances as regular properties, not StateObjects
    @StateObject private var authManager = AuthManager.shared
    private let themeManager = ThemeManager.shared
    private let accountManager = AccountManager.shared
    private let cloudKitSyncManager = CloudKitSyncManager.shared
    private let carryOverManager = CarryOverManager.shared
    private let persistenceController = PersistenceController.shared
    private let categoryManager = CategoryManager.shared
    private let reminderManager = ReminderManager.shared  // Initialize to set up default 9pm notification
    
    init() {
        // Perform any setup that must happen at app launch
        setupAppEnvironment()
    }
    
    var body: some Scene {
        WindowGroup {
            MainAppCoordinator()
                .environmentObject(authManager)
                .environmentObject(themeManager)
                .environmentObject(accountManager)
                .environmentObject(cloudKitSyncManager)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    // Setup notification delegate
                    UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
                    
                    // Clean up category duplicates every time the app launches
                    categoryManager.cleanupAllDuplicateCategories(context: persistenceController.container.viewContext)
                    
                    // Process month-end balances when app launches
                    if let currentAccount = accountManager.currentAccount {
                        carryOverManager.processMonthEndBalance(
                            context: persistenceController.container.viewContext,
                            account: currentAccount
                        )
                    }
                }
        }
    }
    
    private func setupAppEnvironment() {
        // Setup notification delegate
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        
        // Observe auth state changes at app level
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AuthStateChanged"),
            object: nil,
            queue: .main
        ) { notification in
            // Ensure ViewContext is refreshed
            persistenceController.container.viewContext.refreshAllObjects()
            
            // If needed, reset or initialize account data
            if let isGuest = notification.userInfo?["isGuest"] as? Bool, isGuest {
                // For guest login, account setup is handled in signInAsGuest
            } else if let isAppleID = notification.userInfo?["isAppleID"] as? Bool, isAppleID {
                // For Apple ID login, ensure account is initialized
                accountManager.ensureAccountInitialized(context: persistenceController.container.viewContext)
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
                    carryOverManager.processMonthEndBalance(
                        context: persistenceController.container.viewContext,
                        account: account
                    )
                }
            }
        }
    }
} 