import Foundation
import CloudKit
import CoreData
import Combine
import SwiftUI
import FirebaseCrashlytics

/// Manager responsible for CloudKit sync operations
class CloudKitSyncManager: ObservableObject {
    static let shared = CloudKitSyncManager()
    
    @Published var isSyncEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "isSyncEnabled") == nil {
            UserDefaults.standard.set(false, forKey: "isSyncEnabled")
            return false
        }
        return UserDefaults.standard.bool(forKey: "isSyncEnabled")
    }() {
        didSet {
            UserDefaults.standard.set(isSyncEnabled, forKey: "isSyncEnabled")
            UserDefaults.standard.synchronize()
            NotificationCenter.default.post(
                name: NSNotification.Name("CloudKitSyncStatusChanged"),
                object: nil,
                userInfo: ["isEnabled": isSyncEnabled]
            )
        }
    }
    
    @Published var syncStatus: SyncStatus = .idle
    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date? = UserDefaults.standard.object(forKey: "lastCloudKitSyncDate") as? Date
    
    private let cloudKitContainerIdentifier = "iCloud.com.rishiselarka.Spenly"
    private var subscriptions = Set<AnyCancellable>()
    private var syncTimer: Timer?
    
    enum SyncStatus {
        case idle
        case syncing
        case error(String)
        
        var description: String {
            switch self {
            case .idle:
                return "Idle"
            case .syncing:
                return "Syncing with iCloud..."
            case .error(let message):
                return message
            }
        }
    }
    
    private init() {
        setupObservers()
        
        #if targetEnvironment(simulator)
        print("Running in simulator - CloudKit sync will be limited")
        self.isSyncEnabled = false
        self.syncStatus = .error("iCloud sync disabled in simulator")
        #endif
    }
    
    private func setupObservers() {
        // Listen for CloudKit events
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleCloudKitNotification(notification)
            }
            .store(in: &subscriptions)
        
        // Listen for auth state changes
        NotificationCenter.default.publisher(for: NSNotification.Name("AuthStateChanged"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let isGuest = notification.userInfo?["isGuest"] as? Bool, isGuest {
                    self?.isSyncEnabled = false
                    self?.syncStatus = .idle
                }
            }
            .store(in: &subscriptions)
        
        // Listen for CloudKit account changes
        NotificationCenter.default.publisher(for: .CKAccountChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if self?.isSyncEnabled == true {
                    self?.checkAccountStatus()
                }
            }
            .store(in: &subscriptions)
        
        // Listen for app coming to foreground - only check status, don't force sync
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if self?.isSyncEnabled == true {
                    // Just verify account status, CloudKit will sync automatically
                    self?.syncStatus = .idle
                }
            }
            .store(in: &subscriptions)
    }
    
    func toggleSync(enabled: Bool) {
        isSyncEnabled = enabled
        
        if enabled {
            checkAccountStatus()
        } else {
            syncTimer?.invalidate()
            syncTimer = nil
            syncStatus = .idle
            isSyncing = false
        }
    }
    
    private func checkAccountStatus() {
        #if targetEnvironment(simulator)
        isSyncEnabled = false
        syncStatus = .error("iCloud sync disabled in simulator")
            NotificationCenter.default.post(
                name: NSNotification.Name("CloudKitSimulatorAlert"),
                object: nil
            )
        #else
        syncStatus = .syncing
        isSyncing = true
        
        let container = CKContainer(identifier: cloudKitContainerIdentifier)
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                self?.handleAccountStatus(status: status, error: error)
            }
        }
        #endif
    }
                
    private func handleAccountStatus(status: CKAccountStatus, error: Error?) {
                if let error = error {
            // Don't immediately disable sync on account check errors
            syncStatus = .error("iCloud error: \(error.localizedDescription)")
            isSyncing = false
            
                        // Report CloudKit account error to Crashlytics
                        Crashlytics.crashlytics().log("CloudKit account status error: \(error.localizedDescription)")
                        Crashlytics.crashlytics().record(error: error)
                        Crashlytics.crashlytics().setCustomValue("account_status_check", forKey: "cloudkit_operation")
                        
                        print("⚠️ Account status check failed, but keeping sync enabled: \(error.localizedDescription)")
                    return
                }
                
                switch status {
                case .available:
            syncStatus = .idle
            isSyncing = false
            setupPeriodicSync()
            // Trigger a simple sync
            forceSyncNow()
                    
                case .noAccount:
            // Only disable if we're CERTAIN there's no account
            syncStatus = .error("iCloud account not signed in")
            isSyncing = false
                    
                        NotificationCenter.default.post(
                            name: NSNotification.Name("CloudKitSignInRequired"),
                            object: nil
                        )
                        
                        print("🔐 No iCloud account detected - user needs to sign in")
                    
                case .restricted:
            // Don't disable sync for restricted - it might be temporary
            syncStatus = .error("iCloud account restricted")
            isSyncing = false
            print("🚫 iCloud account restricted - keeping sync enabled for when restriction lifts")
                    
                case .couldNotDetermine, .temporarilyUnavailable:
            // These are often temporary - don't disable sync
            syncStatus = .error("iCloud account temporarily unavailable")
            isSyncing = false
            print("⏳ iCloud account temporarily unavailable - will retry")
                    
                @unknown default:
            syncStatus = .error("Unknown iCloud account status")
            isSyncing = false
            print("❓ Unknown account status - keeping sync enabled")
        }
    }
    
    func forceSyncNow() {
        // Allow initial sync kick even if a flag says syncing, but debounce in short window
        if isSyncing { return }
        guard isSyncEnabled else { return }
        
        isSyncing = true
        syncStatus = .syncing
        
        // Trigger actual CloudKit sync through Core Data container
        let container = PersistenceController.shared.container
        let context = container.viewContext
        
        context.perform { [weak self] in
            guard let self = self else { return }
            
            do {
                // Save any pending changes first
                if context.hasChanges {
                    try context.save()
                    print("💾 Saved pending changes to trigger CloudKit export")
                }
                
                // Refresh all objects to pull latest from CloudKit
                context.refreshAllObjects()
                // Perform a lightweight fetch to stimulate initial import
                let fetch: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "Account")
                _ = try? context.fetch(fetch)
                
                // Force CloudKit import by requesting fresh data
                container.persistentStoreCoordinator.perform { [weak self] in
                    // The NSPersistentCloudKitContainer will handle the actual sync
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.updateLastSyncDate()
                        self.syncStatus = .idle
                        self.isSyncing = false
                        
                        print("✅ CloudKit sync operations initiated")
                        
                        // Post completion notification
                        NotificationCenter.default.post(
                            name: NSNotification.Name("CloudKitSyncCompleted"),
                            object: nil
                        )
                    }
                }
                
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    print("❌ CloudKit sync failed: \(error.localizedDescription)")
                    self.syncStatus = .error("Sync error: \(error.localizedDescription)")
                    self.isSyncing = false
                    
                    // Report CloudKit sync error to Crashlytics
                    Crashlytics.crashlytics().log("CloudKit sync failed: \(error.localizedDescription)")
                    Crashlytics.crashlytics().record(error: error)
                    Crashlytics.crashlytics().setCustomValue("force_sync", forKey: "cloudkit_operation")
                    
                    // Post error notification
                    NotificationCenter.default.post(
                        name: NSNotification.Name("CloudKitSyncError"),
                        object: nil,
                        userInfo: ["error": error]
                    )
                }
            }
        }
    }
    
    private func setupPeriodicSync() {
        syncTimer?.invalidate()
        
        // Note: CloudKit syncs automatically via NSPersistentCloudKitContainer
        // No need for periodic timer - saves battery significantly
        // Sync only triggers on data changes or manual user actions
        
        print("✅ CloudKit automatic sync enabled (event-driven, no polling)")
    }
    
    // Helper to determine if periodic sync is needed
    private func shouldPerformPeriodicSync() -> Bool {
        let context = PersistenceController.shared.container.viewContext
        
        // Check if there are unsaved changes
        if context.hasChanges {
            return true
        }
        
        // Check if it's been more than 2 hours since last sync
        if let lastSync = lastSyncDate {
            let timeSinceLastSync = Date().timeIntervalSince(lastSync)
            return timeSinceLastSync > (2 * 60 * 60) // 2 hours
        }
        
        // If we've never synced, do it
        return lastSyncDate == nil
    }
    
    private func updateLastSyncDate() {
        let currentDate = Date()
        lastSyncDate = currentDate
        UserDefaults.standard.set(currentDate, forKey: "lastCloudKitSyncDate")
    }
    
    private func handleCloudKitNotification(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] 
                as? NSPersistentCloudKitContainer.Event else {
            return
        }
            
            switch event.type {
            case .setup:
                if event.succeeded {
                print("✅ CloudKit setup completed successfully")
                DispatchQueue.main.async { [weak self] in
                    if self?.syncStatus == .syncing {
                        self?.syncStatus = .idle
                        self?.isSyncing = false
                    }
                }
                } else if let error = event.error {
                print("❌ CloudKit setup failed: \(error.localizedDescription)")
                handleCloudKitError(error)
                DispatchQueue.main.async { [weak self] in
                    self?.syncStatus = .error("Setup error: \(error.localizedDescription)")
                    self?.isSyncing = false
                    // Notify AuthManager of CloudKit error
                    NotificationCenter.default.post(name: NSNotification.Name("CloudKitSyncError"), object: nil)
                }
            }
            
        case .import:
            if event.succeeded {
                print("✅ CloudKit import completed successfully")
                DispatchQueue.main.async { [weak self] in
                    self?.syncStatus = .idle
                    self?.isSyncing = false
                    self?.lastSyncDate = Date()
                    
                    // CRITICAL: Notify AuthManager that import completed
                    NotificationCenter.default.post(name: NSNotification.Name("CloudKitImportCompleted"), object: nil)
                }
            } else if let error = event.error {
                print("❌ CloudKit import failed: \(error.localizedDescription)")
                handleCloudKitError(error)
                DispatchQueue.main.async { [weak self] in
                    self?.syncStatus = .error("Import error: \(error.localizedDescription)")
                    self?.isSyncing = false
                    // Notify AuthManager of CloudKit error
                    NotificationCenter.default.post(name: NSNotification.Name("CloudKitSyncError"), object: nil)
                    }
                }
            
        case .export:
            if event.succeeded {
                print("✅ CloudKit export completed successfully")
                DispatchQueue.main.async { [weak self] in
                    self?.syncStatus = .idle
                    self?.isSyncing = false
                    self?.lastSyncDate = Date()
                }
            } else if let error = event.error {
                print("❌ CloudKit export failed: \(error.localizedDescription)")
                handleCloudKitError(error)
        DispatchQueue.main.async { [weak self] in
                    self?.syncStatus = .error("Export error: \(error.localizedDescription)")
                    self?.isSyncing = false
                }
            }
            
        @unknown default:
            print("Unknown CloudKit event type: \(event.type)")
        }
    }
    
    private func handleCloudKitError(_ error: Error) {
        print("🔥 CloudKit Error: \(error.localizedDescription)")
        
        // Report CloudKit error to Crashlytics
        Crashlytics.crashlytics().log("CloudKit error in sync manager: \(error.localizedDescription)")
        Crashlytics.crashlytics().record(error: error)
        
        // Handle specific CloudKit error types
        if let ckError = error as? CKError {
            // Set specific error context for Crashlytics
            Crashlytics.crashlytics().setCustomValue(ckError.code.rawValue, forKey: "cloudkit_error_code")
            Crashlytics.crashlytics().setCustomValue(ckError.localizedDescription, forKey: "cloudkit_error_description")
            
            switch ckError.code {
            case .partialFailure:
                print("🔄 Partial failure - some records failed, continuing sync")
                Crashlytics.crashlytics().setCustomValue("partial_failure", forKey: "cloudkit_error_category")
                // DON'T disable sync for partial failures - they're normal
                return
                
            case .networkUnavailable, .networkFailure:
                print("🌐 Network issue - CloudKit will retry automatically")
                Crashlytics.crashlytics().setCustomValue("network_error", forKey: "cloudkit_error_category")
                // DON'T disable sync for network issues - they're temporary
                return
                
            case .quotaExceeded:
                print("💾 iCloud storage quota exceeded")
                Crashlytics.crashlytics().setCustomValue("quota_exceeded", forKey: "cloudkit_error_category")
                // Show user-facing error but keep sync enabled
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("CloudKitQuotaExceeded"),
                        object: nil,
                        userInfo: ["error": error]
                    )
                }
                return
                
            case .accountTemporarilyUnavailable:
                print("⏰ iCloud account temporarily unavailable")
                Crashlytics.crashlytics().setCustomValue("account_unavailable", forKey: "cloudkit_error_category")
                // DON'T disable sync - wait for account to become available
                return
                
            case .serviceUnavailable:
                print("🚫 CloudKit service unavailable")
                Crashlytics.crashlytics().setCustomValue("service_unavailable", forKey: "cloudkit_error_category")
                // DON'T disable sync - service will come back
                return
                
            default:
                print("❓ Other CloudKit error: \(ckError.localizedDescription)")
                Crashlytics.crashlytics().setCustomValue("other_error", forKey: "cloudkit_error_category")
            }
        } else {
            // Non-CloudKit error
            Crashlytics.crashlytics().setCustomValue("non_cloudkit_error", forKey: "cloudkit_error_category")
        }
        
        // Only post generic error notification for truly problematic errors
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("CloudKitError"),
                object: nil,
                userInfo: ["error": error]
            )
        }
    }
    
    func initializeCloudKitSchemaIfNeeded() {
        #if DEBUG
        // Only initialize schema in development builds
        print("🔧 Initializing CloudKit schema for development...")
        
        let container = PersistenceController.shared.container
        do {
            try container.initializeCloudKitSchema(options: [])
            print("✅ CloudKit schema initialized successfully")
        } catch {
            print("❌ Failed to initialize CloudKit schema: \(error.localizedDescription)")
            Crashlytics.crashlytics().log("CloudKit schema initialization failed: \(error.localizedDescription)")
            Crashlytics.crashlytics().record(error: error)
        }
        #else
        print("📱 Production build - CloudKit schema should already be deployed")
        #endif
    }
    
    func forceInitialDataRestore() {
        guard isSyncEnabled else { 
            print("⏭️ CloudKit sync disabled - skipping initial data restore")
            return 
        }
        
        print("🔄 Starting initial data restore from iCloud...")
        syncStatus = .syncing
        isSyncing = true
        
        // Force CloudKit to perform a complete import
        let context = PersistenceController.shared.container.viewContext
        context.perform { [weak self] in
            // Refresh all objects to trigger CloudKit import
            context.refreshAllObjects()
            
            // Reset context to force fresh import
            context.reset()
            
            DispatchQueue.main.async {
                print("📱 Initial data restore triggered - waiting for import...")
                
                // Extended timeout for initial data restore
                DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
                    if self?.isSyncing == true {
                        self?.isSyncing = false
                        self?.syncStatus = .idle
                        print("⏰ Initial restore timeout - data may still be syncing in background")
                    }
                }
            }
        }
    }
    
    func resetSyncState() {
        DispatchQueue.main.async { [weak self] in
            self?.syncStatus = .idle
            self?.isSyncing = false
            self?.syncTimer?.invalidate()
            self?.syncTimer = nil
            
            print("✅ CloudKit sync state reset")
        }
    }
    
    // MEMORY LEAK FIX: Add deinit to properly cleanup resources
    deinit {
        syncTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

// Extension to make SyncStatus conform to Equatable
extension CloudKitSyncManager.SyncStatus: Equatable {
    static func == (lhs: CloudKitSyncManager.SyncStatus, rhs: CloudKitSyncManager.SyncStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.syncing, .syncing):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
} 
 
 