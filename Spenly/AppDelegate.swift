import UIKit
import CoreData
import UserNotifications
import CloudKit
import GoogleMobileAds
import Firebase
import FirebaseCrashlytics

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    // Core Data stack
    var persistentContainer: NSPersistentCloudKitContainer {
        return PersistenceController.shared.container
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Override point for customization after application launch.
        
        // Hide scroll indicators globally (apply before UI creation)
        UIScrollView.appearance().showsVerticalScrollIndicator = false
        UIScrollView.appearance().showsHorizontalScrollIndicator = false
        UITableView.appearance().showsVerticalScrollIndicator = false
        UITableView.appearance().showsHorizontalScrollIndicator = false
        UICollectionView.appearance().showsVerticalScrollIndicator = false
        UICollectionView.appearance().showsHorizontalScrollIndicator = false

        // Initialize Firebase
        FirebaseApp.configure()
        
        // Initialize Firebase Crashlytics
        #if DEBUG
        // Enable Crashlytics data collection for debug builds
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        print("✅ Firebase Crashlytics enabled for debug build")
        #else
        // Enable Crashlytics for release builds
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        print("✅ Firebase Crashlytics enabled for production build")
        #endif
        
        // Initialize Google Mobile Ads SDK
        // Replace the test app ID with your actual AdMob app ID in production
        MobileAds.shared.start(completionHandler: { status in
            // Optional: Handle initialization status
            if let error = status.adapterStatusesByClassName.values.first(where: { $0.state == AdapterInitializationState.notReady })?.description {
                #if DEBUG
                print("AdMob initialization error: \(error)")
                #endif
            }
        })
        
        // Clear any notification badges
        UNUserNotificationCenter.current().setBadgeCount(0)
        
        // Set up error handling
        setupErrorHandling()
        
        // Register for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        // Register for CoreData CloudKit notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloudKitEvent(_:)),
            name: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil
        )
        
        // Register for background task expiration warning
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackgroundTaskWarning(_:)),
            name: NSNotification.Name("UIApplicationBackgroundTaskExpiredWarning"),
            object: nil
        )
        
        // Register for notifications
        UNUserNotificationCenter.current().delegate = self
        
        // Register background operation notifications
        registerBackgroundNotifications()
        
        // Note: We no longer request notification permissions here
        // Notification permissions are now requested after user login
        
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting scene: UIScene, willMigrateFrom fromScene: UIScene?, options: UIScene.ConnectionOptions) {
        // Called when a new scene is being created.
        // Use this method to select a configuration to create the new scene with.
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

    // MARK: - Core Data stack

    func saveContext () {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nserror = error as NSError
                logError(error, context: "Core Data Save")
                handleCoreDataError(nserror)
            }
        }
    }

    // MARK: - App State Handling

    func applicationWillTerminate(_ application: UIApplication) {
        // Save any pending changes
        saveContext()
        cleanupResources()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Save any pending changes
        saveContext()
        
        // Note: CloudKit sync happens automatically via NSPersistentCloudKitContainer
        // No manual background sync needed - saves significant battery life
        // iOS handles CloudKit sync opportunistically when device is charging or on WiFi
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Clear badges when app is about to enter foreground
        UNUserNotificationCenter.current().setBadgeCount(0)
        
        // Refresh Core Data context
        persistentContainer.viewContext.refreshAllObjects()
        
        // Check if iCloud sync should be enabled
        checkAccountStatus()
    }

    // MARK: - State Restoration

    func application(_ application: UIApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool {
        // Save current state
        saveContext()
        return true
    }

    func application(_ application: UIApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool {
        // Restore state
        return true
    }

    // MARK: - Error Handling

    private func setupErrorHandling() {
        // Set up global error handling
        NSSetUncaughtExceptionHandler { exception in
            AppDelegate.handleUncaughtException(exception)
        }
    }
    
    private static func handleUncaughtException(_ exception: NSException) {
        // Log the exception
        print("Uncaught exception: \(exception)")
        print("Exception name: \(exception.name)")
        print("Exception reason: \(exception.reason ?? "Unknown reason")")
        print("Exception callstack: \(exception.callStackSymbols)")
        
        // Report to Firebase Crashlytics
        Crashlytics.crashlytics().log("Uncaught exception: \(exception.name)")
        if let reason = exception.reason {
            Crashlytics.crashlytics().log("Exception reason: \(reason)")
        }
        
        // Set custom keys for crash analysis
        Crashlytics.crashlytics().setCustomValue(exception.name.rawValue, forKey: "exception_name")
        Crashlytics.crashlytics().setCustomValue(exception.reason ?? "Unknown", forKey: "exception_reason")
        Crashlytics.crashlytics().setCustomValue(exception.callStackSymbols.joined(separator: "\n"), forKey: "exception_stack")
        
        // Create a custom error for Crashlytics
        let crashError = NSError(
            domain: "SpenlyUncaughtException",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: exception.reason ?? "Uncaught exception occurred",
                "ExceptionName": exception.name.rawValue,
                "ExceptionReason": exception.reason ?? "Unknown"
            ]
        )
        Crashlytics.crashlytics().record(error: crashError)
        
        // Post notification for UI handling
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("UncaughtException"),
                object: nil,
                userInfo: ["exception": exception]
            )
        }
    }

    private func handleCoreDataError(_ error: NSError) {
        switch error.code {
        case NSPersistentStoreIncompatibleVersionHashError:
            // Handle version mismatch
            NotificationCenter.default.post(
                name: NSNotification.Name("CoreDataVersionMismatch"),
                object: nil
            )
        case NSPersistentStoreIncompatibleSchemaError:
            // Handle schema incompatibility
            NotificationCenter.default.post(
                name: NSNotification.Name("CoreDataSchemaIncompatibility"),
                object: nil
            )
        default:
            // Handle other Core Data errors
            NotificationCenter.default.post(
                name: NSNotification.Name("CoreDataError"),
                object: nil,
                userInfo: ["error": error]
            )
        }
    }

    // MARK: - Helper Methods

    private func cleanupResources() {
        // Clear any caches
        persistentContainer.viewContext.reset()
    }

    private func logError(_ error: Error, context: String) {
        print("Error in \(context): \(error.localizedDescription)")
        
        // Log error to Firebase Crashlytics
        Crashlytics.crashlytics().log("Error in \(context): \(error.localizedDescription)")
        Crashlytics.crashlytics().record(error: error)
        
        // Set custom keys for better crash analysis
        Crashlytics.crashlytics().setCustomValue(context, forKey: "error_context")
        Crashlytics.crashlytics().setCustomValue(error.localizedDescription, forKey: "error_description")
    }

    // MARK: - Memory Management
    
    @objc func handleMemoryWarning() {
        print("⚠️ Memory warning received - clearing caches and optimizing memory usage")
        
        // Clear image cache
        ImageCache.shared.clearCache()
        
        // Handle CoreData memory optimizations
        CoreDataManager.shared.handleMemoryWarning()
        
        // Clear any temporary views or in-memory data
        clearTemporaryResources()
        
        // Force garbage collection by clearing any retained references
        cleanupRetainedReferences()
    }
    
    private func clearTemporaryResources() {
        // Reset any large in-memory collections
        // This is a central place to release any memory-intensive resources
        
        // Reset image cache
        URLCache.shared.removeAllCachedResponses()
        
        // Clear any temporary directories
        clearTemporaryDirectory()
    }
    
    private func clearTemporaryDirectory() {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
        
        do {
            let temporaryFiles = try FileManager.default.contentsOfDirectory(
                at: temporaryDirectoryURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            for fileURL in temporaryFiles {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            print("Error clearing temporary directory: \(error.localizedDescription)")
        }
    }

    private func cleanupRetainedReferences() {
        // Clear any strong reference cycles or retained closures
        // This helps the garbage collector reclaim memory faster
        
        // Clear URLSession cache beyond what clearTemporaryResources does
        URLCache.shared.diskCapacity = 0
        URLCache.shared.memoryCapacity = 0
        URLCache.shared.removeAllCachedResponses()
        
        // Reset URLSession cache to smaller values after clearing
        URLCache.shared.diskCapacity = 10 * 1024 * 1024 // 10MB
        URLCache.shared.memoryCapacity = 4 * 1024 * 1024 // 4MB
    }

    // Add proper cleanup when app is deallocated
    deinit {
        // Remove all NotificationCenter observers to prevent memory leaks
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Notification Delegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                                willPresent notification: UNNotification, 
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show the notification even when the app is in the foreground
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                                didReceive response: UNNotificationResponse, 
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification response
        completionHandler()
    }

    // MARK: - Background Task Handling
    
    @objc func handleCloudKitEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
        
        switch event.type {
        case .setup, .import, .export:
            if event.succeeded {
                #if DEBUG
                print("CloudKit operation succeeded: \(event.type)")
                #endif
            } else if let error = event.error {
                #if DEBUG
                print("CloudKit operation failed: \(error.localizedDescription)")
                #endif
                
                // Handle different CloudKit errors
                handleCloudKitError(error)
            }
        default:
            #if DEBUG
            print("Unknown CloudKit event type")
            #endif
            break
        }
    }
    
    @objc func handleBackgroundTaskWarning(_ notification: Notification) {
        // Handle background task warning
        print("⚠️ Background task warning received")
    }

    // MARK: - Background Task Management

    private func handleCloudKitError(_ error: Error) {
        // Log CloudKit error to Crashlytics
        Crashlytics.crashlytics().log("CloudKit error occurred: \(error.localizedDescription)")
        Crashlytics.crashlytics().record(error: error)
        
        // Handle different CloudKit error types
        if let ckError = error as? CKError {
            // Set custom keys for CloudKit error analysis
            Crashlytics.crashlytics().setCustomValue(ckError.code.rawValue, forKey: "cloudkit_error_code")
            Crashlytics.crashlytics().setCustomValue(ckError.localizedDescription, forKey: "cloudkit_error_description")
            
            switch ckError.code {
            case .quotaExceeded:
                // User's iCloud storage is full
                Crashlytics.crashlytics().log("CloudKit quota exceeded")
                NotificationCenter.default.post(
                    name: NSNotification.Name("CloudKitStorageFull"),
                    object: nil
                )
                
            case .networkFailure, .networkUnavailable, .serviceUnavailable, .serverResponseLost:
                // Network-related errors - can retry later
                Crashlytics.crashlytics().log("CloudKit network error: \(ckError.code)")
                NotificationCenter.default.post(
                    name: NSNotification.Name("CloudKitNetworkError"),
                    object: nil
                )
                
            case .notAuthenticated, .accountTemporarilyUnavailable:
                // User needs to sign in to iCloud again
                Crashlytics.crashlytics().log("CloudKit authentication error: \(ckError.code)")
                NotificationCenter.default.post(
                    name: NSNotification.Name("CloudKitAuthError"),
                    object: nil
                )
                
            case .zoneNotFound:
                // Zone might have been deleted - force recreate
                Crashlytics.crashlytics().log("CloudKit zone not found")
                NotificationCenter.default.post(
                    name: NSNotification.Name("CloudKitZoneNotFound"),
                    object: nil
                )
                
            default:
                // Generic CloudKit error
                Crashlytics.crashlytics().log("Generic CloudKit error: \(ckError.code)")
                NotificationCenter.default.post(
                    name: NSNotification.Name("CloudKitError"),
                    object: nil,
                    userInfo: ["error": error]
                )
            }
        } else {
            // Non-CloudKit error
            Crashlytics.crashlytics().setCustomValue("Non-CloudKit Error", forKey: "cloudkit_error_type")
        }
    }

    // Handle the notification that guest data has been cleared
    @objc private func handleGuestDataCleared() {
        print("Guest data cleared notification received")
        
        // Ensure any remaining Core Data objects are refreshed
        persistentContainer.viewContext.refreshAllObjects()
        
        // Verify account state is correctly set up after guest sign-out
        DispatchQueue.main.async {
            if !AuthManager.shared.isSignedIn {
                // If we're signed out, ensure we don't have a current account
                if AccountManager.shared.currentAccount != nil {
                    print("Resetting current account after guest sign-out")
                    // Clear current account reference by setting to nil
                    // This prevents the app from trying to load guest data
                    UserDefaults.standard.removeObject(forKey: "currentAccountId")
                }
            }
        }
    }

    // MARK: - iCloud Sync Handling
    
    // Register for background operation notifications
    private func registerBackgroundNotifications() {
        // Listen for guest data cleared notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGuestDataCleared),
            name: NSNotification.Name("GuestDataCleared"),
            object: nil
        )
    }

    // New method to check CloudKit sync status
    private func checkAccountStatus() {
        // Only check if user has enabled sync
        if UserDefaults.standard.bool(forKey: "isSyncEnabled") {
            // Verify the CloudKit container is available
            let container = CKContainer(identifier: "iCloud.com.rishiselarka.Spenly")
            container.accountStatus { status, error in
                if let error = error {
                    print("Error checking CloudKit account status: \(error.localizedDescription)")
                    return
                }
                
                DispatchQueue.main.async {
                    if status == .available {
                        // Account is available, verify sync toggle state matches
                        if !CloudKitSyncManager.shared.isSyncEnabled {
                            CloudKitSyncManager.shared.isSyncEnabled = true
                        }
                    } else if CloudKitSyncManager.shared.isSyncEnabled {
                        // Account is not available but sync is on - disable it
                        CloudKitSyncManager.shared.isSyncEnabled = false
                        
                        // Post notification about the state change
                        NotificationCenter.default.post(
                            name: NSNotification.Name("CloudKitUnavailable"),
                            object: nil,
                            userInfo: ["status": status]
                        )
                    }
                }
            }
        }
    }
} 
