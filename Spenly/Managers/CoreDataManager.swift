import CoreData
import SwiftUI
import FirebaseCrashlytics

public class CoreDataManager {
    public static let shared = CoreDataManager()
    
    // Use the single app-wide container from PersistenceController
    public let container: NSPersistentCloudKitContainer
    private var saveTask: Task<Void, Never>?
    
    private init() {
        // Consolidated: point to the shared NSPersistentCloudKitContainer
        self.container = PersistenceController.shared.container
        
        // Ensure viewContext policies are aligned
        self.container.viewContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        self.container.viewContext.automaticallyMergesChangesFromParent = true
        self.container.viewContext.shouldDeleteInaccessibleFaults = true
        self.container.viewContext.undoManager = nil
    }
    
    // Create a background context for heavy operations
    public func backgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }
    
    // Debounced save on main queue
    public func save() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3s debounce
                
                await MainActor.run {
                    let context = self.container.viewContext
                    if context.hasChanges {
                        do {
                            try context.save()
                        } catch {
                            self.logError(error, context: "Core Data context save")
                        }
                    }
                }
            } catch {
                self.logError(error, context: "Core Data save task")
            }
        }
    }
    
    // Immediate save using the context's own queue
    public func saveImmediately() throws {
        var caughtError: Error?
        let context = container.viewContext
        context.performAndWait {
            if context.hasChanges {
                do { try context.save() } catch { caughtError = error }
            }
        }
        if let error = caughtError { throw error }
    }
    
    // Batch operations on a background context
    public func batchDelete(entityName: String, predicate: NSPredicate? = nil) {
        let viewContext = container.viewContext
        let bgContext = backgroundContext()
        
        bgContext.perform { [weak self] in
            guard let self = self else { return }
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            fetchRequest.predicate = predicate
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            deleteRequest.resultType = .resultTypeObjectIDs
            
            do {
                let result = try bgContext.execute(deleteRequest) as? NSBatchDeleteResult
                if let objectIDs = result?.result as? [NSManagedObjectID] {
                    let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: objectIDs]
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
                }
            } catch {
                self.logError(error, context: "Core Data batch delete")
            }
        }
    }
    
    // Optimized fetch on viewContext's queue
    public func optimizedFetch<T: NSManagedObject>(_ request: NSFetchRequest<T>) -> [T] {
        var results: [T] = []
        var fetchError: Error?
        let context = container.viewContext
        context.performAndWait {
            do {
                results = try context.fetch(request)
            } catch {
                fetchError = error
            }
        }
        if let error = fetchError {
            logError(error, context: "Core Data optimized fetch")
        }
        return results
    }
    
    // MARK: - Memory Management
    
    public func cleanupResources() {
        container.viewContext.perform {
            self.container.viewContext.reset()
        }
        
        saveTask?.cancel()
        saveTask = nil
    }
    
    public func handleMemoryWarning() {
        container.viewContext.perform {
            self.container.viewContext.reset()
        }
        
        saveTask?.cancel()
        saveTask = nil
        
        do {
            try saveImmediately()
        } catch {
            logError(error, context: "Core Data memory warning save")
        }
    }
    
    // MARK: - Error Handling
    
    private func logError(_ error: Error, context: String) {
        print("Error in \(context): \(error.localizedDescription)")
        
        Crashlytics.crashlytics().log("Core Data error in \(context): \(error.localizedDescription)")
        Crashlytics.crashlytics().record(error: error)
        Crashlytics.crashlytics().setCustomValue(context, forKey: "core_data_operation")
        Crashlytics.crashlytics().setCustomValue(error.localizedDescription, forKey: "core_data_error_description")
        
        let coreDataError = error as NSError
        Crashlytics.crashlytics().setCustomValue(coreDataError.code, forKey: "core_data_error_code")
        Crashlytics.crashlytics().setCustomValue(coreDataError.domain, forKey: "core_data_error_domain")
    }
    
    // MARK: - Helpers
    
    // Retained for API compatibility (no-op after consolidation)
    public func optimizeContext() { }
    
    public func createOptimizedFetchRequest<T: NSManagedObject>(entityName: String) -> NSFetchRequest<T> {
        let request = NSFetchRequest<T>(entityName: entityName)
        request.fetchBatchSize = 50
        return request
    }
}
