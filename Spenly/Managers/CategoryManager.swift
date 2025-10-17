import Foundation
import CoreData

class CategoryManager {
    static let shared = CategoryManager()
    
    // Track if the full cleanup has been performed during this app session
    private let fullCleanupKey = "fullCategoriesCleanupPerformed"
    
    // Single source of truth for default categories - standardized names
    let defaultCategories: [(name: String, icon: String, type: String)] = [
        // Income Categories
        ("Salary", "briefcase.fill", "income"),
        ("Freelance", "person.fill.checkmark", "income"),
        ("Investments", "chart.line.uptrend.xyaxis.circle.fill", "income"),
        ("Business", "building.2.fill", "income"),
        ("Rental Income", "house.fill", "income"),
        ("Other Income", "dollarsign.circle.fill", "income"),
        
        // Expense Categories
        ("Food & Dining", "fork.knife.circle.fill", "expense"),
        ("Transportation", "car.fill", "expense"),
        ("Shopping", "bag.fill", "expense"),
        ("Bills & Utilities", "doc.text.fill", "expense"),
        ("Entertainment", "tv.fill", "expense"),
        ("Health & Fitness", "cross.case.fill", "expense"),
        ("Education", "book.fill", "expense"),
        ("Travel", "airplane.circle.fill", "expense"),
        ("Housing", "house.fill", "expense"),
        ("Personal Care", "person.fill", "expense"),
        ("Gifts & Donations", "gift.fill", "expense"),
        ("Other Expenses", "cart.fill", "expense")
    ]
    
    // Known duplicate patterns to specifically handle
    private let knownDuplicates: [(original: String, duplicate: String)] = [
        // Income Categories
        ("Investments", "Investment"),
        ("Rental Income", "Rental"),
        ("Other Income", "Other"),
        
        // Expense Categories
        ("Other Expenses", "Other"),
        ("Housing", "Rent"),
        ("Housing", "Home"),
        ("Bills & Utilities", "Bills"),
        ("Bills & Utilities", "Utilities"),
        ("Food & Dining", "Food"),
        ("Food & Dining", "Dining"),
        ("Health & Fitness", "Health"),
        ("Health & Fitness", "Fitness"),
        ("Gifts & Donations", "Gifts"),
        ("Gifts & Donations", "Donations"),
        ("Personal Care", "Personal"),
        ("Transportation", "Transport"),
        ("Entertainment", "Fun")
    ]
    
    func setupInitialCategories(context: NSManagedObjectContext) {
        // First check and fix any duplicate categories
        cleanupAllDuplicateCategories(context: context)
        
        // Check if categories already exist
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Category")
        let count = (try? context.count(for: fetchRequest)) ?? 0
        
        guard count == 0 else { return }
        
        // Add default categories
        for category in defaultCategories {
            let newCategory = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
            newCategory.setValue(UUID(), forKey: "id")
            newCategory.setValue(category.name, forKey: "name")
            newCategory.setValue(category.type, forKey: "type")
            newCategory.setValue(category.icon, forKey: "icon")
            newCategory.setValue(false, forKey: "isCustom")
        }
        
        try? context.save()
    }
    
    // Comprehensive cleanup method that runs all necessary checks
    func cleanupAllDuplicateCategories(context: NSManagedObjectContext) {
        let defaults = UserDefaults.standard
        let isFullCleanupPerformed = defaults.bool(forKey: fullCleanupKey)
        
        // If we've already done a full cleanup in this app session, just do a quick check
        if isFullCleanupPerformed {
            // Only run quick duplicate check for newly added categories
            quickDuplicateCheck(context: context)
            return
        }
        
        // First time in this session - do the full cleanup
        // First fix the known problematic duplicates
        fixKnownDuplicates(context: context)
        
        // Then run the general duplicate removal
        removeDuplicateCategories(context: context)
        
        // Save changes
        if context.hasChanges {
            try? context.save()
        }
        
        // Mark that we've done a full cleanup
        defaults.set(true, forKey: fullCleanupKey)
    }
    
