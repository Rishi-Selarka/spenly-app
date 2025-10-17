import SwiftUI
import CoreData

// Helper extension to calculate account balance
extension Account {
    func calculateBalance(context: NSManagedObjectContext) -> Double {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let endOfMonth = calendar.dateInterval(of: .month, for: now)?.end ?? now
        
        let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "account == %@ AND date >= %@ AND date < %@",
                                           self, startOfMonth as NSDate, endOfMonth as NSDate)
        
        let transactions = (try? context.fetch(fetchRequest)) ?? []
        
        var balance = 0.0
        for transaction in transactions {
            if transaction.isExpense {
                balance -= transaction.amount
            } else {
                balance += transaction.amount
            }
        }
        return balance
    }
}

struct AccountSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @State private var showingAddAccount = false
    @State private var editingAccount: Account?
    @State private var showingDeleteAlert = false
    @State private var accountToDelete: Account?
    @State private var showError = false
    @State private var errorMessage = ""
    
    @FetchRequest(
        entity: Account.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)]
    ) private var accounts: FetchedResults<Account>
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Section
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Accounts")
                            .font(selectedFont.font(size: 28, bold: true))
                        Text("Manage all your financial accounts")
                            .font(selectedFont.font(size: 15))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    
                    Button {
                        showingAddAccount = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("Add")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                    }
                }
                .padding(.horizontal)
                
                // Current Account Section
                if let currentAccount = accountManager.currentAccount, 
                   let currentAccountInList = accounts.first(where: { $0.id == currentAccount.id }) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "creditcard.fill")
                                .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                            Text("Current Account")
                                .font(selectedFont.font(size: 16, bold: true))
                            Spacer()
                        }
                        
                        CurrentAccountCard(account: currentAccountInList)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .padding(.horizontal)
                }
                
                // All Accounts Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "list.bullet")
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                        Text("All Accounts")
                            .font(selectedFont.font(size: 16, bold: true))
                        Spacer()
                    }
                    
                    ForEach(accounts, id: \.objectID) { account in
                        AccountCardView(account: account,
                                      editingAccount: $editingAccount,
                                      accountToDelete: $accountToDelete,
                                      showingDeleteAlert: $showingDeleteAlert)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .padding(.horizontal)
                
                // Bottom spacing
                Color.clear.frame(height: 20)
            }
            .padding(.top)
        }
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showingAddAccount) {
            NavigationView {
                AddAccountView(showingAddAccount: $showingAddAccount)
                    .environmentObject(accountManager)
            }
        }
        .sheet(item: $editingAccount) { account in
            NavigationView {
                EditAccountView(account: account, editingAccount: $editingAccount)
                    .environmentObject(accountManager)
            }
        }
        .alert("Delete Account", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let account = accountToDelete {
                    deleteAccount(account)
                }
            }
        } message: {
            Text("Are you sure you want to delete this account? All associated transactions will be deleted. This action cannot be undone.")
        }
    }
    
    private func deleteAccount(_ account: Account) {
        withAnimation {
            if account.id == accountManager.currentAccount?.id {
                if let defaultAccount = accounts.first(where: { $0.isDefault }) {
                    accountManager.switchToAccount(defaultAccount)
                }
            }
            
            if let transactions = account.transactions {
                for case let transaction as Transaction in transactions {
                    if let contact = transaction.contact {
                        ContactManager.shared.decrementUsageCount(contact: contact, context: viewContext)
                    }
                    viewContext.delete(transaction)
                }
            }
            
            viewContext.delete(account)
            
            do {
                try viewContext.save()
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
        }
    }
}

// Updated Current Account Card
struct CurrentAccountCard: View {
    let account: Account
    @EnvironmentObject private var accountManager: AccountManager
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    themeManager.getAccentColor(for: colorScheme).opacity(0.35),
                                    themeManager.getAccentColor(for: colorScheme).opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "creditcard.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(account.name ?? "")
                        .font(selectedFont.font(size: 22, bold: true))
                    
