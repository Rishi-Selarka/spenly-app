import Foundation
import AuthenticationServices
import CryptoKit
import SwiftUI
import CloudKit
import CoreData
import UserNotifications
import AppTrackingTransparency
import FirebaseCrashlytics

class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isSignedIn = false
    @Published var isGuest = false
    @Published var userID: String?
    @Published var userName: String?
    @Published var userEmail: String?
    
    // Add data restoration state management
    @Published var showDataRestorationAlert = false
    @Published var foundPreviousData = false
    @Published var restorationUserID: String?
    @Published var estimatedDataCount: String = ""
    
    @AppStorage("isUserSignedIn") private var isUserSignedIn = false
    @AppStorage("isGuestUser") private var isGuestUser = false
    // Secure storage moved to Keychain
    private var storedUserID: String? {
        get { KeychainHelper.retrieve(forKey: "userIdentifier") }
        set { 
            if let value = newValue {
                KeychainHelper.store(value, forKey: "userIdentifier")
            } else {
                KeychainHelper.delete(forKey: "userIdentifier")
            }
        }
    }
    
    private var storedUserName: String? {
        get { KeychainHelper.retrieve(forKey: "userName") }
        set { 
            if let value = newValue {
                KeychainHelper.store(value, forKey: "userName")
            } else {
                KeychainHelper.delete(forKey: "userName")
            }
        }
    }
    
    private var storedUserEmail: String? {
        get { KeychainHelper.retrieve(forKey: "userEmail") }
        set { 
            if let value = newValue {
                KeychainHelper.store(value, forKey: "userEmail")
            } else {
                KeychainHelper.delete(forKey: "userEmail")
            }
        }
    }
    // Secure storage moved to Keychain
    private var lastSignedInUserID: String? {
        get { KeychainHelper.retrieve(forKey: "lastSignedInUserID") }
        set { 
            if let value = newValue {
                KeychainHelper.store(value, forKey: "lastSignedInUserID")
            } else {
                KeychainHelper.delete(forKey: "lastSignedInUserID")
            }
        }
    }
    
    private var currentNonce: String?
    private let persistenceController = PersistenceController.shared
    
    // Add state tracking to prevent duplicate ATT requests
    private var hasRequestedATT = false
    private let attRequestQueue = DispatchQueue(label: "att-request", qos: .userInitiated)
    
    // Add state tracking to prevent duplicate operations
    private var isSettingUpAccount = false
    private let setupQueue = DispatchQueue(label: "account-setup", qos: .userInitiated)
    private var expectingCloudRestore = false
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private init() {
        // Load saved authentication state
        self.isSignedIn = isUserSignedIn
        self.isGuest = isGuestUser
        self.userID = storedUserID
        self.userName = storedUserName
        self.userEmail = storedUserEmail
        
        // If user is signed in with Apple, verify CloudKit status ONLY if user enabled sync
        if isSignedIn && !isGuest {
            if CloudKitSyncManager.shared.isSyncEnabled {
                checkAccountStatus()
                // Check if this is a fresh install that might need data restoration
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    self?.checkForDataRestorationOnStartup()
                }
            }
        }
    }
    
    private func checkForDataRestorationOnStartup() {
        guard CloudKitSyncManager.shared.isSyncEnabled else { return }
        
        // Check if app has very little data (might be fresh install)
        let viewContext = PersistenceController.shared.container.viewContext
        
        let accountFetchRequest = NSFetchRequest<Account>(entityName: "Account")
        let transactionFetchRequest = NSFetchRequest<Transaction>(entityName: "Transaction")
        
        do {
            let accountCount = try viewContext.count(for: accountFetchRequest)
            let transactionCount = try viewContext.count(for: transactionFetchRequest)
            
            // If we have very little data, try to restore from iCloud
            if accountCount <= 1 && transactionCount == 0 {
                print("🔄 Fresh install detected - attempting data restoration from iCloud")
                CloudKitSyncManager.shared.forceInitialDataRestore()
            }
        } catch {
            print("❌ Error checking for data restoration: \(error.localizedDescription)")
        }
    }
    
    func prepareSignInWithAppleRequest() -> ASAuthorizationAppleIDRequest {
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        
        // Generate nonce for security
        let nonce = randomNonceString()
        currentNonce = nonce
        request.nonce = sha256(nonce)
        
        return request
    }
    
    func handleSignInWithAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let _ = currentNonce else {
                return
            }
            
            // Save user information
            let userIdentifier = appleIDCredential.user
            
            var name: String?
            if let fullName = appleIDCredential.fullName,
               let givenName = fullName.givenName,
               let familyName = fullName.familyName {
                name = "\(givenName) \(familyName)"
            }
            
            let email = appleIDCredential.email
            
            // Store temporary user details (don't save session yet)
            self.userName = name
            self.userEmail = email
            
            // CRITICAL FIX: Check for previous data on MAIN thread to ensure popup shows
            DispatchQueue.main.async { [weak self] in
                print("🔍 Starting comprehensive data check for Apple ID: \(userIdentifier)")
                self?.checkForPreviousDataOnMainThread(userIdentifier: userIdentifier) { hasPreviousData in
                    DispatchQueue.main.async {
                        if hasPreviousData {
                            // Show data restoration popup - this will handle auth state when user decides
                            print("✅ Showing data restoration popup for Apple ID: \(userIdentifier)")
                            self?.showDataRestorationAlert = true
                        } else {
                            // No previous data, proceed with normal fresh setup
                            print("ℹ️ No previous data found, proceeding with fresh sign-in")
                            self?.proceedWithFreshSignIn(userIdentifier: userIdentifier, name: name, email: email)
                        }
                    }
                }
            }
            
        case .failure(let error):
            print("Sign in with Apple failed: \(error.localizedDescription)")
        }
    }
    
    func signOut() {
        // Store the current user ID before signing out for potential future sign-in
        lastSignedInUserID = userID
        
        // Save the guest status before we clear it
        let wasGuest = isGuest
        
        // Explicitly preserve data for Apple ID users
        preserveCurrentUserData()
        
        // First clear authentication state (prevents race conditions)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update state variables first
            self.isSignedIn = false
            self.isGuest = false
            self.userID = nil
            self.userName = nil
            self.userEmail = nil
            
            // Clear stored values but keep lastSignedInUserID
            self.isUserSignedIn = false
            self.isGuestUser = false
            self.storedUserID = nil
            self.storedUserName = nil
            self.storedUserEmail = nil
            
            // Clear Firebase Crashlytics user identification
            Crashlytics.crashlytics().setUserID(nil)
            Crashlytics.crashlytics().setCustomValue("signed_out", forKey: "user_type")
            Crashlytics.crashlytics().setCustomValue(Date().timeIntervalSince1970, forKey: "sign_out_timestamp")
            
            print("✅ Firebase Crashlytics user data cleared on sign out")
            
            // Reset AccountManager state for next sign-in
            AccountManager.shared.resetLoadedState()
            
            // Only clear the current account ID if this was a guest
            if wasGuest {
            UserDefaults.standard.removeObject(forKey: "currentAccountId")
            }
            
            UserDefaults.standard.synchronize()
            
            // IMPORTANT: For guest users, we'll clear data in a separate step AFTER auth state is cleared
            if wasGuest {
                // Disable CloudKit sync before clearing guest data to avoid warnings
                CloudKitSyncManager.shared.isSyncEnabled = false
                
                // Use a delay to allow auth state to update first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    
                    // Clear CoreData for guest users only - safely
                    self.safelyClearGuestData()
                    
                    // After safely clearing data, notify that guest data was cleared
                    NotificationCenter.default.post(
                        name: NSNotification.Name("GuestDataCleared"),
                        object: nil
                    )
                }
            }
            
            // Notify that auth state has changed - include wasGuest flag
            NotificationCenter.default.post(
                name: NSNotification.Name("AuthStateChanged"),
                object: nil,
                userInfo: ["wasGuest": wasGuest]
            )
        }
    }
    
    // Safer method to clear guest data when signing out
    private func safelyClearGuestData() {
        let viewContext = PersistenceController.shared.container.viewContext
        
        // Create a background context for user operations
        let backgroundContext = PersistenceController.shared.backgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        
        backgroundContext.perform {
            do {
                print("Safely clearing guest data...")
                
                // Find guest accounts first - they should have no user associated
                let accountFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Account")
                accountFetchRequest.predicate = NSPredicate(format: "user == nil")
                
                // Get account IDs for deletion of transactions
                let accountObjectsFetchRequest = NSFetchRequest<Account>(entityName: "Account")
                accountObjectsFetchRequest.predicate = NSPredicate(format: "user == nil")
                let guestAccounts = try backgroundContext.fetch(accountObjectsFetchRequest)
                
                // Record the number of accounts found
                print("Found \(guestAccounts.count) guest accounts to clear")
                
                // If we found guest accounts, delete their transactions first
                if !guestAccounts.isEmpty {
                    // Delete transactions first using batch delete for each account
                    for account in guestAccounts {
                        if let accountID = account.id {
                            let transactionsFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Transaction")
                            transactionsFetchRequest.predicate = NSPredicate(format: "account.id == %@", accountID as CVarArg)
                            
                            let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: transactionsFetchRequest)
                            batchDeleteRequest.resultType = .resultTypeObjectIDs
                            
                            let result = try backgroundContext.execute(batchDeleteRequest) as? NSBatchDeleteResult
                            if let objectIDs = result?.result as? [NSManagedObjectID] {
                                let changes = [NSDeletedObjectsKey: objectIDs]
                                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
                            }
                        }
                    }
                    
                    // Now delete all guest accounts using a batch delete
                    let batchDeleteAccounts = NSBatchDeleteRequest(fetchRequest: accountFetchRequest)
                    batchDeleteAccounts.resultType = .resultTypeObjectIDs
                    
                    let accountResult = try backgroundContext.execute(batchDeleteAccounts) as? NSBatchDeleteResult
                    if let accountObjectIDs = accountResult?.result as? [NSManagedObjectID] {
                        let changes = [NSDeletedObjectsKey: accountObjectIDs]
                        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
                    }
                    
                    print("Guest accounts and transactions cleared successfully")
                } else {
                    print("No guest accounts found to clear")
                }
                
                // Only delete custom categories if no Apple ID accounts exist
                let userFetchRequest = NSFetchRequest<User>(entityName: "User")
                let userCount = try backgroundContext.count(for: userFetchRequest)
                
                if userCount == 0 {
                    // Safe to delete custom categories when no users exist
                    let categoryFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Category")
                    categoryFetchRequest.predicate = NSPredicate(format: "isCustom == YES")
                    
                    // Use batch delete for categories too
                    let batchDeleteCategories = NSBatchDeleteRequest(fetchRequest: categoryFetchRequest)
                    batchDeleteCategories.resultType = .resultTypeObjectIDs
                    
                    let categoryResult = try backgroundContext.execute(batchDeleteCategories) as? NSBatchDeleteResult
                    if let categoryObjectIDs = categoryResult?.result as? [NSManagedObjectID] {
                        let changes = [NSDeletedObjectsKey: categoryObjectIDs]
                        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
                    }
                    
                    print("Custom categories cleared")
                }
                
                // Final save to ensure any remaining changes are persisted
                if backgroundContext.hasChanges {
                    try backgroundContext.save()
                }
                
            } catch {
                print("Error safely clearing guest data: \(error.localizedDescription)")
                backgroundContext.rollback()
            }
        }
    }
    
    // Legacy method kept for compatibility
    private func clearGuestData() {
        // Delegate to the new safer method
        safelyClearGuestData()
    }
    
    func signInAsGuest() {
        // Get a strong reference to the persistence controller
        let persistenceController = self.persistenceController
        let viewContext = persistenceController.container.viewContext
        
        viewContext.perform {
            do {
                // First, ensure we clean up any existing data
                let transactionFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Transaction")
                let accountFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Account")
                let categoryFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Category")
                categoryFetchRequest.predicate = NSPredicate(format: "isCustom == YES")
                
                // Delete transactions first (since they depend on accounts)
                let batchDeleteTransactions = NSBatchDeleteRequest(fetchRequest: transactionFetchRequest)
                try viewContext.execute(batchDeleteTransactions)
                
                // Delete accounts
                let batchDeleteAccounts = NSBatchDeleteRequest(fetchRequest: accountFetchRequest)
                try viewContext.execute(batchDeleteAccounts)
                
                // Delete only custom categories
                let batchDeleteCategories = NSBatchDeleteRequest(fetchRequest: categoryFetchRequest)
                try viewContext.execute(batchDeleteCategories)
                
                // Save changes after cleanup
                try viewContext.save()
                
                // Set guest state first to prevent Apple ID user association
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    // Update auth state first
                    self.isGuest = true
                    self.isSignedIn = true
                    self.isGuestUser = true
                    self.isUserSignedIn = true
                    
                    // Set guest user identification for Firebase Crashlytics
                    let guestUserID = "guest_\(UUID().uuidString)"
                    Crashlytics.crashlytics().setUserID(guestUserID)
                    Crashlytics.crashlytics().setCustomValue("guest_user", forKey: "user_type")
                    Crashlytics.crashlytics().setCustomValue(Date().timeIntervalSince1970, forKey: "sign_in_timestamp")
                    
                    #if DEBUG
            print("✅ Firebase Crashlytics guest user identification set: \(guestUserID)")
            #endif
                    
                    // NOW use centralized account initialization instead of direct creation
                    AccountManager.shared.ensureAccountInitialized(context: viewContext) { guestAccount in
                        if let account = guestAccount {
                            print("✅ Guest account initialized via centralized system: \(account.name ?? "unknown")")
                    
                    // Disable CloudKit sync for guest
                    CloudKitSyncManager.shared.isSyncEnabled = false
                    
                            // Request notification permissions (which will chain to ATT permission)
                    self.requestNotificationPermissionsIfNeeded()
                    
                    // Notify auth state change
                    NotificationCenter.default.post(
                        name: NSNotification.Name("AuthStateChanged"),
                        object: nil,
                        userInfo: ["isGuest": true]
                    )
                            
                            // Notify that account was created/changed
                            NotificationCenter.default.post(
                                name: NSNotification.Name("AccountChanged"),
                                object: account
                            )
                        } else {
                            print("❌ Failed to initialize guest account via centralized system")
                            // Reset state on error
                            self.isGuest = false
                            self.isSignedIn = false
                            self.isGuestUser = false
                            self.isUserSignedIn = false
                        }
                    }
                }
                
            } catch {
                print("Failed to setup guest account: \(error.localizedDescription)")
                // Reset state on error
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.isGuest = false
                    self.isSignedIn = false
                    self.isGuestUser = false
                    self.isUserSignedIn = false
                }
            }
        }
    }
    
    func deleteAccount(completion: ((Bool) -> Void)? = nil) {
        // Check if the user is not signed in or is a guest
        guard isSignedIn, !isGuest, let userID = self.userID else {
            completion?(false)
            return
        }
        
        print("🗑️ Starting account deletion for Apple ID: \(userID)")
        
        deleteLocalCoreData(userID: userID) { success in
            completion?(success)
        }
    }
    
    private func deleteLocalCoreData(userID: String, completion: @escaping (Bool) -> Void) {
        print("🗑️ STEP 2: Deleting user-specific data AND CloudKit data...")
        
        let viewContext = PersistenceController.shared.container.viewContext
        
        viewContext.perform {
            do {
                // Find the User entity for this Apple ID
                let userFetchRequest = NSFetchRequest<User>(entityName: "User")
                userFetchRequest.predicate = NSPredicate(format: "appleUserIdentifier == %@", userID)
                
                if let userEntity = try viewContext.fetch(userFetchRequest).first {
                    print("🗑️ Deleting user-specific data...")
                    
                    // Find all accounts associated with this user
                    let userAccountsFetchRequest = Account.fetchRequest()
                    userAccountsFetchRequest.predicate = NSPredicate(format: "user == %@", userEntity)
                    let userAccounts = try viewContext.fetch(userAccountsFetchRequest)
                    
                    // Delete all transactions for each account
                    for account in userAccounts {
                        if let transactions = account.transactions as? Set<Transaction> {
                            for transaction in transactions {
                                viewContext.delete(transaction)
                            }
                        }
                        viewContext.delete(account)
                    }
                    
                    // Delete the user entity
                    viewContext.delete(userEntity)
                    
                    // Save local deletions first
                    try viewContext.save()
                    print("✅ Local Core Data deleted")
                    
                    // CRITICAL: Now delete CloudKit data if sync was enabled
                    if UserDefaults.standard.bool(forKey: "isSyncEnabled") {
                        print("🗑️ STEP 3: Purging CloudKit data...")
                        self.purgeCloudKitUserData(userID: userID) { cloudKitSuccess in
                            DispatchQueue.main.async {
                                if cloudKitSuccess {
                                    print("✅ CloudKit data purged successfully")
                                } else {
                                    print("⚠️ CloudKit data purging encountered issues, but proceeding with account deletion")
                                }
                                
                                // Continue with the rest of account deletion
                                self.finalizeAccountDeletion(userID: userID, completion: completion)
                            }
                        }
                    } else {
                        // No CloudKit sync, proceed directly
                        DispatchQueue.main.async {
                            self.finalizeAccountDeletion(userID: userID, completion: completion)
                        }
                    }
                    
                } else {
                    print("⚠️ User entity not found")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                }
                
            } catch {
                print("❌ Failed to delete user data: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }
    
    /// NEW: Prefer Core Data mirroring to purge user data
    private func purgeCloudKitUserData(userID: String, completion: @escaping (Bool) -> Void) {
        guard CloudKitSyncManager.shared.isSyncEnabled else {
            print("CloudKit sync not enabled, skipping CloudKit purge")
            completion(true)
            return
        }
        
        // Rely on NSPersistentCloudKitContainer mirroring: local deletes already saved.
        // Kick a sync to export tombstones; avoid manual CK operations to prevent desync.
        print("🗑️ Triggering CloudKit export via Core Data mirroring for user: \(userID)")
        CloudKitSyncManager.shared.forceSyncNow()
        
        // Provide a bounded completion; actual export continues in background.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            completion(true)
        }
    }
    
    /// Finalize account deletion after CloudKit cleanup
    private func finalizeAccountDeletion(userID: String, completion: @escaping (Bool) -> Void) {
        // CRITICAL: Ensure system categories exist after deletion
        CategoryManager.shared.setupInitialCategories(context: PersistenceController.shared.container.viewContext)
        
        DispatchQueue.main.async {
            // NOW disable CloudKit sync (after data is purged)
            CloudKitSyncManager.shared.isSyncEnabled = false
            
            // Clear user-specific UserDefaults
            self.clearUserSpecificDefaults(userID: userID)
    
            // Sign out the user
            self.signOut()
    
            // Clear account manager state
            AccountManager.shared.resetLoadedState()
            AccountManager.shared.currentAccount = nil
            
            print("✅ Account deletion completed - ready for fresh sign-in")
            completion(true)
        }
    }
    
    @MainActor
    private func clearUserSpecificDefaults(userID: String) {
        print("🗑️ Clearing user-specific settings...")
        
        // Clear only user-specific keys, keep system defaults
        UserDefaults.standard.removeObject(forKey: "userIdentifier")
        UserDefaults.standard.removeObject(forKey: "userName")
        UserDefaults.standard.removeObject(forKey: "userEmail")
        UserDefaults.standard.removeObject(forKey: "isUserSignedIn")
        UserDefaults.standard.removeObject(forKey: "currentAccountId")
        UserDefaults.standard.removeObject(forKey: "isSyncEnabled")
        UserDefaults.standard.removeObject(forKey: "lastCloudKitSyncDate")
        
        // Clear the data restoration flag for this user
        let preservationKey = "hasDataForAppleID-\(userID)"
        UserDefaults.standard.removeObject(forKey: preservationKey)
        
        // Reset IAP local entitlements so UI returns to non-premium immediately
        IAPManager.shared.resetLocalEntitlements()
        
        UserDefaults.standard.synchronize()
        print("✅ User settings cleared")
    }
    
    // MARK: - CloudKit Integration
    
    private func setupCloudKitSync(userID: String) {
        // Only setup CloudKit sync for non-guest users
        guard !isGuest else { return }
        
        // Check iCloud account status
        checkAccountStatus()
    }
    
    private func checkAccountStatus() {
        // Only check CloudKit status for non-guest users
        guard !isGuest else { return }
        
        // Verify the user's iCloud account status
        let container = CKContainer(identifier: "iCloud.com.rishiselarka.Spenly")
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    // iCloud is available, no need to print
                    break
                case .noAccount:
                    self?.handleNoiCloudAccount()
                case .restricted:
                    self?.handleRestrictediCloudAccess()
                case .couldNotDetermine:
                    if let error = error {
                        print("Could not determine iCloud status: \(error.localizedDescription)")
                    }
                default:
                    break
                }
            }
        }
    }
    
    private func handleNoiCloudAccount() {
        // Handle case where user doesn't have an iCloud account
        print("No iCloud account found")
    }
    
    private func handleRestrictediCloudAccess() {
        // Handle case where iCloud access is restricted
        print("iCloud access is restricted")
    }
    
    // MARK: - Helper Methods
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                guard errorCode == errSecSuccess else {
                    print("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                    return 0
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
    
    private func createDefaultAccount(context: NSManagedObjectContext) {
        // Use centralized account initialization instead of creating accounts directly
        AccountManager.shared.ensureAccountInitialized(context: context)
    }
    
    private func reinitializeDefaultCategories(context: NSManagedObjectContext) {
        CategoryManager.shared.setupInitialCategories(context: context)
    }
    
    // MARK: - Authentication Methods
    
    // Add a new method to request notification permissions
    func requestNotificationPermissionsIfNeeded() {
        // Always check system authorization status first, not just our flag
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            
            let status = settings.authorizationStatus
            print("🔔 System notification status: \(status.rawValue)")
            
            switch status {
            case .notDetermined:
                print("🔔 Requesting notification permissions now (post-login)...")
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
                    guard let self = self else { return }
                    print("🔔 Notification permission result - granted: \(granted), error: \(String(describing: error))")
                    if granted {
                        print("✅ Notification permission granted")
                    } else if let error = error {
                        print("❌ Error requesting notification permission: \(error.localizedDescription)")
                    } else {
                        print("❌ User denied notification permission")
                        UserDefaults.standard.set(true, forKey: "showNotificationSettingsPrompt")
                    }
                    UserDefaults.standard.set(true, forKey: "hasRequestedNotifications")
                    UserDefaults.standard.set(granted, forKey: "notificationsEnabled")
                    
                    // Chain ATT after notification dialog completes
                    DispatchQueue.main.async {
                        self.requestAppTrackingPermission()
                    }
                }
            case .authorized, .provisional, .ephemeral:
                UserDefaults.standard.set(true, forKey: "hasRequestedNotifications")
                UserDefaults.standard.set(true, forKey: "notificationsEnabled")
                DispatchQueue.main.async {
                    self.requestAppTrackingPermission()
                }
            case .denied:
                UserDefaults.standard.set(true, forKey: "hasRequestedNotifications")
                UserDefaults.standard.set(false, forKey: "notificationsEnabled")
                DispatchQueue.main.async {
                    self.requestAppTrackingPermission()
                }
            @unknown default:
                DispatchQueue.main.async {
                    self.requestAppTrackingPermission()
                }
            }
        }
    }
    
    // Checks notification status and returns if they are authorized
    func checkNotificationStatus(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let authorized = settings.authorizationStatus == .authorized
            DispatchQueue.main.async {
                completion(authorized)
            }
        }
    }
    
    // Opens the app's settings page for the user to enable notifications
    func openNotificationSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        
        DispatchQueue.main.async {
            if UIApplication.shared.canOpenURL(settingsUrl) {
                UIApplication.shared.open(settingsUrl)
            }
        }
    }
    
    // MARK: - Data Store Management
    
    // Setup separate stores for different user types to completely prevent data loss
    private func getStoreNameForCurrentUser() -> String {
        if isGuest {
            return "GuestStore"
        } else if let userID = userID {
            return "AppleID-\(userID)"
        } else {
            return "DefaultStore"
        }
    }
    
    // Create a secure way to preserve Apple ID data when switching between accounts
    private func preserveAppleIDData(_ userID: String) {
        // First, mark in UserDefaults that this user has data to preserve
        // This way we know later to load it back
        let key = "hasDataForAppleID-\(userID)"
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.synchronize()
        
        print("Marked Apple ID data to be preserved for: \(userID)")
    }
    
    // When signing out, explicitly preserve the Apple ID user's data
    private func preserveCurrentUserData() {
        // Only preserve for Apple ID users, not for guests
        if !isGuest, let userID = self.userID {
            preserveAppleIDData(userID)
        }
    }
    
    // MARK: - App Tracking Transparency
    
    /// Reset ATT session state - useful for debugging
    func resetATTSessionState() {
        hasRequestedATT = false
        print("🔄 ATT session state reset")
    }
    
    /// Force request ATT (for debugging) - bypasses session checks
    func forceRequestATT() {
        print("🚀 Force requesting ATT...")
        
        #if targetEnvironment(simulator)
        print("⚠️ ATT not available in simulator")
        #else
        // Check iOS version availability
        if #available(iOS 14.5, *) {
            DispatchQueue.main.async {
                let currentStatus = ATTrackingManager.trackingAuthorizationStatus
                print("🔐 Force ATT - Current status: \(currentStatus.rawValue)")
                
                if currentStatus == .notDetermined {
                    print("🔐 Force requesting ATT dialog...")
                    ATTrackingManager.requestTrackingAuthorization { status in
                        DispatchQueue.main.async {
                            print("✅ Force ATT completed with status: \(status.rawValue)")
                        }
                    }
                } else {
                    print("ℹ️ ATT already determined, cannot show dialog again")
                }
            }
        } else {
            print("⚠️ ATT requires iOS 14.5 or later")
        }
        #endif
    }
    
    /// Debug method to check current permission status
    func debugPermissionStatus() {
        print("\n📊 === PERMISSION STATUS DEBUG ===")
        
        // Check notification status
        let hasRequestedNotifications = UserDefaults.standard.bool(forKey: "hasRequestedNotifications")
        let notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        print("🔔 Notifications Requested: \(hasRequestedNotifications)")
        print("🔔 Notifications Enabled (stored): \(notificationsEnabled)")
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                print("🔔 Actual Notification Status: \(settings.authorizationStatus.rawValue)")
                switch settings.authorizationStatus {
                case .notDetermined: print("   - Not Determined")
                case .denied: print("   - Denied")
                case .authorized: print("   - Authorized")
                case .provisional: print("   - Provisional")
                case .ephemeral: print("   - Ephemeral")
                @unknown default: print("   - Unknown")
                }
            }
        }
        
        // Check ATT status
        #if targetEnvironment(simulator)
        print("🔐 ATT: Not available in simulator")
        #else
        if #available(iOS 14.5, *) {
            let attStatus = ATTrackingManager.trackingAuthorizationStatus
            print("🔐 ATT Status: \(attStatus.rawValue)")
            switch attStatus {
            case .notDetermined: print("   - Not Determined")
            case .restricted: print("   - Restricted")
            case .denied: print("   - Denied")
            case .authorized: print("   - Authorized")
            @unknown default: print("   - Unknown")
            }
        } else {
            print("🔐 ATT: iOS 14.5+ required")
        }
        #endif
        
        print("📊 === END DEBUG ===\n")
    }
    
    /// Request App Tracking Transparency permission
    private func requestAppTrackingPermission() {
        print("🔐 requestAppTrackingPermission called")
        
        // Check ATT availability first
        #if targetEnvironment(simulator)
        print("⚠️ ATT not available in simulator")
        #else
        // Check iOS version
        guard #available(iOS 14.5, *) else {
            print("⚠️ ATT requires iOS 14.5 or later")
            return
        }
        
        // Prevent duplicate ATT requests
        attRequestQueue.async { [weak self] in
            guard let self = self else { 
                print("❌ Self is nil in requestAppTrackingPermission")
                return 
            }
            
            print("🔐 Checking ATT request state - hasRequestedATT: \(self.hasRequestedATT)")
            
            if self.hasRequestedATT {
                print("⚠️ ATT permission already requested this session, skipping duplicate")
                return
            }
            
            // Check current ATT status first
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                let currentStatus = ATTrackingManager.trackingAuthorizationStatus
                print("🔐 Current ATT status: \(currentStatus.rawValue)")
                
                // If already determined, just log and continue
                if currentStatus != .notDetermined {
                    print("ℹ️ ATT already determined (status: \(currentStatus.rawValue)), not showing dialog")
                    return
                }
                
                // Mark as requested before showing dialog
                self.hasRequestedATT = true
                
                // Add delay to ensure notification UI is dismissed
                print("🔐 Scheduling ATT request with delay...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard self != nil else { return }
                    
                    print("🔐 Requesting App Tracking Transparency permission NOW...")
                    
                    AdMobManager.shared.requestTrackingAuthorization { status in
                        print("✅ ATT permission completed with status: \(status.rawValue)")
                        
                        // Log the final status for debugging
                        switch status {
                        case .notDetermined:
                            print("📱 ATT Status: Not Determined")
                        case .restricted:
                            print("📱 ATT Status: Restricted")
                        case .denied:
                            print("📱 ATT Status: Denied")
                        case .authorized:
                            print("📱 ATT Status: Authorized")
                        @unknown default:
                            print("📱 ATT Status: Unknown")
                        }
                        
                        // Store that we've completed the request persistently
                        UserDefaults.standard.set(true, forKey: "hasCompletedATTRequest")
                    }
                }
            }
        }
        #endif
    }
    
    private func completeAppleIDSetup(userIdentifier: String) {
        // Only proceed with permissions if data restoration is complete
        // This ensures the popup appears BEFORE notifications and ATT permissions
        
        // Request notification permissions (which will chain to ATT) post-login
        requestNotificationPermissionsIfNeeded()
        
        // Associate user with CloudKit for syncing
        setupCloudKitSync(userID: userIdentifier)
        
        // Mark that this Apple ID has saved data
        preserveAppleIDData(userIdentifier)
        
        // Notify that authentication state has changed
        NotificationCenter.default.post(
            name: NSNotification.Name("AuthStateChanged"),
            object: nil,
            userInfo: ["isAppleID": true]
        )
        
        // Force refresh UI state
        NotificationCenter.default.post(
            name: NSNotification.Name("CloudKitSetupCompleted"),
            object: nil
        )
        
        print("✅ Apple ID setup completed with data restoration handled")
    }
    
    // MARK: - SIMPLIFIED INSTANT DATA RESTORATION
    // This new approach uses centralized account initialization to prevent duplicates
    
    // MARK: - Data Restoration Methods
    
    /// Check if the Apple ID has previous data and show restoration popup - MAIN THREAD VERSION
    private func checkForPreviousDataOnMainThread(userIdentifier: String, completion: @escaping (Bool) -> Void) {
        print("🔍 Checking for previous data for Apple ID: \(userIdentifier)")
        
        // FIRST: Check UserDefaults flag as a quick indicator
        let preservationKey = "hasDataForAppleID-\(userIdentifier)"
        let hasPreservedData = UserDefaults.standard.bool(forKey: preservationKey)
        
        if hasPreservedData {
            print("✅ UserDefaults indicates previous data exists for Apple ID")
            self.prepareDataRestorationPopup(userIdentifier: userIdentifier, accounts: 1)
            completion(true)
            return
        }
        
        // SECOND: Check local Core Data
        let context = PersistenceController.shared.container.viewContext
        
        do {
            // Check if User entity exists for this Apple ID locally
            let userFetchRequest = NSFetchRequest<User>(entityName: "User")
            userFetchRequest.predicate = NSPredicate(format: "appleUserIdentifier == %@", userIdentifier)
            let existingUsers = try context.fetch(userFetchRequest)
            
            if let existingUser = existingUsers.first {
                // Check for accounts associated with this user
                let accountsFetchRequest = Account.fetchRequest()
                accountsFetchRequest.predicate = NSPredicate(format: "user == %@", existingUser)
                let userAccounts = try context.fetch(accountsFetchRequest)
                
                if !userAccounts.isEmpty {
                    // Found local data - show popup immediately
                    print("✅ Found local Core Data for Apple ID")
                    self.prepareDataRestorationPopup(userIdentifier: userIdentifier, accounts: userAccounts.count)
                    completion(true)
                    return
                }
            }
            
            // THIRD: Check CloudKit for existing data
            print("🔍 No local data found, checking CloudKit for previous data...")
            self.checkCloudKitForPreviousData(userIdentifier: userIdentifier, completion: completion)
            
        } catch {
            print("❌ Error checking local data: \(error.localizedDescription)")
            // Still check CloudKit even if local check fails
            self.checkCloudKitForPreviousData(userIdentifier: userIdentifier, completion: completion)
        }
    }
    
    /// Check CloudKit directly for previous data
    private func checkCloudKitForPreviousData(userIdentifier: String, completion: @escaping (Bool) -> Void) {
        // Check if CloudKit container is available first
        let container = CKContainer(identifier: "iCloud.com.rishiselarka.Spenly")
        container.accountStatus { [weak self] status, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ CloudKit account status error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            guard status == .available else {
                print("ℹ️ CloudKit account not available, no cloud data to check")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            // Check for existing records in CloudKit using modern API
            let database = container.privateCloudDatabase
            let query = CKQuery(recordType: "CD_User", predicate: NSPredicate(format: "CD_appleUserIdentifier == %@", userIdentifier))
            
            database.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success(let (matchResults: matchResults, queryCursor: _)):
                    let records: [CKRecord] = matchResults.compactMap { (recordID: CKRecord.ID, recordResult: Result<CKRecord, Error>) in
                        switch recordResult {
                        case .success(let record):
                            return record
                        case .failure(let error):
                            print("❌ Error fetching individual record: \(error.localizedDescription)")
                            return nil
                        }
                    }
                    
                    if !records.isEmpty {
                        print("✅ Found CloudKit data for Apple ID: \(userIdentifier)")
                        
                        // Query for accounts to get estimate using modern API
                        let accountQuery = CKQuery(recordType: "CD_Account", predicate: NSPredicate(format: "CD_user == %@", records.first!.recordID))
                        database.fetch(withQuery: accountQuery, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { accountResult in
                            DispatchQueue.main.async {
                                switch accountResult {
                                case .success(let (matchResults: accountMatchResults, queryCursor: _)):
                                    let accountRecords: [CKRecord] = accountMatchResults.compactMap { (accountRecordID: CKRecord.ID, accountRecordResult: Result<CKRecord, Error>) in
                                        switch accountRecordResult {
                                        case .success(let record):
                                            return record
                                        case .failure:
                                            return nil
                                        }
                                    }
                                    let accountCount = accountRecords.count > 0 ? accountRecords.count : 1
                                    self.prepareDataRestorationPopup(userIdentifier: userIdentifier, accounts: accountCount)
                                    completion(true)
                                case .failure(let error):
                                    print("❌ CloudKit account query error: \(error.localizedDescription)")
                                    // Still show popup with minimal data if user record exists
                                    self.prepareDataRestorationPopup(userIdentifier: userIdentifier, accounts: 1)
                                    completion(true)
                                }
                            }
                        }
                    } else {
                        print("ℹ️ No CloudKit data found for Apple ID: \(userIdentifier)")
                        DispatchQueue.main.async { completion(false) }
                    }
                    
                case .failure(let error):
                    print("❌ CloudKit query error: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(false) }
                }
            }
        }
    }
    
    /// Prepare the data restoration popup with user data summary
    private func prepareDataRestorationPopup(userIdentifier: String, accounts: Int) {
        self.restorationUserID = userIdentifier
        self.estimatedDataCount = self.formatDataSummary(accounts: accounts, transactions: 0)
        self.foundPreviousData = true
        print("✅ Prepared restoration popup for \(accounts) accounts")
    }
    
    /// Proceed with fresh sign-in when no previous data exists
    private func proceedWithFreshSignIn(userIdentifier: String, name: String?, email: String?) {
        // Save user session and update auth state
        saveUserSession(userID: userIdentifier, userName: name, userEmail: email)
        
        // Create fresh account without CloudKit complications
        createFreshAccountForNewUser(userIdentifier: userIdentifier)
    }
    
    private func formatDataSummary(accounts: Int, transactions: Int) -> String {
        var summary = ""
        if accounts > 0 {
            summary += "\(accounts) account\(accounts > 1 ? "s" : "")"
        }
        if transactions > 0 {
            if !summary.isEmpty { summary += " with " }
            summary += "\(transactions) transaction\(transactions > 1 ? "s" : "")"
        }
        if summary.isEmpty {
            summary = "some previous data"
        }
        return summary
    }
    
    /// Handle user's choice to restore or start fresh
    func handleDataRestorationChoice(shouldRestore: Bool) {
        guard let userID = restorationUserID else { return }
        
        showDataRestorationAlert = false
        
        if shouldRestore {
            print("🔄 User chose to restore previous data")
            
            // Save user session and update auth state FIRST
            saveUserSession(userID: userID, userName: userName, userEmail: userEmail)
            
            // Then restore data without creating new accounts
            restoreExistingUserData(userIdentifier: userID)
        } else {
            print("🆕 User chose to start fresh")
            
            // Clear existing data first, then proceed with fresh setup
            clearExistingUserData(userIdentifier: userID) { [weak self] in
                self?.proceedWithFreshSignIn(userIdentifier: userID, name: self?.userName, email: self?.userEmail)
            }
        }
    }
    
    private func restoreExistingUserData(userIdentifier: String) {
        print("🔄 Starting data restoration for Apple ID: \(userIdentifier)")
        
        // Enable CloudKit sync FIRST to pull data from cloud
        if CloudKitSyncManager.shared.isSyncEnabled == false {
            CloudKitSyncManager.shared.toggleSync(enabled: true)
        }
        
        // Give CloudKit a moment to start syncing data before checking local storage
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.loadRestoredAccountFromLocalOrCloud(userIdentifier: userIdentifier)
        }
    }
    
    private func loadRestoredAccountFromLocalOrCloud(userIdentifier: String) {
        let context = PersistenceController.shared.container.viewContext
        context.perform { [weak self] in
            do {
                // Find the User entity for this Apple ID
                let userFetchRequest = NSFetchRequest<User>(entityName: "User")
                userFetchRequest.predicate = NSPredicate(format: "appleUserIdentifier == %@", userIdentifier)
                
                if let userEntity = try context.fetch(userFetchRequest).first {
                    // Find existing accounts for this user
                    let accountsFetchRequest = Account.fetchRequest()
                    accountsFetchRequest.predicate = NSPredicate(format: "user == %@", userEntity)
                    accountsFetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
                    let existingAccounts = try context.fetch(accountsFetchRequest)
                    
                    if !existingAccounts.isEmpty {
                        // Load the first existing account (or saved preference)
                        var accountToLoad = existingAccounts.first!
                        
                        // Check if user had a preferred account saved
                        if let savedId = UserDefaults.standard.string(forKey: "currentAccountId"),
                           let accountId = UUID(uuidString: savedId) {
                            if let preferredAccount = existingAccounts.first(where: { $0.id == accountId }) {
                                accountToLoad = preferredAccount
                            }
                        }
                        
                        DispatchQueue.main.async { [weak self] in
                            // Set the existing account as current - NO new account creation
                            AccountManager.shared.setRestoredAccount(accountToLoad)
                            
                            print("✅ Restored existing account: \(accountToLoad.name ?? "unknown") with \(accountToLoad.transactions?.count ?? 0) transactions")
                            
                            // CRITICAL: Wait for data to be fully loaded before requesting permissions
                            self?.completeDataRestorationAndRequestPermissions(userIdentifier: userIdentifier)
                        }
                        return
                    }
                }
                
                // No local data found after CloudKit sync - trigger another sync
                print("⚠️ No local data after initial sync, forcing CloudKit pull...")
                DispatchQueue.main.async { [weak self] in
                    self?.forceCloudKitSyncAndRetry(userIdentifier: userIdentifier)
                }
                
            } catch {
                print("❌ Error loading restored data: \(error.localizedDescription)")
                DispatchQueue.main.async { [weak self] in
                    self?.forceCloudKitSyncAndRetry(userIdentifier: userIdentifier)
                }
            }
        }
    }
    
    private func forceCloudKitSyncAndRetry(userIdentifier: String) {
        // Force CloudKit to sync data
        CloudKitSyncManager.shared.forceSyncNow()
        
        // Wait for sync to complete and try one more time
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.finalRestoreAttempt(userIdentifier: userIdentifier)
        }
    }
    
    private func finalRestoreAttempt(userIdentifier: String) {
        let context = PersistenceController.shared.container.viewContext
        context.perform { [weak self] in
            do {
                // Final attempt to find restored data
                let userFetchRequest = NSFetchRequest<User>(entityName: "User")
                userFetchRequest.predicate = NSPredicate(format: "appleUserIdentifier == %@", userIdentifier)
                
                if let userEntity = try context.fetch(userFetchRequest).first {
                    let accountsFetchRequest = Account.fetchRequest()
                    accountsFetchRequest.predicate = NSPredicate(format: "user == %@", userEntity)
                    let existingAccounts = try context.fetch(accountsFetchRequest)
                    
                    if let accountToLoad = existingAccounts.first {
                        DispatchQueue.main.async { [weak self] in
                            AccountManager.shared.setRestoredAccount(accountToLoad)
                            print("✅ Final attempt: Restored account \(accountToLoad.name ?? "unknown")")
                            self?.completeDataRestorationAndRequestPermissions(userIdentifier: userIdentifier)
                        }
                        return
                    }
                }
                
                // Final fallback - create fresh account
                print("⚠️ Final attempt failed, creating fresh account")
                DispatchQueue.main.async { [weak self] in
                    self?.createFreshAccountForNewUser(userIdentifier: userIdentifier)
                }
                
            } catch {
                print("❌ Final restore attempt failed: \(error.localizedDescription)")
                DispatchQueue.main.async { [weak self] in
                    self?.createFreshAccountForNewUser(userIdentifier: userIdentifier)
                }
            }
        }
    }
    
    /// Complete data restoration and request permissions after data is fully loaded
    private func completeDataRestorationAndRequestPermissions(userIdentifier: String) {
        // Give a moment for UI to update with restored data
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            // Now request permissions after data is visible
            self?.completeAppleIDSetup(userIdentifier: userIdentifier)
        }
    }
    
    private func clearExistingUserData(userIdentifier: String, completion: @escaping () -> Void) {
        let context = PersistenceController.shared.container.viewContext
        
        context.perform {
            do {
                // Find and delete all data for this user
                let userFetchRequest = NSFetchRequest<User>(entityName: "User")
                userFetchRequest.predicate = NSPredicate(format: "appleUserIdentifier == %@", userIdentifier)
                
                if let userEntity = try context.fetch(userFetchRequest).first {
                    // Delete all accounts and transactions for this user
                    let accountsFetchRequest = Account.fetchRequest()
                    accountsFetchRequest.predicate = NSPredicate(format: "user == %@", userEntity)
                    let userAccounts = try context.fetch(accountsFetchRequest)
                    
                    for account in userAccounts {
                        // Delete transactions first
                        if let transactions = account.transactions as? Set<Transaction> {
                            for transaction in transactions {
                                context.delete(transaction)
                            }
                        }
                        // Delete account
                        context.delete(account)
                    }
                    
                    // Delete user entity
                    context.delete(userEntity)
                    
                    try context.save()
                    print("✅ Cleared existing user data for fresh start")
                }
                
                DispatchQueue.main.async {
                    completion()
                }
                
            } catch {
                print("❌ Error clearing existing user data: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }
    
    /// Create fresh account for new user without CloudKit complications
    private func createFreshAccountForNewUser(userIdentifier: String) {
        let context = PersistenceController.shared.container.viewContext
        
        context.perform { [weak self] in
            do {
                // Create User entity first
                let userFetchRequest = NSFetchRequest<User>(entityName: "User")
                userFetchRequest.predicate = NSPredicate(format: "appleUserIdentifier == %@", userIdentifier)
                
                let userEntity: User
                if let existingUser = try context.fetch(userFetchRequest).first {
                    userEntity = existingUser
                    userEntity.lastSignInAt = Date()
                } else {
                    userEntity = User(context: context)
                    userEntity.appleUserIdentifier = userIdentifier
                    userEntity.lastSignInAt = Date()
                }
                
                try context.save()
                print("✅ User entity created for fresh user: \(userIdentifier)")
                
                // Now create account on main thread
                DispatchQueue.main.async { [weak self] in
                    // Ensure categories exist
                    CategoryManager.shared.setupInitialCategories(context: context)
                    
                    // Create account through centralized system
                    AccountManager.shared.ensureAccountInitialized(context: context) { [weak self] account in
                        if let account = account {
                            print("✅ Fresh account created: \(account.name ?? "unknown")")
                        }
                        
                        // Enable CloudKit after account creation
                        CloudKitSyncManager.shared.toggleSync(enabled: true)
                        
                        // Complete setup
                        self?.completeAppleIDSetup(userIdentifier: userIdentifier)
                    }
                }
                
            } catch {
                print("❌ Error creating fresh user: \(error.localizedDescription)")
                DispatchQueue.main.async { [weak self] in
                    // Fallback to centralized account creation
                    AccountManager.shared.ensureAccountInitialized(context: context) { [weak self] _ in
                        CloudKitSyncManager.shared.toggleSync(enabled: true)
                        self?.completeAppleIDSetup(userIdentifier: userIdentifier)
                    }
                }
            }
        }
    }
    
    private func saveUserSession(userID: String, userName: String?, userEmail: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update published properties
            self.isSignedIn = true
            self.isGuest = false
            self.userID = userID
            self.userName = userName
            self.userEmail = userEmail
            
            // Update AppStorage
            self.isUserSignedIn = true
            self.isGuestUser = false
            self.storedUserID = userID
            self.storedUserName = userName
            self.storedUserEmail = userEmail
            
            // Set user identification for Firebase Crashlytics
            Crashlytics.crashlytics().setUserID(userID)
            
            // Set additional user attributes for better crash analysis
            if let name = userName {
                Crashlytics.crashlytics().setCustomValue(name, forKey: "user_name")
            }
            if let email = userEmail {
                Crashlytics.crashlytics().setCustomValue(email, forKey: "user_email")
            }
            
            // Set user type for analytics
            Crashlytics.crashlytics().setCustomValue("apple_id_user", forKey: "user_type")
            Crashlytics.crashlytics().setCustomValue(Date().timeIntervalSince1970, forKey: "sign_in_timestamp")
            
            #if DEBUG
            print("✅ Firebase Crashlytics user identification set for: \(userID)")
            #endif
            
            // Force UserDefaults synchronize to ensure data is saved immediately
            UserDefaults.standard.synchronize()
            
            // Notify about auth state change
            NotificationCenter.default.post(
                name: NSNotification.Name("AuthStateChanged"),
                object: nil,
                userInfo: ["isGuest": false]
            )
            }
        }
    }

// Extension to chunk arrays for batch CloudKit operations
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
