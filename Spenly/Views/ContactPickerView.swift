import SwiftUI
import CoreData

struct ContactPickerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    @Binding var selectedContact: Contact?
    @Binding var isPresented: Bool
    
    @State private var searchText = ""
    @State private var sortOption: ContactSortOption = .usage
    @State private var showingAddContact = false
    @State private var newContactName = ""
    @State private var contacts: [Contact] = []
    @State private var filteredContacts: [Contact] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and Sort Header
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    // Transparent background
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .background(Color.black)
                
                // Contacts List
                if filteredContacts.isEmpty && !searchText.isEmpty {
                    // No search results
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No contacts found")
                            .font(selectedFont.font(size: 18, bold: true))
                            .foregroundColor(.primary)
                        
                        Text("Try a different search term or add a new contact")
                            .font(selectedFont.font(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button {
                            newContactName = searchText
                            showingAddContact = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add \"\(searchText)\" as new contact")
                            }
                            .font(selectedFont.font(size: 16))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(themeManager.getAccentColor(for: colorScheme))
                            .cornerRadius(12)
                        }
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
                            .font(selectedFont.font(size: 18))
                            .fontWeight(.semibold)
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
                            .font(selectedFont.font(size: 16))
                            .fontWeight(.medium)
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
                                ContactRowView(
                                    contact: contact,
                                    isSelected: selectedContact?.objectID == contact.objectID,
                                    onSelect: {
                                        selectedContact = contact
                                        let impact = UIImpactFeedbackGenerator(style: .light)
                                        impact.impactOccurred()
                                        isPresented = false
                                    }
                                )
                                .environmentObject(themeManager)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                
                // Add New Contact Button
                if !filteredContacts.isEmpty {
                    VStack(spacing: 0) {
                        Divider()
                            .background(.ultraThinMaterial)
                        
                        Button {
                            showingAddContact = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18))
                                Text("Add New Contact")
                                    .font(selectedFont.font(size: 16))
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .background(.ultraThinMaterial)
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("Select Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                }
            }
        }
        .onAppear {
            loadContacts()
        }
        .onChange(of: searchText) { _ in
            filterContacts()
        }
        .onChange(of: sortOption) { _ in
            loadContacts()
        }
        .sheet(isPresented: $showingAddContact) {
            AddContactSheet(
                contactName: $newContactName,
                onSave: { name in
                    if let newContact = ContactManager.shared.createContact(name: name, context: viewContext) {
                        selectedContact = newContact
                        loadContacts()
                        isPresented = false
                    }
                }
            )
            .environmentObject(themeManager)
        }
    }
    
    private func loadContacts() {
        contacts = ContactManager.shared.fetchContacts(context: viewContext, sortBy: sortOption)
        filterContacts()
    }
    
    private func filterContacts() {
        if searchText.isEmpty {
            filteredContacts = contacts
        } else {
            filteredContacts = ContactManager.shared.searchContacts(
                query: searchText,
                context: viewContext,
                sortBy: sortOption
            )
        }
    }
}

// MARK: - Contact Row View

struct ContactRowView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    let contact: Contact
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.safeName)
                        .font(selectedFont.font(size: 16, bold: true))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        if contact.safeUsageCount > 0 {
                            Text(contact.usageDisplay)
                                .font(selectedFont.font(size: 12))
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(selectedFont.font(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        Text(contact.lastUsedFormatted)
                            .font(selectedFont.font(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Selection Indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [
                        themeManager.getAccentColor(for: colorScheme).opacity(0.1),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .background(.ultraThinMaterial)
            )
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? themeManager.getAccentColor(for: colorScheme).opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Contact Sheet

struct AddContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    @Binding var contactName: String
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
                        .font(selectedFont.font(size: 16))
                        .fontWeight(.semibold)
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
            .background(.black)
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
        .onAppear {
            name = contactName
        }
    }
}
