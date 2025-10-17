import Foundation
import Contacts
import CoreData

final class ContactsImporter {
    static let shared = ContactsImporter()
    private let store = CNContactStore()
    private init() {}

    enum ImportError: Error {
        case permissionDenied
        case unavailable
        case unknown
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        store.requestAccess(for: .contacts) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func importAllContacts(context: NSManagedObjectContext, progress: ((Int) -> Void)? = nil, completion: @escaping (Result<Int, Error>) -> Void) {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized || status == .notDetermined else {
            completion(.failure(ImportError.permissionDenied))
            return
        }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor
        ]

        let fetchRequest = CNContactFetchRequest(keysToFetch: keysToFetch)
        var importedCount = 0

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var contactsToCreate: [String] = []
                
                // First pass: collect all contact names
                try self.store.enumerateContacts(with: fetchRequest) { contact, _ in
                    let name = self.displayName(for: contact)
                    if !name.isEmpty {
                        contactsToCreate.append(name)
                    }
                }
                
                // Second pass: create contacts in batches to avoid deadlocks
                let batchSize = 50
                for i in stride(from: 0, to: contactsToCreate.count, by: batchSize) {
                    let batch = Array(contactsToCreate[i..<min(i + batchSize, contactsToCreate.count)])
                    
                    context.performAndWait {
                        for name in batch {
                            // Reuse existing if present (case-insensitive)
                            if let _ = ContactManager.shared.fetchContactByName(name, context: context) {
                                // Already exists, skip
                            } else {
                                _ = ContactManager.shared.createContact(name: name, context: context)
                                importedCount += 1
                            }
                        }
                        
                        // Save batch
                        do {
                            try context.save()
                        } catch {
                            print("Error saving contact batch: \(error.localizedDescription)")
                        }
                        
                        DispatchQueue.main.async {
                            progress?(importedCount)
                        }
                    }
                }

                // Final cleanup and reconcile
                context.performAndWait {
                    ContactManager.shared.cleanupDuplicateContacts(context: context)
                    ContactManager.shared.reconcileUsageCounts(context: context)
                }

                DispatchQueue.main.async { completion(.success(importedCount)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func displayName(for contact: CNContact) -> String {
        let given = contact.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        let family = contact.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let org = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !given.isEmpty || !family.isEmpty {
            return [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        }
        return org
    }
}


