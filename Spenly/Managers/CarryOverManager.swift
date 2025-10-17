import Foundation
import CoreData

class CarryOverManager: ObservableObject {
    static let shared = CarryOverManager()
    @Published var isEnabled = UserDefaults.standard.bool(forKey: "carryOverEnabled")
    
    // Change in-memory dictionary to use UserDefaults for persistence
    private var deletedCarryOvers: [String: Bool] {
        get {
            return UserDefaults.standard.dictionary(forKey: "deletedCarryOvers") as? [String: Bool] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "deletedCarryOvers")
        }
    }
    
    func toggleCarryOver(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "carryOverEnabled")
    }
    
    // Add a method to mark a carry-over as manually deleted
    func markCarryOverDeleted(for date: Date, account: Account) {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        let key = "\(accountKey(account))-\(year)-\(month)"
        
        // Update the dictionary in UserDefaults
        var updatedDict = deletedCarryOvers
        updatedDict[key] = true
        deletedCarryOvers = updatedDict
        
        // Clean up old entries to prevent indefinite growth
        cleanupOldDeletedEntries()
    }
    
    // New method to clean up entries older than 1 year
    private func cleanupOldDeletedEntries() {
        let calendar = Calendar.current
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: Date())!
        var updatedDict = deletedCarryOvers
        
        // Loop through and remove entries older than one year
        for key in updatedDict.keys {
            // Parse the key to get year and month
            let components = key.split(separator: "-")
            if components.count >= 2,
               let year = Int(components[components.count - 2]),
               let month = Int(components[components.count - 1]) {
                
                var dateComponents = DateComponents()
                dateComponents.year = year
                dateComponents.month = month
                dateComponents.day = 1
                
                if let entryDate = calendar.date(from: dateComponents),
                   entryDate < oneYearAgo {
                    updatedDict.removeValue(forKey: key)
                }
            }
        }
        
        // Save the cleaned dictionary
        if updatedDict.count != deletedCarryOvers.count {
            deletedCarryOvers = updatedDict
        }
    }
    
    func processMonthEndBalance(context: NSManagedObjectContext, account: Account) {
        guard isEnabled else { return }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Check if we're in a new month 
        // Modified to handle missed months by checking up to 3 months back
        for monthOffset in 0...2 {
            let targetMonth = calendar.date(byAdding: .month, value: -monthOffset, to: now)!
            let previousMonth = calendar.date(byAdding: .month, value: -1, to: targetMonth)!
            
            // Get the month and year for tracking
            let month = calendar.component(.month, from: targetMonth)
            let year = calendar.component(.year, from: targetMonth)
            let key = "\(accountKey(account))-\(year)-\(month)"
            
            // Check if this carry-over was manually deleted by the user
            if deletedCarryOvers[key] == true {
                print("Skipping carry-over creation for \(year)-\(month) because it was manually deleted")
                continue
            }
            
            // Check if carry-over already exists for this month
            let existingCarryOver = checkExistingCarryOver(for: targetMonth, account: account, context: context)
            if existingCarryOver {
                // Skip this month if carry-over already exists
                continue
            }
            
            // Calculate previous month's balance
            let previousMonthBalance = calculateMonthBalance(for: previousMonth, account: account, context: context)
            
            // Only carry forward positive balances
            if previousMonthBalance > 0 {
                // Log the carry-over operation for debugging
                print("Creating carry-over transaction of \(previousMonthBalance) for \(account.name ?? "unnamed account") for \(year)-\(month)")
                
                createCarryOverTransaction(
                    amount: previousMonthBalance,
                    date: getStartOfMonth(for: targetMonth),
                    account: account,
                    context: context
                )
                
                // Continue loop to allow backfill for up to 3 months
            }
        }
    }
    
    private func calculateMonthBalance(for date: Date, account: Account, context: NSManagedObjectContext) -> Double {
        let startOfMonth = getStartOfMonth(for: date)
        let endOfMonth = getEndOfMonth(for: date)
        
        let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        // Include carry-over transactions to correctly compute true ending balance
        fetchRequest.predicate = NSPredicate(format: "account == %@ AND date >= %@ AND date <= %@",
                                           account, startOfMonth as NSDate, endOfMonth as NSDate)
        
        let transactions = (try? context.fetch(fetchRequest)) ?? []
        let income = transactions.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount }
        let expenses = transactions.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
        
        // Final balance = all incomes (including carry-overs) - all expenses
        return income - expenses
    }
    
    private func checkExistingCarryOver(for date: Date, account: Account, context: NSManagedObjectContext) -> Bool {
        let startOfMonth = getStartOfMonth(for: date)
        let endOfMonth = getEndOfMonth(for: date)
        
        let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "account == %@ AND date >= %@ AND date <= %@ AND isCarryOver == YES",
                                           account, startOfMonth as NSDate, endOfMonth as NSDate)
        
        let count = (try? context.count(for: fetchRequest)) ?? 0
        return count > 0
    }
    
    private func createCarryOverTransaction(amount: Double, date: Date, account: Account, context: NSManagedObjectContext) {
        // Perform the operation on the context's queue to ensure thread safety
        context.perform {
            // Double-check that carry-over doesn't already exist (race condition protection)
            let startOfMonth = self.getStartOfMonth(for: date)
            let endOfMonth = self.getEndOfMonth(for: date)
            
            let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "account == %@ AND date >= %@ AND date <= %@ AND isCarryOver == YES",
                                               account, startOfMonth as NSDate, endOfMonth as NSDate)
            
            let existingCount = (try? context.count(for: fetchRequest)) ?? 0
            if existingCount > 0 {
                print("Carry-over already exists for \(self.formatMonth(for: date)) - skipping creation")
                return
            }
            
            let category = self.findOrCreateCarryOverCategory(context: context)
            
            let transaction = Transaction(context: context)
            transaction.id = UUID()
            transaction.amount = amount
            transaction.date = date
            transaction.note = "Balance carried forward from \(self.formatMonth(for: date, offset: -1))"
            transaction.isExpense = false
            transaction.isCarryOver = true
            transaction.account = account
            transaction.category = category
            
            do {
                try context.save()
                print("Successfully created carry-over transaction")
                
                // Notify that data has changed
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("TransactionsUpdated"),
                        object: nil
                    )
                }
            } catch {
                print("Error saving carry-over transaction: \(error)")
            }
        }
    }
    
    private func findOrCreateCarryOverCategory(context: NSManagedObjectContext) -> Category {
        let fetchRequest: NSFetchRequest<Category> = Category.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name == %@", "Balance Carry-Over")
        
        if let existing = try? context.fetch(fetchRequest).first {
            return existing
        }
        
        let category = Category(context: context)
        category.id = UUID()
        category.name = "Balance Carry-Over"
        category.type = "income"
        category.icon = "arrow.forward.circle.fill"
        category.isCustom = false
        
        return category
    }
    
    private func formatMonth(for date: Date, offset: Int = 0) -> String {
        let calendar = Calendar.current
        let offsetDate = calendar.date(byAdding: .month, value: offset, to: date) ?? date
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: offsetDate)
    }
    
    // Internal date helper methods
    private func getStartOfMonth(for date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date // Safe fallback to original date
    }
    
    private func getEndOfMonth(for date: Date) -> Date {
        let calendar = Calendar.current
        let startOfMonth = getStartOfMonth(for: date)
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            // Safe fallback: return end of current day if date calculation fails
            return calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
        }
        let lastDay = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? date
        return calendar.date(bySettingHour: 23, minute: 59, second: 59, of: lastDay) ?? lastDay
    }
} 

// MARK: - Helpers
private extension CarryOverManager {
    func accountKey(_ account: Account) -> String {
        account.id?.uuidString ?? account.objectID.uriRepresentation().absoluteString
    }
}