                    HStack(spacing: 8) {
                        Text("Active")
                            .font(selectedFont.font(size: 14))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.18))
                            )
                            .foregroundColor(.green)
                        
                        if account.isDefault {
                            Text("Default")
                                .font(selectedFont.font(size: 14))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(themeManager.getAccentColor(for: colorScheme).opacity(0.20))
                                )
                                .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                        }
                    }
                }
                
                Spacer()
            }
            
            // Balance card
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Balance")
                        .font(selectedFont.font(size: 14))
                        .foregroundColor(.secondary)
                    
                    let balance = account.calculateBalance(context: viewContext)
                    Text("\(selectedCurrency.symbol) \(String(format: "%.2f", abs(balance)))")
                        .font(selectedFont.font(size: 26, bold: true))
                        .foregroundColor(balance >= 0 ? .green : .red)
                }
                
                Spacer()
                
                Image(systemName: balance >= 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                    .foregroundColor(balance >= 0 ? .green : .red)
                    .font(.system(size: 30))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }
    
    private var balance: Double {
        account.calculateBalance(context: viewContext)
    }
}

// Updated AccountCardView
struct AccountCardView: View {
    let account: Account
    @Binding var editingAccount: Account?
    @Binding var accountToDelete: Account?
    @Binding var showingDeleteAlert: Bool
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @Environment(\.colorScheme) private var colorScheme
    
    private var isCurrentAccount: Bool {
        account.id == accountManager.currentAccount?.id
    }
    
    var body: some View {
        VStack(spacing: 12) {
        HStack(spacing: 16) {
            let accentColor = themeManager.getAccentColor(for: colorScheme)
            let iconGradientColors: [Color] = isCurrentAccount
                ? [accentColor.opacity(0.30), accentColor.opacity(0.12)]
                : [Color.gray.opacity(0.20), Color.gray.opacity(0.06)]
            let iconShadowColor: Color = isCurrentAccount ? accentColor.opacity(0.18) : Color.black.opacity(0.10)
            let iconForegroundColor: Color = isCurrentAccount ? accentColor : .gray
            // Account icon with shadow
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: iconGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .shadow(color: iconShadowColor, radius: 4, x: 0, y: 2)
                
                Image(systemName: isCurrentAccount ? "creditcard.circle.fill" : "creditcard.circle")
                    .font(.system(size: 24))
                    .foregroundColor(iconForegroundColor)
            }
            
            // Account details
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name ?? "")
                        .font(selectedFont.font(size: 18, bold: true))
                
                HStack(spacing: 8) {
                    if account.isDefault {
                        Text("Default")
                            .font(selectedFont.font(size: 12))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(themeManager.getAccentColor(for: colorScheme).opacity(0.20))
                                )
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                    }
                    
                    if isCurrentAccount {
                        Text("Current")
                            .font(selectedFont.font(size: 12))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.green.opacity(0.18))
                                )
                            .foregroundColor(.green)
                        }
                    }
                }
                
                Spacer()
                
                // Balance display
                VStack(alignment: .trailing, spacing: 2) {
                    let balance = account.calculateBalance(context: viewContext)
                    let formattedBalance = String(format: "%.2f", abs(balance))
                    
                    Text("\(selectedCurrency.symbol) \(formattedBalance)")
                        .font(selectedFont.font(size: 18, bold: true))
                        .foregroundColor(balance >= 0 ? .green : .red)
                    
                    Text(balance >= 0 ? "Available" : "Overdrawn")
                        .font(selectedFont.font(size: 12))
                        .foregroundColor(balance >= 0 ? .green : .red)
                }
            }
            
            // Actions row
            HStack(spacing: 16) {
                if !isCurrentAccount {
                    Button {
                        accountManager.switchToAccount(account)
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 16))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                    }
                }
                
                Spacer()
                
                if !account.isDefault {
                    // Edit button
                    Button {
                        editingAccount = account
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 16))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .foregroundColor(.white)
                    }
                        
                    // Delete button
                    Button {
                        accountToDelete = account
                        showingDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.red.opacity(0.2))
                            )
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isCurrentAccount ? themeManager.getAccentColor(for: colorScheme).opacity(0.30) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .shadow(
            color: isCurrentAccount ? themeManager.getAccentColor(for: colorScheme).opacity(0.10) : Color.black.opacity(0.06),
            radius: 8,
            x: 0,
            y: 4
        )
    }
}

// Updated FeatureRow
struct FeatureRow: View {
    let icon: String
    let text: String
    let color: Color
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 18))
            }
            
            Text(text)
                .font(selectedFont.font(size: 16))
                .foregroundColor(.primary)
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
    }
}

