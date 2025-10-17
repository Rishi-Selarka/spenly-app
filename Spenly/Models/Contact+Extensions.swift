import Foundation
import CoreData

extension Contact {
    
    // MARK: - Safe Getters
    
    var safeName: String {
        return name ?? "Unknown Contact"
    }
    
    var safeCreatedAt: Date {
        return createdAt ?? Date()
    }
    
    var safeLastUsedAt: Date? {
        return lastUsedAt
    }
    
    var safeUsageCount: Int32 {
        return usageCount
    }
    
    // MARK: - Computed Properties
    
    var transactionCount: Int {
        return transactions?.count ?? 0
    }
    
    var hasBeenUsed: Bool {
        return safeUsageCount > 0
    }
    
    var lastUsedFormatted: String {
        guard let lastUsed = safeLastUsedAt else {
            return "Never used"
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUsed, relativeTo: Date())
    }
    
    var createdFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: safeCreatedAt)
    }
    
    // MARK: - Comparison
    
    func compareByName(_ other: Contact) -> Bool {
        return safeName.localizedCaseInsensitiveCompare(other.safeName) == .orderedAscending
    }
    
    func compareByUsage(_ other: Contact) -> Bool {
        if safeUsageCount != other.safeUsageCount {
            return safeUsageCount > other.safeUsageCount
        }
        return compareByName(other)
    }
    
    func compareByRecent(_ other: Contact) -> Bool {
        let thisLastUsed = safeLastUsedAt ?? Date.distantPast
        let otherLastUsed = other.safeLastUsedAt ?? Date.distantPast
        
        if thisLastUsed != otherLastUsed {
            return thisLastUsed > otherLastUsed
        }
        return compareByName(other)
    }
    
    // MARK: - Validation
    
    var isValid: Bool {
        return !safeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Display Helpers
    
    var displayName: String {
        return safeName
    }
    
    var usageDisplay: String {
        let count = safeUsageCount
        if count == 0 {
            return "Not used"
        } else if count == 1 {
            return "Used once"
        } else {
            return "Used \(count) times"
        }
    }
    
    var quickInfo: String {
        return "\(displayName) • \(usageDisplay)"
    }
    
    // MARK: - Search Helpers
    
    func matchesSearch(_ query: String) -> Bool {
        let searchQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let contactName = safeName.lowercased()
        
        if searchQuery.isEmpty {
            return true
        }
        
        return contactName.contains(searchQuery)
    }
    
    // MARK: - Statistics
    
    var totalTransactionAmount: Double {
        guard let transactions = transactions as? Set<Transaction> else { return 0.0 }
        
        return transactions.reduce(0.0) { total, transaction in
            return total + transaction.amount
        }
    }
    
    var averageTransactionAmount: Double {
        let count = transactionCount
        guard count > 0 else { return 0.0 }
        return totalTransactionAmount / Double(count)
    }
    
    var mostRecentTransaction: Transaction? {
        guard let transactions = transactions as? Set<Transaction> else { return nil }
        
        return transactions.max { transaction1, transaction2 in
            let date1 = transaction1.date ?? Date.distantPast
            let date2 = transaction2.date ?? Date.distantPast
            return date1 < date2
        }
    }
    
    var oldestTransaction: Transaction? {
        guard let transactions = transactions as? Set<Transaction> else { return nil }
        
        return transactions.min { transaction1, transaction2 in
            let date1 = transaction1.date ?? Date.distantPast
            let date2 = transaction2.date ?? Date.distantPast
            return date1 < date2
        }
    }
    
    // MARK: - Export Helpers
    
    var exportData: [String: Any] {
        return [
            "name": safeName,
            "createdAt": safeCreatedAt,
            "lastUsedAt": safeLastUsedAt as Any,
            "usageCount": safeUsageCount,
            "transactionCount": transactionCount,
            "totalAmount": totalTransactionAmount,
            "averageAmount": averageTransactionAmount
        ]
    }
}
