import Foundation
import CoreData

struct TransactionData: Codable {
    let id: UUID
    let amount: Double
    let date: Date
    let note: String?
    let isExpense: Bool
    let isCarryOver: Bool
    let categoryID: UUID?
    let receiptFileName: String?
    let receiptUploadDate: Date?
    
    init(from transaction: Transaction) {
        self.id = transaction.id ?? UUID()
        self.amount = transaction.amount
        self.date = transaction.date ?? Date()
        self.note = transaction.note
        self.isExpense = transaction.isExpense
        self.isCarryOver = transaction.isCarryOver
        self.categoryID = transaction.category?.id
        self.receiptFileName = transaction.receiptFileName
        self.receiptUploadDate = transaction.receiptUploadDate
    }
    
    func updateTransaction(_ transaction: Transaction, in context: NSManagedObjectContext) {
        transaction.id = self.id
        transaction.amount = self.amount
        transaction.date = self.date
        transaction.note = self.note
        transaction.isExpense = self.isExpense
        transaction.isCarryOver = self.isCarryOver
        transaction.receiptFileName = self.receiptFileName
        transaction.receiptUploadDate = self.receiptUploadDate
        
        if let categoryID = self.categoryID {
            let fetchRequest: NSFetchRequest<Category> = Category.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", categoryID as CVarArg)
            if let category = try? context.fetch(fetchRequest).first {
                transaction.category = category
            }
        }
    }
} 