// Keep existing AddAccountView and EditAccountView functionality
struct AddAccountView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var accountManager: AccountManager
    @Binding var showingAddAccount: Bool
    @State private var accountName = ""
    @State private var isDefault = false
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("New Account")
                        .font(selectedFont.font(size: 24, bold: true))
                    Text("Add a new financial account to track")
                        .font(selectedFont.font(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                
                // Account name field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Account Name")
                        .font(selectedFont.font(size: 15))
                        .foregroundColor(.secondary)
                    
                    TextField("Enter account name", text: $accountName)
                        .font(selectedFont.font(size: 17))
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                }
                
                // Default toggle
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $isDefault) {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill")
                                .foregroundColor(isDefault ? .yellow : .gray)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Set as Default Account")
                                    .font(selectedFont.font(size: 16))
                                
                                Text("This will be the default account for new transactions")
                                    .font(selectedFont.font(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                
                Spacer()
                
                // Buttons
                HStack(spacing: 16) {
                    Button {
                        showingAddAccount = false
                    } label: {
                        Text("Cancel")
                            .font(selectedFont.font(size: 16, bold: true))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(16)
                    }
                    
                    Button {
                        saveAccount()
                    } label: {
                        Text("Add Account")
                            .font(selectedFont.font(size: 16, bold: true))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(accountName.isEmpty ? Color.blue.opacity(0.3) : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .disabled(accountName.isEmpty)
                }
                .padding(.bottom)
            }
            .padding()
        }
        .navigationBarHidden(true)
    }
    
    private func saveAccount() {
        let account = Account(context: viewContext)
        account.id = UUID()
        account.name = accountName
        account.createdAt = Date()
        account.isDefault = isDefault
        
        if isDefault {
            // Update other accounts to not be default
            let fetchRequest = Account.fetchRequest()
            if let existingAccounts = try? viewContext.fetch(fetchRequest) {
                for existingAccount in existingAccounts {
                    existingAccount.isDefault = existingAccount.id == account.id
                }
            }
            accountManager.switchToAccount(account)
        }
        
        do {
            try viewContext.save()
            NotificationCenter.default.post(name: NSManagedObjectContext.didSaveObjectsNotification, object: nil)
        } catch {
            print("Error saving account: \(error)")
        }
        showingAddAccount = false
    }
}

struct EditAccountView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var accountManager: AccountManager
    let account: Account
    @Binding var editingAccount: Account?
    @State private var accountName: String
    @State private var isDefault: Bool
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    init(account: Account, editingAccount: Binding<Account?>) {
        self.account = account
        self._editingAccount = editingAccount
        self._accountName = State(initialValue: account.name ?? "")
        self._isDefault = State(initialValue: account.isDefault)
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Edit Account")
                        .font(selectedFont.font(size: 24, bold: true))
                    Text("Update your account details")
                        .font(selectedFont.font(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                
                // Account name field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Account Name")
                        .font(selectedFont.font(size: 15))
                        .foregroundColor(.secondary)
                    
                    TextField("Enter account name", text: $accountName)
                        .font(selectedFont.font(size: 17))
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                }
                
                // Default toggle
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $isDefault) {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill")
                                .foregroundColor(isDefault ? .yellow : .gray)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Set as Default Account")
                                    .font(selectedFont.font(size: 16))
                                
                                Text("This will be the default account for new transactions")
                                    .font(selectedFont.font(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                
                Spacer()
                
                // Buttons
                HStack(spacing: 16) {
                    Button {
                        editingAccount = nil
                    } label: {
                        Text("Cancel")
                            .font(selectedFont.font(size: 16, bold: true))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(16)
                    }
                    
                    Button {
                        saveChanges()
                    } label: {
                        Text("Save Changes")
                            .font(selectedFont.font(size: 16, bold: true))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(accountName.isEmpty ? Color.blue.opacity(0.3) : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .disabled(accountName.isEmpty)
                }
                .padding(.bottom)
            }
            .padding()
        }
        .navigationBarHidden(true)
    }
    
    private func saveChanges() {
        account.name = accountName
        
        if isDefault {
            // Update other accounts to not be default
            let fetchRequest = Account.fetchRequest()
            if let existingAccounts = try? viewContext.fetch(fetchRequest) {
                for existingAccount in existingAccounts {
                    existingAccount.isDefault = existingAccount.id == account.id
                }
            }
            accountManager.switchToAccount(account)
        } else {
            account.isDefault = false
        }
        
        do {
            try viewContext.save()
            // Force UI update
            NotificationCenter.default.post(name: NSManagedObjectContext.didSaveObjectsNotification, object: nil)
        } catch {
            print("Error saving account changes: \(error)")
        }
        editingAccount = nil
    }
} 
