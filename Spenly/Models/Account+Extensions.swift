import Foundation
import CoreData


extension Account {
    static func createDefault(context: NSManagedObjectContext) -> Account {
        let account = Account(context: context)
        account.id = UUID()
        account.name = "Default Account"
        account.isDefault = true
        account.createdAt = Date()
        return account
    }
} 
