import Foundation
import CoreData
import SwiftUI

class TemplateManager: ObservableObject {
    static let shared = TemplateManager()
    
    @Published var templates: [TransactionTemplate] = []
    @AppStorage("templatesEnabled") var isEnabled = false
    @AppStorage("hasSeenTemplateWelcome") private var hasSeenWelcome = false
    
    private let userDefaults = UserDefaults.standard
    private let templatesKey = "transactionTemplates"
    private let maxNameLength = 15
    private let usageKey = "templateUsageStats"
    
    // THREAD SAFETY: Add queue for safe concurrent access
    private let templateQueue = DispatchQueue(label: "template-manager", qos: .userInitiated)
    
    private var usageStatsById: [UUID: TemplateUsageStats] = [:]
    
    private init() {
        loadTemplates()
        loadUsageStats()
    }
    
    // MARK: - Template Management
    
    func loadTemplates() {
        guard let data = userDefaults.data(forKey: templatesKey),
              let decodedTemplates = try? JSONDecoder().decode([TransactionTemplate].self, from: data) else {
            templates = []
            return
        }
        templates = decodedTemplates
    }
    
    private func saveTemplates() {
        templateQueue.async { [weak self] in
            guard let self = self else { return }
            guard let data = try? JSONEncoder().encode(self.templates) else { 
                print("❌ Failed to encode templates for saving")
                return 
            }
            self.userDefaults.set(data, forKey: self.templatesKey)
            print("💾 Templates saved successfully (\(self.templates.count) templates)")
        }
    }
    
    // MARK: - Usage Persistence
    private func loadUsageStats() {
        if let data = userDefaults.data(forKey: usageKey),
           let decoded = try? JSONDecoder().decode([UUID: TemplateUsageStats].self, from: data) {
            usageStatsById = decoded
        } else {
            usageStatsById = [:]
        }
    }
    
    private func saveUsageStats() {
        templateQueue.async { [weak self] in
            guard let self = self else { return }
            guard let data = try? JSONEncoder().encode(self.usageStatsById) else { return }
            self.userDefaults.set(data, forKey: self.usageKey)
        }
    }
    
    func addTemplate(_ template: TransactionTemplate) {
        // Validate name length
        guard template.name.count <= maxNameLength else { return }
        
        templates.append(template)
        saveTemplates()
    }
    
    func updateTemplate(_ template: TransactionTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        templates[index] = template
        saveTemplates()
    }
    
    func deleteTemplate(_ template: TransactionTemplate) {
        templates.removeAll { $0.id == template.id }
        saveTemplates()
        // Clean up usage to avoid stale data
        usageStatsById.removeValue(forKey: template.id)
        saveUsageStats()
    }
    
    // MARK: - Template Usage
    
    func getVariableFieldRequest(for template: TransactionTemplate) -> VariableFieldRequest {
        return VariableFieldRequest(
            templateName: template.name,
            needsAmount: template.amountType == .variable,
            needsNote: template.noteType == .variable,
            needsDate: template.dateType == .variable
        )
    }
    
