import Foundation
import UserNotifications
import CoreData

class MonthlyNotificationManager {
    static let shared = MonthlyNotificationManager()
    
    func scheduleMonthlyNotification(context: NSManagedObjectContext) {
        // Respect centralized permission flow: only schedule if already authorized
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized {
                self.scheduleEndOfMonthNotification(context: context)
            } else {
                print("🔔 Monthly notification not scheduled yet; will schedule after login when permissions are granted")
            }
        }
    }
    
    private func scheduleEndOfMonthNotification(context: NSManagedObjectContext) {
        // Remove any existing notifications
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["monthlySpendingSummary"])
        
        // Create date components for last day of month
        // Note: We'll schedule this to trigger on the 28th of each month to ensure it works for all months
        var dateComponents = DateComponents()
        dateComponents.hour = 20 // 8 PM
        dateComponents.minute = 0
        dateComponents.day = 28 // 28th works for all months (safer than trying to get exact last day)
        
        // Create the trigger
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Monthly Spending Summary"
        content.body = "Your monthly spending report is ready to view."
        
        // Create the request
        let request = UNNotificationRequest(
            identifier: "monthlySpendingSummary",
            content: content,
            trigger: trigger
        )
        
        // Schedule the notification
        UNUserNotificationCenter.current().add(request)
    }
    
    func generateMonthlySummary(context: NSManagedObjectContext) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        // Get start and end of current month
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else {
            return "Unable to generate summary"
        }
        
        // Fetch transactions for current month
        let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        
        // Create compound predicate to filter by date and current user's account
        var predicates: [NSPredicate] = [
            NSPredicate(format: "date >= %@ AND date <= %@ AND isCarryOver == NO", 
                       monthStart as NSDate, monthEnd as NSDate)
        ]
        
        // Add account filtering for current user
        if let currentAccount = AccountManager.shared.currentAccount {
            predicates.append(NSPredicate(format: "account == %@", currentAccount))
        }
        
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        do {
            let transactions = try context.fetch(fetchRequest)
            let totalExpenses = transactions.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
            let totalIncome = transactions.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount }
            let netAmount = totalIncome - totalExpenses
            
            // Get top spending categories
            let expensesByCategory = Dictionary(grouping: transactions.filter { $0.isExpense }) { $0.category?.name ?? "Uncategorized" }
            let topCategories = expensesByCategory.map { ($0.key, $0.value.reduce(0) { $0 + $1.amount }) }
                .sorted { $0.1 > $1.1 }
                .prefix(3)
            
            // Format the summary
            var summary = "Monthly Summary\n\n"
            summary += "Total Income: \(CurrencyFormatter.format(totalIncome, currency: .usd))\n"
            summary += "Total Expenses: \(CurrencyFormatter.format(totalExpenses, currency: .usd))\n"
            summary += "Net Amount: \(CurrencyFormatter.format(netAmount, currency: .usd))\n\n"
            summary += "Top Spending Categories:\n"
            topCategories.forEach { category, amount in
                summary += "• \(category): \(CurrencyFormatter.format(amount, currency: .usd))\n"
            }
            
            return summary
        } catch {
            return "Error generating summary: \(error.localizedDescription)"
        }
    }
} 