    // Quick check for duplicates - only checks recent categories
    private func quickDuplicateCheck(context: NSManagedObjectContext) {
        // Get all categories - we can't filter by modification date since that property doesn't exist
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Category")
        
        do {
            let allCategories = try context.fetch(fetchRequest)
            var uniqueCategories: [String: NSManagedObject] = [:]
            var duplicatesToRemove: [NSManagedObject] = []
            
            // First pass: collect unique categories
            for category in allCategories {
                guard let name = category.value(forKey: "name") as? String,
                      let type = category.value(forKey: "type") as? String else { continue }
                
                let normalizedName = normalizeCategory(name: name)
                let key = "\(normalizedName)_\(type.lowercased())"
                
                if let existing = uniqueCategories[key] {
                    // Determine which to keep based on whether they're default or custom
                    let isExistingDefault = existing.value(forKey: "isCustom") as? Bool == false
                    let isCategoryDefault = category.value(forKey: "isCustom") as? Bool == false
                    
                    // Prefer default categories
                    if isExistingDefault && !isCategoryDefault {
                        // Keep existing, mark this one for removal
                        duplicatesToRemove.append(category)
                    } else if !isExistingDefault && isCategoryDefault {
                        // Replace with this one, mark existing for removal
                        duplicatesToRemove.append(existing)
                        uniqueCategories[key] = category
                    } else {
                        // Both are same type, keep the first one we encountered
                        duplicatesToRemove.append(category)
                    }
                } else {
                    // First time seeing this category
                    uniqueCategories[key] = category
                }
            }
            
            // Now merge and clean up duplicates
            for duplicate in duplicatesToRemove {
                guard let name = duplicate.value(forKey: "name") as? String,
                      let type = duplicate.value(forKey: "type") as? String else { continue }
                
                let normalizedName = normalizeCategory(name: name)
                let key = "\(normalizedName)_\(type.lowercased())"
                
                if let keeper = uniqueCategories[key] {
                    // Transfer transactions to the keeper
                    if let transactions = duplicate.value(forKey: "transactions") as? Set<NSManagedObject> {
                        for transaction in transactions {
                            transaction.setValue(keeper, forKey: "category")
                        }
                    }
                    
                    // Delete the duplicate
                    context.delete(duplicate)
                }
            }
            
            // Save if changes were made
            if context.hasChanges {
                try context.save()
                print("Removed \(duplicatesToRemove.count) duplicate categories")
            }
        } catch {
            print("Error in quick duplicate check: \(error)")
        }
    }
    
    // Find and fix specific known duplicate patterns
    private func fixKnownDuplicates(context: NSManagedObjectContext) {
        for typePredicate in ["type == %@", "type == %@"] {
            for type in ["income", "expense"] {
                let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Category")
                fetchRequest.predicate = NSPredicate(format: typePredicate, type)
                
                do {
                    let categories = try context.fetch(fetchRequest)
                    var categoryMap: [String: NSManagedObject] = [:]
                    
                    // First pass - build a map of categories by normalized name
                    for category in categories {
                        if let name = category.value(forKey: "name") as? String {
                            let normalizedName = normalizeCategory(name: name)
                            categoryMap[normalizedName] = category
                        }
                    }
                    
                    // Second pass - find and fix known duplicates
                    for (original, duplicate) in knownDuplicates {
                        let normalizedOriginal = normalizeCategory(name: original)
                        let normalizedDuplicate = normalizeCategory(name: duplicate)
                        
                        // If both exist, merge them
                        if let originalObj = categoryMap[normalizedOriginal],
                           let duplicateObj = categoryMap[normalizedDuplicate] {
                            
                            // Standardize to the preferred name
                            originalObj.setValue(original, forKey: "name")
                            
                            // Migrate transactions from duplicate to original
                            if let transactions = duplicateObj.value(forKey: "transactions") as? Set<NSManagedObject> {
                                for transaction in transactions {
                                    transaction.setValue(originalObj, forKey: "category")
                                }
                            }
                            
                            // Delete the duplicate
                            context.delete(duplicateObj)
                        }
                    }
                } catch {
                    print("Error fixing known duplicates: \(error)")
                }
            }
        }
    }
    
    // Helper to normalize category names consistently
    private func normalizeCategory(name: String) -> String {
        var normalizedName = name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&", with: "and")
        
        // Remove common suffixes for comparison
        if normalizedName.hasSuffix(" income") {
            normalizedName = normalizedName.replacingOccurrences(of: " income", with: "")
        }
        
        if normalizedName.hasSuffix(" expenses") || normalizedName.hasSuffix(" expense") {
            normalizedName = normalizedName.replacingOccurrences(of: " expenses", with: "")
            normalizedName = normalizedName.replacingOccurrences(of: " expense", with: "")
        }
        
        return normalizedName
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
                
                // Use the improved normalization
                let normalizedName = normalizeCategory(name: name)
                let key = "\(normalizedName)_\(type.lowercased())"
                
                if let existing = unique[key] {
                    // For standard categories, prefer the default name
                    let isExistingDefault = existing.value(forKey: "isCustom") as? Bool == false
                    let isCategoryDefault = category.value(forKey: "isCustom") as? Bool == false
                    
                    let keepExisting = isExistingDefault || !isCategoryDefault
                    
                    // Decide which one to keep
                    let keeper = keepExisting ? existing : category
                    let toRemove = keepExisting ? category : existing
                    
                    // Update the unique map
                    unique[key] = keeper
                    
                    // Reassign transactions from the one to remove
                    if let transactions = toRemove.value(forKey: "transactions") as? Set<NSManagedObject> {
                        for transaction in transactions {
                            transaction.setValue(keeper, forKey: "category")
                        }
                    }
                    
                    // Mark for deletion
                    toDelete.append(toRemove)
                    
                    // If we're keeping this one instead of the previous one, remove the previous one from toDelete
                    if !keepExisting && toDelete.contains(existing) {
                        toDelete.removeAll { $0 === existing }
                    }
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
            
            if !toDelete.isEmpty {
                print("Removed \(toDelete.count) duplicate categories")
            }
        } catch {
            print("Error removing duplicate categories: \(error)")
        }
    }
    
    // MEMORY LEAK FIX: Add deinit to cleanup notifications
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
} 

