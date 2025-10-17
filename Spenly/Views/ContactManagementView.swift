import SwiftUI
import CoreData

struct ContactManagementView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    @State private var searchText = ""
    // Sorting
    enum LocalSortOption: String, CaseIterable {
        case aToZ = "A to Z"
        case zToA = "Z to A"
        case mostUsed = "Most Used"
        case recentlyUsed = "Recently Used"
    }
    @State private var localSort: LocalSortOption = .mostUsed
    @State private var contacts: [Contact] = []
    @State private var filteredContacts: [Contact] = []
    @State private var showingAddContact = false
    @State private var showingImportSheet = false
    @State private var isImporting = false
    @State private var importCount: Int = 0
    @State private var showImportResult = false
    @State private var showingSortSheet = false
    @State private var contactToEdit: Contact?
    @State private var contactToDelete: Contact?
    @State private var showingDeleteAlert = false
    @State private var showingEditSheet = false
    @State private var editContactName = ""
    
    var body: some View {
        VStack(spacing: 0) {
            searchAndSortHeader
            
            contactsContent
        }
        .background(Color.black)
        .navigationTitle("Manage Contacts")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showingAddContact = true
                    } label: {
                        Text("Add Contact")
                            .font(selectedFont.font(size: 16))
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                    }
                    
                    Button {
                        startContactsImport()
                    } label: {
                        Text("Sync Contacts")
                            .font(selectedFont.font(size: 16))
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                    }
                }
            }
        }
        .onAppear {
            loadContacts()
        }
        .onChange(of: searchText) { _ in
            filterContacts()
        }
        .onChange(of: localSort) { _ in
            loadContacts()
        }
        .alert("Contacts Imported", isPresented: $showImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Successfully imported \(importCount) contacts")
        }
        .overlay(importProgressOverlay)
        .sheet(isPresented: $showingSortSheet) {
            SortPickerSheet(
                selected: localSort,
                onSelect: { option in
                    withAnimation { localSort = option }
                    showingSortSheet = false
                }
            )
            .environmentObject(themeManager)
            .presentationDetents([.fraction(0.3), .medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddContact) {
            AddContactManagementSheet(
                onSave: { name in
                    _ = ContactManager.shared.createContact(name: name, context: viewContext)
                    loadContacts()
                }
            )
            .environmentObject(themeManager)
        }
        .sheet(isPresented: $showingEditSheet) {
            EditContactSheet(
                contact: contactToEdit,
                contactName: $editContactName,
                onSave: { name in
                    if let contact = contactToEdit {
                        let success = ContactManager.shared.updateContact(contact, newName: name, context: viewContext)
                        if !success {
                            // Duplicate or invalid name
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.error)
                        } else {
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                        }
                        loadContacts()
                    }
                }
            )
            .environmentObject(themeManager)
        }
        .alert("Delete Contact", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let contact = contactToDelete {
                    _ = ContactManager.shared.deleteContact(contact, context: viewContext)
                    loadContacts()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let contact = contactToDelete {
                Text("Are you sure you want to delete \"\(contact.safeName)\"? This will remove the contact from all associated transactions.")
            }
        }
    }
    
    private var searchAndSortHeader: some View {
        VStack(spacing: 12) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
                
                TextField("Search contacts...", text: $searchText)
                    .font(selectedFont.font(size: 16))
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                
                Button {
                    showingSortSheet = true
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // Transparent background as requested
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(Color.black)
    }
    
    private var contactsContent: some View {
        Group {
            if filteredContacts.isEmpty && !searchText.isEmpty {
                // No search results
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No contacts found")
                        .font(selectedFont.font(size: 18, bold: true))
                        .foregroundColor(.primary)
                    
                    Text("Try a different search term")
                        .font(selectedFont.font(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if filteredContacts.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No contacts yet")
                        .font(selectedFont.font(size: 18, bold: true))
                        .foregroundColor(.primary)
                    
                    Text("Add your first contact to get started")
                        .font(selectedFont.font(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        showingAddContact = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Contact")
                        }
                        .font(selectedFont.font(size: 16, bold: true))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(themeManager.getAccentColor(for: colorScheme))
                        .cornerRadius(12)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                // Contacts List
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredContacts, id: \.objectID) { contact in
                            ContactManagementRowView(
                                contact: contact,
                                onEdit: {
                                    contactToEdit = contact
                                    editContactName = contact.safeName
                                    showingEditSheet = true
                                },
                                onDelete: {
                                    contactToDelete = contact
                                    showingDeleteAlert = true
                                }
                            )
                            .environmentObject(themeManager)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }
    
    private func loadContacts() {
        switch localSort {
        case .aToZ:
            contacts = ContactManager.shared.fetchContacts(context: viewContext, sortBy: .name)
        case .zToA:
            contacts = ContactManager.shared.fetchContacts(context: viewContext, sortBy: .name)
                .sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedDescending }
        case .mostUsed:
            contacts = ContactManager.shared.fetchContacts(context: viewContext, sortBy: .usage)
        case .recentlyUsed:
            contacts = ContactManager.shared.fetchContacts(context: viewContext, sortBy: .recent)
        }
        filterContacts()
    }
    
    private func filterContacts() {
        if searchText.isEmpty {
            filteredContacts = contacts
        } else {
            let baseSorted: [Contact]
            switch localSort {
            case .aToZ:
                baseSorted = ContactManager.shared.searchContacts(query: searchText, context: viewContext, sortBy: .name)
            case .zToA:
                baseSorted = ContactManager.shared.searchContacts(query: searchText, context: viewContext, sortBy: .name)
                    .sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedDescending }
            case .mostUsed:
                baseSorted = ContactManager.shared.searchContacts(query: searchText, context: viewContext, sortBy: .usage)
            case .recentlyUsed:
                baseSorted = ContactManager.shared.searchContacts(query: searchText, context: viewContext, sortBy: .recent)
            }
            filteredContacts = baseSorted
        }
    }
    
    // MARK: - Import Contacts
    private func startContactsImport() {
        ContactsImporter.shared.requestAccess { granted in
            guard granted else {
                // Offer to open Settings
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                return
            }
            isImporting = true
            importCount = 0
            ContactsImporter.shared.importAllContacts(context: viewContext, progress: { count in
                importCount = count
            }, completion: { result in
                isImporting = false
                switch result {
                case .success(let imported):
                    importCount = imported
                    loadContacts()
                    showImportResult = true
                case .failure:
                    importCount = 0
                    // brief error haptic
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
            })
        }
    }
    
    @ViewBuilder
    private var importProgressOverlay: some View {
        if isImporting {
            ZStack {
                Color.black.opacity(0.25).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView(value: Double(importCount).truncatingRemainder(dividingBy: 100.0), total: 100)
                        .progressViewStyle(.linear)
                        .tint(themeManager.getAccentColor(for: colorScheme))
                        .frame(maxWidth: 240)
                    Text("Importing contacts…")
                        .font(selectedFont.font(size: 14))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(.ultraThinMaterial)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(themeManager.getAccentColor(for: colorScheme).opacity(0.3), lineWidth: 1)
                )
            }
            .transition(.opacity)
        } else {
            EmptyView()
        }
    }
}

// MARK: - Sort Picker Sheet
private struct SortPickerSheet: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    let selected: ContactManagementView.LocalSortOption
    let onSelect: (ContactManagementView.LocalSortOption) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
            
            Text("Sort Contacts")
                .font(selectedFont.font(size: 18, bold: true))
                .foregroundColor(.primary)
            
            VStack(spacing: 10) {
                sortRow(title: "A to Z", option: .aToZ)
                sortRow(title: "Z to A", option: .zToA)
                sortRow(title: "Most Used", option: .mostUsed)
                sortRow(title: "Recently Used", option: .recentlyUsed)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }

    }
    
    @ViewBuilder private func sortRow(title: String, option: ContactManagementView.LocalSortOption) -> some View {
        Button {
            onSelect(option)
        } label: {
            HStack {
                Text(title)
                    .font(selectedFont.font(size: 16))
                    .foregroundColor(.primary)
                Spacer()
                if selected == option {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                }
            }
            .padding()
            .background(Color.white.opacity(0.06))
            .cornerRadius(12)
        }
    }
}

// MARK: - Contact Management Row View

struct ContactManagementRowView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    let contact: Contact
    let onEdit: () -> Void
    let onDelete: () -> Void
    // Removed view transactions per request
    
    var body: some View {
        HStack(spacing: 12) {
            // Contact Icon
            ZStack {
                Circle()
                    .fill(themeManager.getAccentColor(for: colorScheme).opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "person.fill")
                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                    .font(.system(size: 18))
            }
            
            // Contact Info
            VStack(alignment: .leading, spacing: 4) {
                    Text(contact.safeName)
                        .font(selectedFont.font(size: 16, bold: true))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text("\(contact.transactionCount) transactions")
                        .font(selectedFont.font(size: 12))
                        .foregroundColor(.secondary)
                    
                    if contact.safeUsageCount > 0 {
                        Text("•")
                            .font(selectedFont.font(size: 12))
                            .foregroundColor(.secondary)
                        
                        Text(contact.usageDisplay)
                            .font(selectedFont.font(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                if contact.safeLastUsedAt != nil {
                    Text("Last used: \(contact.lastUsedFormatted)")
                        .font(selectedFont.font(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            ZStack {
                Color.black
                LinearGradient(
                    colors: [
                        themeManager.getAccentColor(for: colorScheme).opacity(0.10),
                        themeManager.getAccentColor(for: colorScheme).opacity(0.02)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .blendMode(.plusLighter)
            }
        )
        .cornerRadius(14)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(themeManager.getAccentColor(for: colorScheme))
        }
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Add Contact Management Sheet

struct AddContactManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    let onSave: (String) -> Void
    
    @State private var name = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                    
                    Text("Add New Contact")
                        .font(selectedFont.font(size: 24, bold: true))
                        .foregroundColor(.primary)
                    
                    Text("Enter the name of the person or business")
                        .font(selectedFont.font(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Contact Name")
                        .font(selectedFont.font(size: 14))
                        .foregroundColor(.secondary)
                    
                    TextField("Enter name", text: $name)
                        .font(selectedFont.font(size: 16))
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(themeManager.getAccentColor(for: colorScheme).opacity(0.3), lineWidth: 1)
                        )
                }
                
                Spacer()
                
                Button {
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedName.isEmpty {
                        onSave(trimmedName)
                        dismiss()
                    }
                } label: {
                    Text("Add Contact")
                        .font(selectedFont.font(size: 16, bold: true))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
                            Color.gray : themeManager.getAccentColor(for: colorScheme)
                        )
                        .cornerRadius(12)
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(24)
            .background(Color.black)
            .navigationTitle("New Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                }
            }
        }
    }
}

// MARK: - Edit Contact Sheet

struct EditContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    let contact: Contact?
    @Binding var contactName: String
    let onSave: (String) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 48))
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                    
                    Text("Edit Contact")
                        .font(selectedFont.font(size: 24, bold: true))
                        .foregroundColor(.primary)
                    
                    Text("Update the contact name")
                        .font(selectedFont.font(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Contact Name")
                        .font(selectedFont.font(size: 14))
                        .foregroundColor(.secondary)
                    
                    TextField("Enter name", text: $contactName)
                        .font(selectedFont.font(size: 16))
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(themeManager.getAccentColor(for: colorScheme).opacity(0.3), lineWidth: 1)
                        )
                }
                
                Spacer()
                
                Button {
                    let trimmedName = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedName.isEmpty {
                        onSave(trimmedName)
                        dismiss()
                    }
                } label: {
                    Text("Save Changes")
                        .font(selectedFont.font(size: 16, bold: true))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
                            Color.gray : themeManager.getAccentColor(for: colorScheme)
                        )
                        .cornerRadius(12)
                }
                .disabled(contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(24)
            .background(Color.black)
            .navigationTitle("Edit Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                }
            }
        }
    }
}
