import Foundation
import CoreData

class ContactManager {
    static let shared = ContactManager()
    
    private init() {}
    
    // MARK: - Setup
    
    func setupInitialContacts(context: NSManagedObjectContext) {
        // No initial contacts needed - users will add their own
        // This method exists for consistency with other managers
    }
    
    // MARK: - CRUD Operations
    
    func createContact(name: String, context: NSManagedObjectContext) -> Contact? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if contact already exists
        if let existingContact = fetchContactByName(trimmedName, context: context) {
            return existingContact
        }
        
        let newContact = NSEntityDescription.insertNewObject(forEntityName: "Contact", into: context) as! Contact
        newContact.id = UUID()
        newContact.name = trimmedName
        newContact.createdAt = Date()
        newContact.usageCount = 0
        
        do {
            try context.save()
            return newContact
        } catch {
            print("Error creating contact: \(error.localizedDescription)")
            context.delete(newContact)
            return nil
        }
    }
    
    func updateContact(_ contact: Contact, newName: String, context: NSManagedObjectContext) -> Bool {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if another contact with this name already exists
        if let existingContact = fetchContactByName(trimmedName, context: context),
           existingContact != contact {
            return false // Name already exists
        }
        
        contact.name = trimmedName
        
        do {
            try context.save()
            return true
        } catch {
            print("Error updating contact: \(error.localizedDescription)")
            return false
        }
    }
    
    func deleteContact(_ contact: Contact, context: NSManagedObjectContext) -> Bool {
        // Nullify relationships with transactions
        if let transactions = contact.transactions as? Set<Transaction> {
            for transaction in transactions {
                transaction.contact = nil
            }
        }
        
        context.delete(contact)
        
        do {
            try context.save()
            return true
        } catch {
            print("Error deleting contact: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Usage Tracking
    
    func incrementUsageCount(contact: Contact, context: NSManagedObjectContext) {
        contact.usageCount += 1
        contact.lastUsedAt = Date()
        
        do {
            try context.save()
        } catch {
            print("Error updating contact usage: \(error.localizedDescription)")
        }
    }
    
    func decrementUsageCount(contact: Contact, context: NSManagedObjectContext) {
        contact.usageCount = max(0, contact.usageCount - 1)
        // Optionally refresh lastUsedAt to most recent transaction date
        if let latest = mostRecentTransactionDate(for: contact, context: context) {
            contact.lastUsedAt = latest
        } else {
            contact.lastUsedAt = nil
        }
        do {
            try context.save()
        } catch {
            print("Error decrementing contact usage: \(error.localizedDescription)")
        }
    }
    
    private func mostRecentTransactionDate(for contact: Contact, context: NSManagedObjectContext) -> Date? {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = NSPredicate(format: "contact == %@", contact)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]
        request.fetchLimit = 1
        return try? context.fetch(request).first?.date
    }
    
    /// Recalculate usageCount and lastUsedAt for all contacts based on existing transactions
    func reconcileUsageCounts(context: NSManagedObjectContext) {
        let contactRequest: NSFetchRequest<Contact> = Contact.fetchRequest()
        guard let allContacts = try? context.fetch(contactRequest) else { return }
        
        for contact in allContacts {
            let txReq: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            txReq.predicate = NSPredicate(format: "contact == %@", contact)
            if let matches = try? context.count(for: txReq) {
                contact.usageCount = Int32(matches)
            }
            contact.lastUsedAt = mostRecentTransactionDate(for: contact, context: context)
        }
        do { try context.save() } catch {
            print("Error reconciling contact usage: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Fetch Operations
    
    func fetchContacts(context: NSManagedObjectContext, sortBy: ContactSortOption = .usage) -> [Contact] {
        let request: NSFetchRequest<Contact> = Contact.fetchRequest()
        
        switch sortBy {
        case .name:
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.name, ascending: true)]
        case .usage:
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \Contact.usageCount, ascending: false),
                NSSortDescriptor(keyPath: \Contact.name, ascending: true)
            ]
        case .recent:
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \Contact.lastUsedAt, ascending: false),
                NSSortDescriptor(keyPath: \Contact.name, ascending: true)
            ]
        }
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching contacts: \(error.localizedDescription)")
            return []
        }
    }
    
    func searchContacts(query: String, context: NSManagedObjectContext, sortBy: ContactSortOption = .usage) -> [Contact] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fetchContacts(context: context, sortBy: sortBy)
        }
        
        let request: NSFetchRequest<Contact> = Contact.fetchRequest()
        request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", query.trimmingCharacters(in: .whitespacesAndNewlines))
        
        switch sortBy {
        case .name:
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.name, ascending: true)]
        case .usage:
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \Contact.usageCount, ascending: false),
                NSSortDescriptor(keyPath: \Contact.name, ascending: true)
            ]
        case .recent:
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \Contact.lastUsedAt, ascending: false),
                NSSortDescriptor(keyPath: \Contact.name, ascending: true)
            ]
        }
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error searching contacts: \(error.localizedDescription)")
            return []
        }
    }
    
    func fetchContactByName(_ name: String, context: NSManagedObjectContext) -> Contact? {
        let request: NSFetchRequest<Contact> = Contact.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[cd] %@", name.trimmingCharacters(in: .whitespacesAndNewlines))
        request.fetchLimit = 1
        
        do {
            let contacts = try context.fetch(request)
            return contacts.first
        } catch {
            print("Error fetching contact by name: \(error.localizedDescription)")
            return nil
        }
    }
    
    func getContactTransactionCount(_ contact: Contact) -> Int {
        return contact.transactions?.count ?? 0
    }
    
    // MARK: - Statistics
    
    func getTotalContactCount(context: NSManagedObjectContext) -> Int {
        let request: NSFetchRequest<Contact> = Contact.fetchRequest()
        
        do {
            return try context.count(for: request)
        } catch {
            print("Error counting contacts: \(error.localizedDescription)")
            return 0
        }
    }
    
    func getMostUsedContacts(context: NSManagedObjectContext, limit: Int = 5) -> [Contact] {
        let request: NSFetchRequest<Contact> = Contact.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Contact.usageCount, ascending: false),
            NSSortDescriptor(keyPath: \Contact.name, ascending: true)
        ]
        request.fetchLimit = limit
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching most used contacts: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Duplicate Cleanup
    
    /// Normalize a contact name for duplicate detection
    private func normalizeContactName(_ name: String) -> String {
        return name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(of: " ", with: "")
    }
    
    /// Merge duplicate contacts by normalized name. Keeps the first encountered as keeper, reassigns transactions from duplicates, deletes duplicates.
    func cleanupDuplicateContacts(context: NSManagedObjectContext) {
        let request: NSFetchRequest<Contact> = Contact.fetchRequest()
        guard let contacts = try? context.fetch(request) else { return }
        
        var unique: [String: Contact] = [:]
        var toDelete: [Contact] = []
        
        for contact in contacts {
            let name = contact.name ?? ""
            let key = normalizeContactName(name)
            if let keeper = unique[key] {
                // Reassign transactions to keeper
                if let txs = contact.transactions as? Set<Transaction> {
                    for t in txs { t.contact = keeper }
                }
                toDelete.append(contact)
            } else {
                unique[key] = contact
            }
        }
        
        for c in toDelete { context.delete(c) }
        do {
            try context.save()
            // Reconcile counts after merge
            reconcileUsageCounts(context: context)
        } catch {
            print("Error cleaning duplicate contacts: \(error.localizedDescription)")
        }
    }
}

// MARK: - Sort Options

enum ContactSortOption: String, CaseIterable, Identifiable {
    case name = "Name"
    case usage = "Most Used"
    case recent = "Recently Used"
    
    var id: String { rawValue }
    
    var description: String { rawValue }
}
