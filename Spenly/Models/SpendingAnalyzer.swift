import CoreML
import Foundation
import CoreData

class SpendingAnalyzer {
    static let shared = SpendingAnalyzer()
    
    struct SpendingInsight {
        let title: String
        let description: String
        let type: InsightType
        
        enum InsightType {
            case warning
            case positive
            case suggestion
            
            var icon: String {
                switch self {
                case .warning: return "exclamationmark.triangle.fill"
                case .positive: return "checkmark.circle.fill"
                case .suggestion: return "lightbulb.fill"
                }
            }
            
            var color: String {
                switch self {
                case .warning: return "red"
                case .positive: return "green"
                case .suggestion: return "blue"
                }
            }
        }
    }
    
    func analyzeSpending(context: NSManagedObjectContext) -> [SpendingInsight] {
        var insights: [SpendingInsight] = []
        
        // Get transactions from last 3 months with optimized fetch
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        
        // Create compound predicate to filter by date, expense type, and current user's account
        var predicates: [NSPredicate] = [
            NSPredicate(format: "date >= %@ AND isExpense == YES", threeMonthsAgo as NSDate)
        ]
        
        // Add account filtering for current user
        if let currentAccount = AccountManager.shared.currentAccount {
            predicates.append(NSPredicate(format: "account == %@", currentAccount))
        }
        
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: true)]
        fetchRequest.fetchBatchSize = 100 // Increased from 50 for better performance with large datasets
        fetchRequest.fetchLimit = 1000 // Add limit to prevent memory issues with very large datasets
        
        guard let transactions = try? context.fetch(fetchRequest) else { return [] }
        
        // Process transactions in memory for better performance
        let categoryAnalysis = analyzeCategorySpending(transactions)
        let monthlyAnalysis = analyzeMonthlySpending(transactions)
        let trendAnalysis = analyzeSpendingTrends(transactions)
        
        // Combine insights efficiently
        insights.reserveCapacity(categoryAnalysis.count + monthlyAnalysis.count + trendAnalysis.count)
        insights.append(contentsOf: categoryAnalysis)
        insights.append(contentsOf: monthlyAnalysis)
        insights.append(contentsOf: trendAnalysis)
        
        return insights
    }
    
    private func analyzeCategorySpending(_ transactions: [Transaction]) -> [SpendingInsight] {
        var insights: [SpendingInsight] = []
        
        // Group transactions by category
        let categoryGroups = Dictionary(grouping: transactions) { $0.category?.name ?? "Uncategorized" }
        
        // Find highest spending category
        if let highestCategory = categoryGroups.max(by: { a, b in
            let aTotal = a.value.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
            let bTotal = b.value.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
            return aTotal < bTotal
        }) {
            let total = highestCategory.value.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
            insights.append(SpendingInsight(
                title: "Highest Spending Category",
                description: "Your highest spending is in '\(highestCategory.key)' category with total of $\(String(format: "%.2f", total))",
                type: .warning
            ))
        }
        
        return insights
    }
    
    private func analyzeMonthlySpending(_ transactions: [Transaction]) -> [SpendingInsight] {
        var insights: [SpendingInsight] = []
        
        // Group transactions by month
        let calendar = Calendar.current
        let monthlyGroups = Dictionary(grouping: transactions) {
            calendar.startOfMonth(for: $0.date ?? Date())
        }
        
        // Calculate average monthly spending
        let monthlyTotals = monthlyGroups.mapValues { transactions in
            transactions.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
        }
        
        if let averageSpending = monthlyTotals.values.average {
            // Check if current month's spending is higher than average
            if let currentMonthSpending = monthlyTotals[calendar.startOfMonth(for: Date())],
               currentMonthSpending > averageSpending * 1.2 {
                insights.append(SpendingInsight(
                    title: "Higher Than Average Spending",
                    description: "Your spending this month is \(String(format: "%.1f", (currentMonthSpending/averageSpending - 1) * 100))% higher than your 3-month average",
                    type: .warning
                ))
            } else if let currentMonthSpending = monthlyTotals[calendar.startOfMonth(for: Date())],
                      currentMonthSpending < averageSpending * 0.8 {
                insights.append(SpendingInsight(
                    title: "Lower Than Average Spending",
                    description: "Great job! Your spending this month is \(String(format: "%.1f", (1 - currentMonthSpending/averageSpending) * 100))% lower than your 3-month average",
                    type: .positive
                ))
            }
        }
        
        return insights
    }
    
    private func analyzeSpendingTrends(_ transactions: [Transaction]) -> [SpendingInsight] {
        var insights: [SpendingInsight] = []
        
        // Analyze spending trends
        let calendar = Calendar.current
        let dailyGroups = Dictionary(grouping: transactions) {
            calendar.startOfDay(for: $0.date ?? Date())
        }
        
        // Look for spending spikes
        let dailyTotals = dailyGroups.mapValues { transactions in
            transactions.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
        }.sorted { $0.key < $1.key }
        
        if let averageDaily = dailyTotals.map({ $0.value }).average {
            let spikeDays = dailyTotals.filter { $0.value > averageDaily * 2 }
            
            if !spikeDays.isEmpty {
                insights.append(SpendingInsight(
                    title: "Spending Spikes Detected",
                    description: "Found \(spikeDays.count) days with unusually high spending",
                    type: .suggestion
                ))
            }
        }
        
        return insights
    }
    
    static func categoryDistribution(transactions: [Transaction]) -> [(category: String, amount: Double)] {
        let expenseTransactions = transactions.filter { $0.isExpense }
        var categoryAmounts: [String: Double] = [:]
        
        for transaction in expenseTransactions {
            let categoryName = transaction.category?.name ?? "Uncategorized"
            categoryAmounts[categoryName, default: 0] += transaction.amount
        }
        
        return categoryAmounts.map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 }
    }
    
    static func monthlySpending(transactions: [Transaction], months: Int = 6) -> [(date: Date, amount: Double)] {
        let calendar = Calendar.current
        let now = Date()
        var result: [(Date, Double)] = []
        
        for monthOffset in 0..<months {
            guard let monthStart = calendar.date(byAdding: .month, value: -monthOffset, to: now) else { continue }
            guard let monthStartDate = calendar.date(from: calendar.dateComponents([.year, .month], from: monthStart)) else { continue }
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStartDate) else { continue }
            
            let monthTransactions = transactions.filter { transaction in
                guard let date = transaction.date else { return false }
                return date >= monthStartDate && date < nextMonth && transaction.isExpense
            }
            
            let totalAmount = monthTransactions.reduce(0) { $0 + $1.amount }
            result.append((monthStartDate, totalAmount))
        }
        
        return result.reversed()
    }
    
    static func topSpendingCategories(transactions: [Transaction], limit: Int = 5) -> [(category: String, amount: Double)] {
        return categoryDistribution(transactions: transactions)
            .prefix(limit)
            .map { ($0.category, $0.amount) }
    }
    
    static func monthOverMonthChange(transactions: [Transaction]) -> Double? {
        let monthly = monthlySpending(transactions: transactions, months: 2)
        guard monthly.count == 2 else { return nil }
        
        let currentMonth = monthly[1].amount
        let previousMonth = monthly[0].amount
        
        guard previousMonth > 0 else { return nil }
        return ((currentMonth - previousMonth) / previousMonth) * 100
    }
}

// Helper extensions
extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}

extension Collection where Element: BinaryFloatingPoint {
    var average: Element? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Element(count)
    }
} 