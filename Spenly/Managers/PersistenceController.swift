import Foundation
import CoreData
import CloudKit

class PersistenceController {
    static let shared = PersistenceController()
    
    // Serialize persistent store reloads to avoid overlapping operations
    private let storeReloadQueue = DispatchQueue(label: "com.spenly.coredata.storeReload", qos: .userInitiated)
    private var isReloadInProgress = false
    
    // Add preview for SwiftUI previews
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        return controller
    }()
    
    lazy var container: NSPersistentCloudKitContainer = {
        // Begin initialization immediately on load to improve app startup time
        let container = NSPersistentCloudKitContainer(name: "Spenly")
        
        // Check if any of the persistent stores have already been loaded
        // If no descriptions exist, create a default one instead of crashing
        if container.persistentStoreDescriptions.isEmpty {
            print("Warning: No persistent store descriptions found, creating default")
            let defaultDescription = NSPersistentStoreDescription()
            defaultDescription.type = NSSQLiteStoreType
            defaultDescription.shouldAddStoreAsynchronously = false
            container.persistentStoreDescriptions = [defaultDescription]
        }
        
        // Get the current sync setting with proper fallback
        let isSyncEnabled: Bool
        if UserDefaults.standard.object(forKey: "isSyncEnabled") != nil {
            isSyncEnabled = UserDefaults.standard.bool(forKey: "isSyncEnabled")
        } else {
            // Default to false for new installations to avoid CloudKit issues
            isSyncEnabled = false
            UserDefaults.standard.set(false, forKey: "isSyncEnabled")
        }
        
        // Configure each persistent store with proper error prevention
        container.persistentStoreDescriptions.forEach { description in
            // Configure Core Data options first (required for both CloudKit and non-CloudKit)
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            
            // Configure CloudKit options only if sync is enabled and we're not in preview mode
            if isSyncEnabled && !ProcessInfo.processInfo.environment.keys.contains("XCODE_RUNNING_FOR_PREVIEWS") {
                // Verify CloudKit container identifier is valid
                guard !cloudKitContainerIdentifier.isEmpty else {
                    print("ERROR: CloudKit container identifier is empty")
                    return
                }
                
                // Create CloudKit container options with proper error handling
                let cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerIdentifier)
                
                // Configure CloudKit options for better reliability
                cloudKitContainerOptions.databaseScope = .private
            description.cloudKitContainerOptions = cloudKitContainerOptions
                
                print("✅ CloudKit container configured successfully for: \(cloudKitContainerIdentifier)")
            } else {
                // Ensure CloudKit options are nil when sync is disabled
                description.cloudKitContainerOptions = nil
                print("CloudKit sync disabled - container configured without CloudKit")
            }
            
            // Configure additional performance and reliability options
            description.shouldAddStoreAsynchronously = true
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            
            // Set transaction timeout to prevent deadlocks
            description.timeout = 30.0
        }
        
        // Load persistent stores with comprehensive error handling
        container.loadPersistentStores(completionHandler: { [weak self] (storeDescription, error) in
            if let error = error as NSError? {
                print("❌ CoreData persistent store load error: \(error), \(error.userInfo)")
                
                // Handle specific CloudKit-related errors
                self?.handleCoreDataError(error)
                
                // Post notification for errors that need UI handling
                DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("CoreDataError"),
                    object: nil,
                    userInfo: ["error": error]
                )
            }
            } else {
                print("✅ CoreData persistent store loaded successfully")
                // Initialize core data stack after successful load
                self?.initializeCoreData()
                
                // Validate CloudKit configuration if sync is enabled
                if UserDefaults.standard.bool(forKey: "isSyncEnabled") {
                    self?.validateCloudKitConfiguration()
                    // Kick an initial sync shortly after stores are live
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        CloudKitSyncManager.shared.forceSyncNow()
                    }
                }
            }
        })
        
        // Configure view context for optimal performance and safety
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        
        // Configure the view context for better UI responsiveness
        container.viewContext.shouldDeleteInaccessibleFaults = true
        container.viewContext.transactionAuthor = "app"
        
        // Set proper undo manager configuration
        container.viewContext.undoManager = nil // Disable undo for performance
        
        // Memory optimization settings
        container.viewContext.refreshAllObjects()
        
        return container
    }()
    
    private let cloudKitContainerIdentifier = "iCloud.com.rishiselarka.Spenly"
    
    init(inMemory: Bool = false) {
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        // Set merge policy - NSMergeByPropertyStoreTrumpMergePolicy is better for CloudKit
        // as it prioritizes server data over local changes, reducing conflicts
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        
        // Set up remote change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteStoreChange),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
        
        // Set up CloudKit account change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloudKitAccountChange),
            name: .CKAccountChanged,
            object: nil
        )
        
        // Listen for manual sync requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSyncNotification),
            name: NSNotification.Name("RefreshCloudKitSyncNotification"),
            object: nil
        )
        
        // Listen for CloudKit sync status changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloudKitSyncStatusChanged),
            name: NSNotification.Name("CloudKitSyncStatusChanged"),
            object: nil
        )
    }
    
    deinit {
        // Clean up NotificationCenter observers to prevent memory leaks
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc
    private func handleRemoteStoreChange(_ notification: Notification) {
        // Only refresh if we're not already in a save operation
        if !container.viewContext.hasChanges {
            container.viewContext.perform { [weak self] in
                self?.container.viewContext.refreshAllObjects()
            }
        }
    }
    
    @objc
    private func handleCloudKitAccountChange(_ notification: Notification) {
        // Handle CloudKit account changes (sign in/out)
        let container = CKContainer(identifier: cloudKitContainerIdentifier)
        container.accountStatus { [weak self] status, error in
            if let error = error {
                print("Error checking CloudKit account status: \(error.localizedDescription)")
                return
            }
            
            DispatchQueue.main.async {
                switch status {
                case .available:
                    print("CloudKit account is available")
                    // Refresh the view context to ensure we have the latest data
                    self?.container.viewContext.refreshAllObjects()
                    // Check if we need to associate the user with CloudKit
                    if let userID = AuthManager.shared.userID {
                        self?.associateUserWithCloudKit(userID: userID)
                    }
                case .noAccount:
                    print("No CloudKit account")
                    // Disable CloudKit syncing
                    CloudKitSyncManager.shared.isSyncEnabled = false
                case .restricted:
                    print("CloudKit account is restricted")
                    CloudKitSyncManager.shared.isSyncEnabled = false
                case .couldNotDetermine:
                    print("Could not determine CloudKit account status")
                case .temporarilyUnavailable:
                    print("temporarily unavailable")
                @unknown default:
                    print("Unknown CloudKit account status")
                }
            }
        }
    }
    
    @objc
    private func handleSyncNotification(_ notification: Notification) {
        container.viewContext.perform { [weak self] in
            guard let self = self else { return }
            
            // Refresh all objects to ensure we have latest data
            self.container.viewContext.refreshAllObjects()
            
            // Save any pending changes
            if self.container.viewContext.hasChanges {
                do {
                    try self.container.viewContext.save()
                    print("Successfully saved changes during sync")
                } catch {
                    print("Failed to save during sync: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @objc
    private func handleCloudKitSyncStatusChanged(_ notification: Notification) {
        guard let isEnabled = notification.userInfo?["isEnabled"] as? Bool else {
            return
        }
        
        // If sync was toggled, we need to reload the persistent stores
        print("CloudKit sync status changed to: \(isEnabled)")
        
        // Check if we need to rebuild the Core Data stack to enable/disable CloudKit
        let currentStoreHasCloudKit = container.persistentStoreDescriptions.first?.cloudKitContainerOptions != nil
        
        if isEnabled != currentStoreHasCloudKit {
            reloadPersistentStores(enableCloudKit: isEnabled)
        }
    }
    
    // Function to reload the persistent stores with or without CloudKit
    private func reloadPersistentStores(enableCloudKit: Bool) {
        print("🔄 Reloading persistent stores with CloudKit: \(enableCloudKit)")
        
        storeReloadQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Guard against overlapping reloads
            if self.isReloadInProgress {
                print("⏭️ Store reload already in progress, skipping new request")
                return
            }
            self.isReloadInProgress = true
            defer { self.isReloadInProgress = false }
            
            // Save any pending changes before reloading stores on the context's queue
            let viewContext = self.container.viewContext
            var saveError: Error?
            viewContext.performAndWait {
                if viewContext.hasChanges {
                    do { try viewContext.save(); print("✅ Saved pending changes before store reload") }
                    catch { saveError = error }
                }
            }
            if let error = saveError {
                print("❌ Failed to save before reloading stores: \(error.localizedDescription)")
            }
            
            // Notify UI that store reloading is starting
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("CoreDataReloadingStores"),
                    object: nil
                )
            }
            
            var reloadError: Error?
            
            // Perform the reload operation safely
            do {
                guard let currentStore = self.container.persistentStoreCoordinator.persistentStores.first,
                      let storeURL = currentStore.url else {
                    throw NSError(domain: "PersistenceController", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Could not get persistent store URL"
                    ])
                }
                
                print("🔧 Removing existing persistent store...")
                try self.container.persistentStoreCoordinator.remove(currentStore)
                
                print("🔧 Creating new store description...")
                let newDescription = NSPersistentStoreDescription(url: storeURL)
                newDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                newDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                if enableCloudKit && !ProcessInfo.processInfo.environment.keys.contains("XCODE_RUNNING_FOR_PREVIEWS") {
                    let cloudKitOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: self.cloudKitContainerIdentifier)
                    cloudKitOptions.databaseScope = .private
                    newDescription.cloudKitContainerOptions = cloudKitOptions
                    print("✅ CloudKit options configured for new store")
                } else {
                    newDescription.cloudKitContainerOptions = nil
                    print("✅ CloudKit options disabled for new store")
                }
                newDescription.shouldAddStoreAsynchronously = false
                newDescription.shouldMigrateStoreAutomatically = true
                newDescription.shouldInferMappingModelAutomatically = true
                newDescription.timeout = 30.0
                
                print("🔧 Reloading persistent store via loadPersistentStores to honor CloudKit options...")
                self.container.persistentStoreDescriptions = [newDescription]
                
                var loadError: Error?
                let group = DispatchGroup()
                group.enter()
                
                self.container.loadPersistentStores { _, error in
                    loadError = error
                    group.leave()
                }
                
                let result = group.wait(timeout: .now() + 45)
                if result == .timedOut {
                    throw NSError(domain: "PersistenceController", code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "Store reload timed out"
                    ])
                }
                
                if let error = loadError { throw error }
                
                print("✅ Successfully reloaded persistent store with CloudKit: \(enableCloudKit)")
            } catch {
                print("❌ Failed to reload persistent stores: \(error.localizedDescription)")
                reloadError = error
            }
            
            DispatchQueue.main.async {
                if let error = reloadError {
                    print("❌ Store reload failed, notifying UI...")
                    NotificationCenter.default.post(
                        name: NSNotification.Name("CoreDataError"),
                        object: nil,
                        userInfo: ["error": error]
                    )
                } else {
                    print("✅ Store reload successful, refreshing context...")
                    let currentAccountId = AccountManager.shared.currentAccount?.id
                    print("🔄 Preserving account selection: \(currentAccountId?.uuidString ?? "none")")
                    
                    // Save account ID to UserDefaults before any context changes
                    if let accountId = currentAccountId {
                        UserDefaults.standard.set(accountId.uuidString, forKey: "currentAccountId")
                    }
                    
                    // Notify views to release references before reset
                    NotificationCenter.default.post(
                        name: NSNotification.Name("CoreDataWillReset"),
                        object: nil
                    )
                    
                    // Refresh without full reset to preserve in-memory state
                    self.container.viewContext.refreshAllObjects()
                    UserDefaults.standard.set(enableCloudKit, forKey: "isSyncEnabled")
                    
                    // Restore account selection immediately on main thread
                    if let accountId = currentAccountId {
                        self.restoreAccountSelection(accountId: accountId)
                    }
                    
                    NotificationCenter.default.post(
                        name: NSNotification.Name("CoreDataReloadComplete"),
                        object: nil
                    )
                    
                    if enableCloudKit {
                        self.validateCloudKitConfiguration()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            CloudKitSyncManager.shared.forceSyncNow()
                        }
                    }
                }
            }
        }
    }
    
    func initializeCoreData() {
        // Initialize the category manager to set up default categories
        DispatchQueue.main.async {
            CategoryManager.shared.setupInitialCategories(context: self.container.viewContext)
            ContactManager.shared.setupInitialContacts(context: self.container.viewContext)
            // Clean duplicates and reconcile metrics at startup
            ContactManager.shared.cleanupDuplicateContacts(context: self.container.viewContext)
            ContactManager.shared.reconcileUsageCounts(context: self.container.viewContext)
        }
    }
    
    func save() {
        let context = container.viewContext
        
        // Check if there are changes before attempting to save
        guard context.hasChanges else { return }
        
        do {
            try context.save()
        } catch {
            print("Error saving Core Data context: \(error.localizedDescription)")
            
            // Notify UI of error
            NotificationCenter.default.post(
                name: NSNotification.Name("CoreDataError"),
                object: nil,
                userInfo: ["error": error]
            )
        }
    }
    
    // Create a background context for batch operations
    func backgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }
    
    // Optimize memory usage when memory warning received
    func handleMemoryWarning() {
        // Notify views to release references before reset
        NotificationCenter.default.post(
            name: NSNotification.Name("CoreDataWillReset"),
            object: nil
        )
        
        // Reset any unused contexts
        container.viewContext.refreshAllObjects()
        
        // Save changes before reset to prevent data loss
        if container.viewContext.hasChanges {
            do {
                try container.viewContext.save()
            } catch {
                print("❌ Failed to save before memory warning reset: \(error.localizedDescription)")
            }
        }
        
        // Cancel any long-running fetch requests
        // Explicitly discard any cached objects we don't need immediately
        container.viewContext.reset()
    }
    
    // Perform save on background thread with completion handler
    func performSave(_ context: NSManagedObjectContext, completion: ((Error?) -> Void)? = nil) {
        guard context.hasChanges else {
            completion?(nil)
            return
        }
        
        context.perform {
            do {
                try context.save()
                completion?(nil)
            } catch {
                print("Error saving context: \(error.localizedDescription)")
                NotificationCenter.default.post(
                    name: NSNotification.Name("CoreDataError"),
                    object: nil,
                    userInfo: ["error": error]
                )
                completion?(error)
            }
        }
    }
    
    // Background save with closure
    func backgroundSave(_ block: @escaping (NSManagedObjectContext) -> Void, completion: ((Error?) -> Void)? = nil) {
        let context = backgroundContext()
        context.perform {
            block(context)
            
            if context.hasChanges {
                do {
                    try context.save()
                    DispatchQueue.main.async {
                        completion?(nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        print("Background save error: \(error.localizedDescription)")
                        completion?(error)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion?(nil)
                }
            }
        }
    }
    
    // Batch delete function for performance optimization
    func batchDelete(entityName: String, predicate: NSPredicate? = nil) {
        let context = backgroundContext()
        
        context.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            if let predicate = predicate {
                fetchRequest.predicate = predicate
            }
            
            let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            batchDeleteRequest.resultType = .resultTypeObjectIDs
            
            do {
                let result = try context.execute(batchDeleteRequest) as? NSBatchDeleteResult
                if let objectIDs = result?.result as? [NSManagedObjectID] {
                    // Merge the changes to the view context
                    let changes = [NSDeletedObjectsKey: objectIDs]
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.container.viewContext])
                }
            } catch {
                print("Batch delete failed: \(error.localizedDescription)")
            }
        }
    }
    
    // Add a method to associate user ID with CloudKit records
    func associateUserWithCloudKit(userID: String) {
        let container = CKContainer(identifier: cloudKitContainerIdentifier)
        container.fetchUserRecordID { [weak self] recordID, error in
            if let error = error {
                self?.handleCloudKitError(error)
            } else if let recordID = recordID {
                print("Successfully associated user with CloudKit record ID: \(recordID.recordName)")
            }
        }
    }
    
    private func handleCoreDataError(_ error: NSError) {
        print("🔍 Analyzing Core Data error: \(error.localizedDescription)")
        
        switch error.code {
        case NSPersistentStoreIncompatibleVersionHashError:
            print("⚠️ Core Data version mismatch detected. Attempting to recover...")
            handleVersionMismatch()
            
        case NSPersistentStoreIncompatibleSchemaError:
            print("⚠️ Core Data schema incompatibility detected. Attempting to recover...")
            handleSchemaIncompatibility()
            
        case NSPersistentStoreOperationError:
            print("⚠️ Persistent store operation error. Checking CloudKit status...")
            handlePersistentStoreOperationError(error)
            
        default:
            print("❌ Unhandled Core Data error: \(error.localizedDescription)")
            
            // Check if this is a CloudKit-related error by domain or description
            if error.domain.contains("CloudKit") || 
               error.localizedDescription.contains("CloudKit") ||
               error.domain == "NSCloudKitMirroringDelegate" {
                print("⚠️ CloudKit mirroring error detected. Attempting to recover...")
                handleCloudKitMirroringError(error)
            }
        }
    }
    
    private func handleVersionMismatch() {
        // Implement proper version migration logic
        print("Attempting to recover from Core Data version mismatch")
        
        // Create a new persistent store description
        guard let storeURL = container.persistentStoreDescriptions.first?.url else {
            print("Could not get store URL")
            return
        }
        
        // Perform migration on background thread to avoid UI freezing
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // First notify UI that migration is starting
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("CoreDataMigrationStarted"),
                    object: nil
                )
            }
            
            do {
                // Remove the existing store
                let coordinator = self.container.persistentStoreCoordinator
                if let store = coordinator.persistentStore(for: storeURL) {
                    try coordinator.remove(store)
                }
                
                // Create a new store description with migration options
                let description = NSPersistentStoreDescription(url: storeURL)
                description.shouldMigrateStoreAutomatically = true
                description.shouldInferMappingModelAutomatically = true
                
                // Add the store with the new description
                let semaphore = DispatchSemaphore(value: 0)
                var migrationError: Error? = nil
                
                coordinator.addPersistentStore(with: description) { _, error in
                    migrationError = error
                    semaphore.signal()
                }
                
                // Wait for completion
                semaphore.wait()
                
                // Handle the result
                if let error = migrationError {
                    print("Migration failed: \(error.localizedDescription)")
                    
                    // Notify UI about migration failure
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("CoreDataMigrationFailed"),
                            object: nil,
                            userInfo: ["error": error]
                        )
                    }
                } else {
                    print("Migration successful")
                    
                    // Notify UI about successful migration
                    DispatchQueue.main.async {
                        // Reset the view context
                        self.container.viewContext.reset()
                        
                        // Notify success
                        NotificationCenter.default.post(
                            name: NSNotification.Name("CoreDataMigrationCompleted"),
                            object: nil
                        )
                    }
                }
            } catch {
                print("Error during migration: \(error.localizedDescription)")
                
                // Notify UI about migration error
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("CoreDataMigrationFailed"),
                        object: nil,
                        userInfo: ["error": error]
                    )
                }
            }
        }
    }
    
    private func handleSchemaIncompatibility() {
        // Implement schema migration with conflict resolution
        print("Attempting to recover from Core Data schema incompatibility")
        
        // This is more serious and might require data replacement
        guard let storeURL = container.persistentStoreDescriptions.first?.url else {
            print("Could not get store URL")
            return
        }
        
        // Perform recovery on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // First notify UI that recovery is starting
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("CoreDataRecoveryStarted"),
                    object: nil
                )
            }
            
            do {
                // Try to back up the store first if possible
                let fileManager = FileManager.default
                let backupURL = storeURL.deletingLastPathComponent().appendingPathComponent("backup_\(Date().timeIntervalSince1970).sqlite")
                
                if fileManager.fileExists(atPath: storeURL.path) {
                    try fileManager.copyItem(at: storeURL, to: backupURL)
                    print("Created backup at \(backupURL.path)")
                }
                
                // Remove all persistent stores
                let coordinator = self.container.persistentStoreCoordinator
                for store in coordinator.persistentStores {
                    try coordinator.remove(store)
                }
                
                // REMOVE this dangerous code:
                // if fileManager.fileExists(atPath: storeURL.path) {
                //     try fileManager.removeItem(at: storeURL)
                // }
                // Instead, notify the app for user action:
                NotificationCenter.default.post(
                    name: NSNotification.Name("DataRecoveryNeeded"),
                    object: nil,
                    userInfo: ["requiresUserAction": true]
                )
                
                // Create a new store description
                let description = NSPersistentStoreDescription(url: storeURL)
                description.shouldMigrateStoreAutomatically = true
                description.shouldInferMappingModelAutomatically = true
                
                // Add the store with the new description
                let semaphore = DispatchSemaphore(value: 0)
                var recoveryError: Error? = nil
                
                coordinator.addPersistentStore(with: description) { _, error in
                    recoveryError = error
                    semaphore.signal()
                }
                
                // Wait for completion
                semaphore.wait()
                
                if let error = recoveryError {
                    print("Recovery failed: \(error.localizedDescription)")
                    
                    // Notify UI about recovery failure
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("CoreDataRecoveryFailed"),
                            object: nil,
                            userInfo: ["error": error, "backupURL": backupURL]
                        )
                    }
                } else {
                    print("Recovery successful with new store")
                    
                    // Notify UI about successful recovery
                    DispatchQueue.main.async {
                        // Reset the view context
                        self.container.viewContext.reset()
                        self.initializeCoreData() // Reinitialize with default data
                        
                        // Notify success
                        NotificationCenter.default.post(
                            name: NSNotification.Name("CoreDataRecoveryCompleted"),
                            object: nil
                        )
                    }
                }
            } catch {
                print("Error during recovery: \(error.localizedDescription)")
                
                // Notify UI about recovery error
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("CoreDataRecoveryFailed"),
                        object: nil,
                        userInfo: ["error": error]
                    )
                }
            }
        }
    }
    
    private func handleContextSaveError(_ error: Error) {
        print("Error saving context: \(error.localizedDescription)")
        
        // Attempt recovery
        if let nsError = error as NSError? {
            switch nsError.code {
            case NSPersistentStoreIncompatibleVersionHashError:
                handleVersionMismatch()
            case NSPersistentStoreIncompatibleSchemaError:
                handleSchemaIncompatibility()
            default:
                // Notify user of error
                NotificationCenter.default.post(
                    name: NSNotification.Name("CoreDataError"),
                    object: nil,
                    userInfo: ["error": error]
                )
                
                // Attempt retry after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.retrySaveOperation()
                }
            }
        }
    }
    
    private func retrySaveOperation() {
        container.viewContext.perform { [weak self] in
            guard let self = self else { return }
            
            do {
                try self.container.viewContext.save()
                print("Successfully retried save operation")
            } catch {
                print("Failed to retry save operation: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleCloudKitError(_ error: Error) {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .quotaExceeded:
                // Handle quota exceeded
                NotificationCenter.default.post(
                    name: NSNotification.Name("CloudKitQuotaExceeded"),
                    object: nil
                )
                
                // Disable automatic sync temporarily
                CloudKitSyncManager.shared.isSyncEnabled = false
                
            case .networkFailure, .networkUnavailable:
                // Handle network issues
                NotificationCenter.default.post(
                    name: NSNotification.Name("CloudKitNetworkError"),
                    object: nil
                )
                // Attempt retry after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.retryCloudKitOperation()
                }
                
            case .serverResponseLost, .serviceUnavailable:
                // Handle server issues
                NotificationCenter.default.post(
                    name: NSNotification.Name("CloudKitServerError"),
                    object: nil
                )
                // Attempt retry after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    self?.retryCloudKitOperation()
                }
                
            case .partialFailure:
                // Handle partial failures - important for conflict resolution
                if let partialErrorDict = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [NSObject: CKError] {
                    handlePartialErrors(partialErrorDict)
                } else {
                    // If we can't get details, just retry
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                        self?.retryCloudKitOperation()
                    }
                }
                
            case .userDeletedZone:
                // User deleted their CloudKit zone - need to recreate
                recreateCloudKitZone()
                
            case .changeTokenExpired:
                // Handle expired change token - need to restart sync
                resetCloudKitSyncState()
                
            case .zoneNotFound:
                // Zone not found - need to create it
                recreateCloudKitZone()
                
            case .assetFileNotFound:
                // Handle missing asset files
                print("CloudKit asset file not found: \(error.localizedDescription)")
                
            default:
                // Handle other CloudKit errors
                print("CloudKit error: \(error.localizedDescription)")
                NotificationCenter.default.post(
                    name: NSNotification.Name("CloudKitError"),
                    object: nil,
                    userInfo: ["error": error]
                )
            }
        } else {
            // Handle non-CloudKit errors
            print("Non-CloudKit error during sync: \(error.localizedDescription)")
            NotificationCenter.default.post(
                name: NSNotification.Name("CloudKitError"),
                object: nil,
                userInfo: ["error": error]
            )
        }
    }
    
    // Handle partial errors in CloudKit operations
    private func handlePartialErrors(_ errors: [NSObject: CKError]) {
        for (_, error) in errors {
            switch error.code {
            case .serverRecordChanged:
                // Server has a newer version - need to handle conflict
                if let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                    print("Server has newer record: \(serverRecord.recordID.recordName)")
                    // Automatic conflict resolution will be handled by NSPersistentCloudKitContainer
                }
                
            case .unknownItem:
                // Item doesn't exist - usually not an issue for writes
                print("Unknown CloudKit item referenced")
                
            case .batchRequestFailed:
                // Try again with smaller batches
                print("Batch request failed, should retry with smaller batches")
                
            default:
                // Log other partial errors
                print("CloudKit partial error: \(error.localizedDescription)")
            }
        }
    }
    
    // Reset CloudKit sync state when tokens are expired
    private func resetCloudKitSyncState() {
        print("Resetting CloudKit sync state due to expired tokens")
        
        // Force refresh all objects
        container.viewContext.refreshAllObjects()
        
        // Disable and re-enable sync
        let wasEnabled = CloudKitSyncManager.shared.isSyncEnabled
        CloudKitSyncManager.shared.isSyncEnabled = false
        
        // If sync was enabled, re-enable it after a delay
        if wasEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                CloudKitSyncManager.shared.toggleSync(enabled: true)
            }
        }
    }
    
    // Recreate CloudKit zone if it was deleted or not found
    private func recreateCloudKitZone() {
        print("Recreating CloudKit zone")
        
        // Reset sync state first
        resetCloudKitSyncState()
        
        // The NSPersistentCloudKitContainer will handle recreation on next sync
    }
    
    private func retryCloudKitOperation() {
        // Refresh the persistent store
        container.viewContext.perform { [weak self] in
            guard let self = self else { return }
            
            do {
                try self.container.viewContext.save()
                print("Successfully retried CloudKit operation")
            } catch {
                print("Failed to retry CloudKit operation: \(error.localizedDescription)")
            }
        }
    }
    
    func removeDuplicateCategories(context: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Category")
        do {
            let allCategories = try context.fetch(fetchRequest)
            var unique: [String: NSManagedObject] = [:]
            var toDelete: [NSManagedObject] = []
            
            for category in allCategories {
                guard let name = category.value(forKey: "name") as? String,
                      let type = category.value(forKey: "type") as? String else { continue }
                let key = "\(name.lowercased())_\(type.lowercased())"
                if let existing = unique[key] {
                    // Reassign transactions to the existing category
                    if let transactions = category.value(forKey: "transactions") as? Set<NSManagedObject> {
                        for transaction in transactions {
                            transaction.setValue(existing, forKey: "category")
                        }
                    }
                    toDelete.append(category)
                } else {
                    unique[key] = category
                }
            }
            // Delete duplicates
            for category in toDelete {
                context.delete(category)
            }
            if context.hasChanges {
                try context.save()
            }
            print("Duplicate categories removed.")
        } catch {
            print("Error removing duplicate categories: \(error)")
        }
    }
    
    private func handleCloudKitMirroringError(_ error: NSError) {
        print("🔧 Handling CloudKit mirroring error...")
        
        // CloudKit mirroring errors can often be resolved by resetting sync state
        DispatchQueue.main.async {
            CloudKitSyncManager.shared.resetSyncState()
            
            // Notify user about the issue
            NotificationCenter.default.post(
                name: NSNotification.Name("CloudKitMirroringError"),
                object: nil,
                userInfo: ["error": error]
            )
        }
    }
    
    private func handlePersistentStoreOperationError(_ error: NSError) {
        print("🔧 Handling persistent store operation error...")
        
        // These errors often indicate CloudKit sync conflicts or schema issues
        if error.localizedDescription.contains("CloudKit") {
            handleCloudKitRelatedError(error)
        } else {
            // Generic persistent store error - attempt recovery
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("PersistentStoreError"),
                    object: nil,
                    userInfo: ["error": error]
                )
            }
        }
    }
    
    private func handleCloudKitRelatedError(_ error: NSError) {
        print("🔧 Handling CloudKit-related error...")
        
        DispatchQueue.main.async {
            // Temporarily disable CloudKit sync to prevent further issues
            let wasEnabled = CloudKitSyncManager.shared.isSyncEnabled
            CloudKitSyncManager.shared.isSyncEnabled = false
            
            // Attempt to recover after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                if wasEnabled {
                    // Try to re-enable sync after error recovery
                    CloudKitSyncManager.shared.toggleSync(enabled: true)
                }
            }
            
            // Notify about the CloudKit error
            NotificationCenter.default.post(
                name: NSNotification.Name("CloudKitError"),
                object: nil,
                userInfo: ["error": error]
            )
        }
    }
    
    private func validateCloudKitConfiguration() {
        print("🔍 Validating CloudKit configuration...")
        
        // Check if CloudKit container is properly configured
        guard let storeDescription = container.persistentStoreDescriptions.first else {
            print("❌ No persistent store description found")
            return
        }
        
        // Validate CloudKit container options
        if let cloudKitOptions = storeDescription.cloudKitContainerOptions {
            print("✅ CloudKit container options validated: \(cloudKitOptions.containerIdentifier)")
            
            // Test CloudKit container accessibility
            let ckContainer = CKContainer(identifier: cloudKitOptions.containerIdentifier)
            ckContainer.accountStatus { status, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ CloudKit container validation failed: \(error.localizedDescription)")
                        // Disable sync if container is not accessible
                        UserDefaults.standard.set(false, forKey: "isSyncEnabled")
                        CloudKitSyncManager.shared.isSyncEnabled = false
                    } else {
                        print("✅ CloudKit container validation successful, status: \(status)")
                    }
                }
            }
        } else {
            print("✅ CloudKit disabled - no container options to validate")
        }
    }
    
    private func restoreAccountSelection(accountId: UUID) {
        // Must run on main thread to update AccountManager
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Fetch the account from the refreshed context on viewContext's thread
            self.container.viewContext.perform {
                let fetchRequest = Account.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", accountId as CVarArg)
                
                do {
                    let accounts = try self.container.viewContext.fetch(fetchRequest)
                    if let restoredAccount = accounts.first {
                        DispatchQueue.main.async {
                            // Restore the account selection in AccountManager
                            AccountManager.shared.currentAccount = restoredAccount
                            UserDefaults.standard.set(accountId.uuidString, forKey: "currentAccountId")
                            
                            print("✅ Successfully restored account selection: \(restoredAccount.name ?? "unknown")")
                            
                            // Notify that account was restored
                            NotificationCenter.default.post(
                                name: NSNotification.Name("AccountChanged"),
                                object: restoredAccount
                            )
                        }
                    } else {
                        print("⚠️ Could not find account with ID \(accountId.uuidString) after store reload")
                        DispatchQueue.main.async {
                            // Fallback: load any available account
                            AccountManager.shared.ensureAccountInitialized(context: self.container.viewContext)
                        }
                    }
                } catch {
                    print("❌ Error restoring account selection: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        // Fallback: load any available account
                        AccountManager.shared.ensureAccountInitialized(context: self.container.viewContext)
                    }
                }
            }
        }
    }
} 