    func createTransaction(
        from template: TransactionTemplate,
        variableResponse: VariableFieldResponse? = nil,
        context: NSManagedObjectContext,
        accountManager: AccountManager
    ) -> Bool {
        // CRITICAL FIX: Ensure account is properly initialized and valid
        guard let currentAccount = accountManager.currentAccount,
              currentAccount.managedObjectContext != nil,
              !currentAccount.isDeleted else { 
            print("❌ Template: Invalid account state, attempting to fix...")
            // Try to fix account initialization
            accountManager.ensureAccountInitialized(context: context)
            return false 
        }
        
        // Create new transaction
        let newTransaction = Transaction(context: context)
        newTransaction.id = UUID()
        newTransaction.isExpense = template.isExpense
        
        // Set amount
        if template.amountType == .fixed {
            newTransaction.amount = template.fixedAmount ?? 0.0
        } else {
            newTransaction.amount = variableResponse?.amount ?? 0.0
        }
        
        // Set note
        if template.noteType == .fixed {
            newTransaction.note = template.fixedNote
        } else {
            newTransaction.note = variableResponse?.note
        }
        
        // Set date
        if template.dateType == .fixed, let dateOption = template.dateOption {
            if dateOption == .custom, let customDay = template.customDay {
                // Compute current month date using custom day, clamped to month's last day
                let calendar = Calendar.current
                let now = Date()
                let components = calendar.dateComponents([.year, .month], from: now)
                if let startOfMonth = calendar.date(from: components),
                   let range = calendar.range(of: .day, in: .month, for: startOfMonth) {
                    let clampedDay = min(max(customDay, range.lowerBound), range.upperBound - 1)
                    var finalComponents = components
                    finalComponents.day = clampedDay
                    // Use noon to avoid DST edge cases
                    finalComponents.hour = 12
                    if let computedDate = calendar.date(from: finalComponents) {
                        newTransaction.date = computedDate
                    } else {
                        newTransaction.date = Date()
                    }
                } else {
                    newTransaction.date = Date()
                }
            } else {
                newTransaction.date = dateOption.date
            }
        } else {
            newTransaction.date = variableResponse?.date ?? Date()
        }
        
        // CRITICAL FIX: Safe category fetching with context validation
        if let categoryID = template.categoryID {
            let fetchRequest: NSFetchRequest<Category> = Category.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", categoryID as CVarArg)
            fetchRequest.fetchLimit = 1 // Performance optimization
            
            do {
                if let category = try context.fetch(fetchRequest).first {
                    newTransaction.category = category
                } else {
                    print("⚠️ Template: Category with ID \(categoryID) not found, transaction will have no category")
                }
            } catch {
                print("❌ Template: Failed to fetch category: \(error)")
                // Continue without category rather than failing completely
            }
        }
        
        // Set account relationship
        newTransaction.account = currentAccount
        
        // Set additional properties
        newTransaction.isCarryOver = false
        newTransaction.isDemo = false
        newTransaction.isPaused = false
        
        // CRITICAL FIX: Enhanced save with proper error handling and rollback
        do {
            try context.save()
            // Record usage for analytics/AI context
            recordUsage(for: template, using: newTransaction)
            
            // Post notification for UI updates (matches existing pattern)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("TransactionUpdated"),
                    object: nil
                )
            }
            
            print("✅ Template transaction created successfully: \(template.name)")
            return true
        } catch {
            print("❌ Failed to save transaction from template: \(error)")
            // CRITICAL: Rollback context to prevent corrupted state
            context.rollback()
            return false
        }
    }
    
    // MARK: - Welcome State
    
    var shouldShowWelcome: Bool {
        return !hasSeenWelcome
    }
    
    func markWelcomeSeen() {
        hasSeenWelcome = true
    }
    
    // MARK: - Validation
    
    func validateTemplateName(_ name: String) -> Bool {
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
               name.count <= maxNameLength
    }
    
    func isTemplateNameUnique(_ name: String, excluding templateID: UUID? = nil) -> Bool {
        return !templates.contains { template in
            template.name.lowercased() == name.lowercased() && 
            template.id != templateID
        }
    }
    
    // MARK: - Usage Tracking
    private func recordUsage(for template: TransactionTemplate, using transaction: Transaction) {
        var stats = usageStatsById[template.id] ?? TemplateUsageStats()
        stats.useCount += 1
        stats.lastUsedAt = Date()
        stats.totalAmount += transaction.amount
        if transaction.isExpense {
            stats.totalExpenseAmount += transaction.amount
        } else {
            stats.totalIncomeAmount += transaction.amount
        }
        usageStatsById[template.id] = stats
        saveUsageStats()
    }
    
    func usageStats() -> [UUID: TemplateUsageStats] {
        return usageStatsById
    }
    
    func mostUsedTemplates(limit: Int = 3) -> [(template: TransactionTemplate, count: Int)] {
        let byCount = templates.compactMap { t -> (TransactionTemplate, Int)? in
            if let stats = usageStatsById[t.id] { return (t, stats.useCount) }
            return nil
        }
        .sorted { $0.1 > $1.1 }
        return Array(byCount.prefix(limit))
    }
}

// MARK: - Usage Models
struct TemplateUsageStats: Codable {
    var useCount: Int = 0
    var lastUsedAt: Date? = nil
    var totalAmount: Double = 0
    var totalExpenseAmount: Double = 0
    var totalIncomeAmount: Double = 0
}
