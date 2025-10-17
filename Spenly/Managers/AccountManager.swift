import Foundation
import CoreData
import SwiftUI

public class AccountManager: ObservableObject {
    static let shared = AccountManager()
    @Published var currentAccount: Account? {
        didSet {
            // When account changes, save it to UserDefaults for persistence
            if let account = currentAccount {
                // Store account ID securely in Keychain instead of UserDefaults
                if let accountId = account.id?.uuidString {
                    KeychainHelper.store(accountId, forKey: "currentAccountId")
                }
                #if DEBUG
                print("💾 Account saved: \(account.name ?? "unknown")")
                #endif
            } else if oldValue != nil {
                // Account was cleared unexpectedly, try to restore it
                print("⚠️ Account was unexpectedly cleared, attempting to restore...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.attemptAccountRecovery()
                }
            }
        }
    }
    
    private let persistenceController = PersistenceController.shared
    private var isLoading = false // Track loading state instead of blocking
    private var loadingCallbacks: [(Account?) -> Void] = [] // Queue callbacks
    
    // CRITICAL: Add centralized initialization control
    private var isInitialized = false
    private var isInitializing = false
    private let initializationQueue = DispatchQueue(label: "account-initialization", qos: .userInitiated)
    private var initializationCallbacks: [(Account?) -> Void] = []
    
    // ADD: Persistent initialization tracking to prevent duplicates across app sessions
    private var hasInitializedThisSession: Bool {
        get {
            UserDefaults.standard.bool(forKey: "accountManagerInitializedThisSession")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "accountManagerInitializedThisSession")
        }
    }
    
    private init() {}
    
    func resetLoadedState() {
        initializationQueue.sync {
            isLoading = false
            loadingCallbacks.removeAll()
            // DON'T reset isInitialized here - this was causing the race condition
            // isInitialized = false
            isInitializing = false
            initializationCallbacks.removeAll()
        }
        // Mark that we need to re-check initialization for the new session
        hasInitializedThisSession = false
        print("🔄 AccountManager state reset - ready for next sign-in")
    }
    
    // SMART SOLUTION: Single entry point for all account initialization
    func ensureAccountInitialized(context: NSManagedObjectContext, completion: ((Account?) -> Void)? = nil) {
        // ENHANCED: Check both in-memory and persistent initialization state
        if isInitialized && currentAccount != nil && currentAccount!.managedObjectContext != nil && !currentAccount!.isDeleted && hasInitializedThisSession {
            completion?(currentAccount)
            return
        }
        
        // ADDITIONAL SAFETY: Quick check if we already have a valid account loaded
        if currentAccount != nil && currentAccount!.managedObjectContext != nil && !currentAccount!.isDeleted {
            // Mark as initialized if we have a valid account
            isInitialized = true
            hasInitializedThisSession = true
            completion?(currentAccount)
            return
        }
        
        initializationQueue.async { [weak self] in
            guard let self = self else { 
                DispatchQueue.main.async { completion?(nil) }
                return 
            }
            
            // If initialization already in progress, queue callback
            if self.isInitializing {
                if let completion = completion {
                    self.initializationCallbacks.append(completion)
                }
                return
            }
            
            // Start initialization
            self.isInitializing = true
            if let completion = completion {
                self.initializationCallbacks.append(completion)
            }
            
            // Perform actual initialization
            self.performAccountInitialization(context: context)
        }
    }
    
    private func performAccountInitialization(context: NSManagedObjectContext) {
        context.perform { [weak self] in
            guard let self = self else { return }
            
            do {
                // STEP 0: Clean up any existing duplicates first
                self.cleanupDuplicateAccounts(context: context)
                
                // STEP 1: Check for ANY existing accounts first
                let allAccountsFetchRequest = Account.fetchRequest()
                allAccountsFetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
                let allAccounts = try context.fetch(allAccountsFetchRequest)
                
                var accountToUse: Account?
                
                // STEP 2: For Apple ID users, prioritize their accounts
                if let userID = AuthManager.shared.userID, !AuthManager.shared.isGuest {
                    let userFetchRequest = NSFetchRequest<User>(entityName: "User")
                    userFetchRequest.predicate = NSPredicate(format: "appleUserIdentifier == %@", userID)
                    
                    if let user = try? context.fetch(userFetchRequest).first {
                        let userAccountsFetchRequest = Account.fetchRequest()
                        userAccountsFetchRequest.predicate = NSPredicate(format: "user == %@", user)
                        userAccountsFetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
                        let userAccounts = try context.fetch(userAccountsFetchRequest)
                        
                        if !userAccounts.isEmpty {
                            // Use saved preference or first account
                            if let savedId = UserDefaults.standard.string(forKey: "currentAccountId"),
                               let accountId = UUID(uuidString: savedId) {
                                accountToUse = userAccounts.first { $0.id == accountId }
                            }
                            accountToUse = accountToUse ?? userAccounts.first
                            print("✅ Found Apple ID user account: \(accountToUse?.name ?? "unknown")")
                        }
                    }
                }
                
                // STEP 3: Fallback to any existing account
                if accountToUse == nil && !allAccounts.isEmpty {
                    // Try to use saved account preference
                    if let savedId = UserDefaults.standard.string(forKey: "currentAccountId"),
                       let accountId = UUID(uuidString: savedId) {
                        accountToUse = allAccounts.first { $0.id == accountId }
                    }
                    accountToUse = accountToUse ?? allAccounts.first
                    print("✅ Using existing account: \(accountToUse?.name ?? "unknown")")
                }
                
                // STEP 4: Only create if NO accounts exist at all
                if accountToUse == nil {
                    print("🆕 No accounts found - creating single default account")
                    accountToUse = self.createSingleDefaultAccount(context: context)
                }
                
                // STEP 5: Finalize initialization
                if let finalAccount = accountToUse {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        self.currentAccount = finalAccount
                        UserDefaults.standard.set(finalAccount.id?.uuidString, forKey: "currentAccountId")
                        
                        // Mark as initialized with enhanced persistence
                        self.initializationQueue.sync {
                            self.isInitialized = true
                            self.isInitializing = false
                        }
                        self.hasInitializedThisSession = true
                        
                        print("✅ Account initialization completed: \(finalAccount.name ?? "unknown")")
                        
                        // Call all queued callbacks
                        let callbacks = self.initializationQueue.sync {
                            let callbacksCopy = self.initializationCallbacks
                            self.initializationCallbacks.removeAll()
                            return callbacksCopy
                        }
                        
                        for callback in callbacks {
                            callback(finalAccount)
                        }
                        
                        // Post notification
                        NotificationCenter.default.post(
                            name: NSNotification.Name("AccountChanged"),
                            object: finalAccount
                        )
                    }
                } else {
                    print("❌ Failed to initialize account")
                    self.finishInitializationWithError()
                }
                
            } catch {
                print("❌ Error during account initialization: \(error.localizedDescription)")
                self.finishInitializationWithError()
            }
        }
    }
    
    private func createSingleDefaultAccount(context: NSManagedObjectContext) -> Account? {
        var createdAccount: Account?
        
        // Use performAndWait to ensure atomic operation
        context.performAndWait {
            do {
                // Double-check inside the performAndWait to ensure atomicity
                let checkRequest = Account.fetchRequest()
                let existingCount = try context.count(for: checkRequest)
                if existingCount > 0 {
                    print("⚠️ DUPLICATE PREVENTION: \(existingCount) account(s) already exist, aborting creation")
                    let existingAccountsFetch = try context.fetch(checkRequest)
                    createdAccount = existingAccountsFetch.first
                    return
                }
                
                let newAccount = Account(context: context)
                newAccount.id = UUID()
                newAccount.name = "My Account"
                newAccount.isDefault = true
                newAccount.createdAt = Date()
                
                // Associate with Apple ID user if applicable
                if let userID = AuthManager.shared.userID, !AuthManager.shared.isGuest {
                    let userFetchRequest = NSFetchRequest<User>(entityName: "User")
                    userFetchRequest.predicate = NSPredicate(format: "appleUserIdentifier == %@", userID)
                    
                    let user: User
                    if let existingUser = try? context.fetch(userFetchRequest).first {
                        user = existingUser
                    } else {
                        user = User(context: context)
                        user.appleUserIdentifier = userID
                        user.lastSignInAt = Date()
                    }
                    newAccount.user = user
                }
                
                try context.save()
                print("✅ Created single default account: \(newAccount.id?.uuidString ?? "unknown")")
                createdAccount = newAccount
                
            } catch {
                print("❌ Error creating default account: \(error.localizedDescription)")
            }
        }
        
        return createdAccount
    }
    
    private func finishInitializationWithError() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.initializationQueue.sync {
                self.isInitializing = false
                // Don't mark as initialized on error
            }
            
            let callbacks = self.initializationQueue.sync {
                let callbacksCopy = self.initializationCallbacks
                self.initializationCallbacks.removeAll()
                return callbacksCopy
            }
            
            for callback in callbacks {
                callback(nil)
            }
        }
    }
    
    func switchToAccount(_ account: Account) {
        // Get a strong reference to the account
        guard let context = account.managedObjectContext else { return }
        
        context.perform {
            // Verify account still exists
            if account.managedObjectContext != nil {
                DispatchQueue.main.async { [weak self] in
                    self?.currentAccount = account
                    UserDefaults.standard.set(account.id?.uuidString, forKey: "currentAccountId")
                    
                    // Post notification that account has changed for features like balance carryover
                    NotificationCenter.default.post(
                        name: NSNotification.Name("AccountChanged"),
                        object: account
                    )
                }
            } else {
                // Account was deleted, reinitialize
                self.ensureAccountInitialized(context: self.persistenceController.container.viewContext)
            }
        }
    }
    
    // DEPRECATED: Replace all calls with ensureAccountInitialized
    func loadSavedAccount(context: NSManagedObjectContext, completion: ((Account?) -> Void)? = nil) {
        ensureAccountInitialized(context: context, completion: completion)
    }
    
    // DEPRECATED: Replace all calls with ensureAccountInitialized
    func loadSavedAccount(context: NSManagedObjectContext) {
        ensureAccountInitialized(context: context, completion: nil)
    }
            
    // DEPRECATED: Replace all calls with ensureAccountInitialized  
    func setupDefaultAccount(context: NSManagedObjectContext, forUserID userID: String? = nil, completion: ((Account?) -> Void)? = nil) {
        ensureAccountInitialized(context: context, completion: completion)
            }
            
    // DEPRECATED: Replace all calls with ensureAccountInitialized
    func setupDefaultAccount(context: NSManagedObjectContext, forUserID userID: String? = nil) {
        ensureAccountInitialized(context: context, completion: nil)
    }
    
    func handleAccountDeletion(_ deletedAccount: Account) {
        if currentAccount?.id == deletedAccount.id {
            ensureAccountInitialized(context: persistenceController.container.viewContext)
        }
                }
                
    // New method to restore account selection after context operations
    func restoreAccountAfterReset(context: NSManagedObjectContext, accountId: UUID) {
        let fetchRequest = Account.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", accountId as CVarArg)
        
        context.perform { [weak self] in
            do {
                let accounts = try context.fetch(fetchRequest)
                if let restoredAccount = accounts.first {
                    DispatchQueue.main.async {
                        self?.currentAccount = restoredAccount
                        UserDefaults.standard.set(accountId.uuidString, forKey: "currentAccountId")
                        
                        print("✅ Successfully restored account selection: \(restoredAccount.name ?? "unknown")")
                        
                        // Notify that account was restored
                        NotificationCenter.default.post(
                            name: NSNotification.Name("AccountChanged"),
                            object: restoredAccount
                        )
                    }
                } else {
                    print("⚠️ Could not find account with ID \(accountId.uuidString) after reset")
                    // Fallback: load any available account
                    DispatchQueue.main.async {
                        self?.loadSavedAccount(context: context)
                    }
                }
            } catch {
                print("❌ Error restoring account selection: \(error.localizedDescription)")
                // Fallback: load any available account
                DispatchQueue.main.async {
                    self?.loadSavedAccount(context: context)
                }
            }
        }
    }
    
    private func attemptAccountRecovery() {
        // Only attempt recovery if we still don't have an account
        guard currentAccount == nil else { return }
        
        // Try to restore from UserDefaults or load any available account
        print("🔄 Attempting account recovery...")
        let context = persistenceController.container.viewContext
        ensureAccountInitialized(context: context)
    }
    
    private func cleanupDuplicateAccounts(context: NSManagedObjectContext) {
        do {
            // Find all accounts with the same name for the current user
            let allAccountsFetch = Account.fetchRequest()
            allAccountsFetch.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let allAccounts = try context.fetch(allAccountsFetch)
            
            // Group accounts by user and name
            var accountGroups: [String: [Account]] = [:]
            
            for account in allAccounts {
                let userKey = account.user?.appleUserIdentifier ?? "guest"
                let accountName = account.name ?? "My Account"
                let groupKey = "\(userKey)_\(accountName)"
                
                if accountGroups[groupKey] == nil {
                    accountGroups[groupKey] = []
                }
                accountGroups[groupKey]?.append(account)
            }
            
            // Merge duplicates
            var hasChanges = false
            for (groupKey, accounts) in accountGroups {
                if accounts.count > 1 {
                    print("🧹 Found \(accounts.count) duplicate accounts for \(groupKey), merging...")
                    
                    // Keep the first (oldest) account
                    let primaryAccount = accounts[0]
                    let duplicates = Array(accounts.dropFirst())
                    
                    // Move all transactions from duplicates to primary account
                    for duplicate in duplicates {
                        if let transactions = duplicate.transactions as? Set<Transaction> {
                            for transaction in transactions {
                                transaction.account = primaryAccount
                            }
                        }
                        
                        // Delete the duplicate
                        context.delete(duplicate)
                        hasChanges = true
                        print("🗑️ Merged and deleted duplicate account: \(duplicate.id?.uuidString ?? "unknown")")
                    }
                    
                    print("✅ Kept primary account: \(primaryAccount.name ?? "unknown") with ID: \(primaryAccount.id?.uuidString ?? "unknown")")
                }
            }
            
            // Save changes if any duplicates were merged
            if hasChanges {
                try context.save()
                print("✅ Duplicate account cleanup completed")
                }
            
            } catch {
            print("❌ Error during duplicate account cleanup: \(error.localizedDescription)")
            }
        }
    
    // Call this when the app actually launches fresh
    func resetSessionState() {
        hasInitializedThisSession = false
        print("🔄 Session state reset for new app launch")
    }
    
    // MARK: - CloudKit Account Restoration
    
    /// Set an account that was restored from CloudKit
    func setRestoredAccount(_ account: Account) {
        // Set this as current account
        self.currentAccount = account
        
        // Mark as initialized to prevent duplicate creation
        self.hasInitializedThisSession = true
        
        // Store the account ID
        UserDefaults.standard.set(account.id?.uuidString, forKey: "currentAccountId")
        UserDefaults.standard.synchronize()
        
        // Notify UI
        DispatchQueue.main.async {
            self.objectWillChange.send()
            
            NotificationCenter.default.post(
                name: NSNotification.Name("AccountChanged"),
                object: account
            )
            
            NotificationCenter.default.post(
                name: NSNotification.Name("AccountsLoaded"),
                object: nil
            )
        }
        
        print("✅ Restored account set as current: \(account.name ?? "unknown")")
    }
} 