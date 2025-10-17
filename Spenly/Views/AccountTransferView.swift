import SwiftUI
import CoreData

struct AccountTransferView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    
    @FetchRequest(
        entity: Account.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)]
    ) private var accounts: FetchedResults<Account>
    
    @State private var fromAccountID: UUID?
    @State private var toAccountID: UUID?
    @State private var amount: String = ""
    @State private var note: String = ""
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isTransferring = false
    @State private var showFromAccountList = false
    @State private var showToAccountList = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Transfer Details")) {
                    // From Account Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("From Account")
                            .font(.headline)
                        
                        if showFromAccountList {
                            VStack(spacing: 0) {
                                ForEach(availableFromAccounts, id: \.id) { account in
                                    Button {
                                        print("🔄 Selected from account: \(account.name ?? "Unknown") with ID: \(account.id?.uuidString ?? "nil")")
                                        fromAccountID = account.id
                                        showFromAccountList = false
                                    } label: {
                                        HStack {
                                            Text(account.name ?? "Unknown")
                                                .foregroundColor(.primary)
                                            Spacer()
                                            Text("\(selectedCurrency.symbol)\(String(format: "%.2f", account.calculateBalance(context: viewContext)))")
                                                .foregroundColor(.secondary)
                                                .font(.caption)
                                        }
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 16)
                                        .background(fromAccountID == account.id ? themeManager.getAccentColor(for: colorScheme).opacity(0.12) : Color(.systemBackground))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    if account.id != availableFromAccounts.last?.id {
                                        Divider()
                                    }
                                }
                            }
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(themeManager.getAccentColor(for: colorScheme).opacity(0.25), lineWidth: 1)
                            )
                        } else {
                            Button {
                                print("🔽 Toggling from account list. Current: \(showFromAccountList), Available accounts: \(availableFromAccounts.count)")
                                for account in availableFromAccounts {
                                    print("   - \(account.name ?? "Unknown") (Balance: \(account.calculateBalance(context: viewContext)))")
                                }
                                showToAccountList = false
                                showFromAccountList.toggle()
                            } label: {
                                HStack {
                                    Text(selectedFromAccount?.name ?? "Select Account")
                                        .foregroundColor(selectedFromAccount != nil ? .primary : .secondary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                                        .font(.caption)
                                        .rotationEffect(.degrees(showFromAccountList ? 180 : 0))
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    // To Account Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To Account")
                            .font(.headline)
                        
                        if showToAccountList {
                            VStack(spacing: 0) {
                                ForEach(availableToAccounts, id: \.id) { account in
                                    Button {
                                        toAccountID = account.id
                                        showToAccountList = false
                                    } label: {
                                        HStack {
                                            Text(account.name ?? "Unknown")
                                                .foregroundColor(.primary)
                                            Spacer()
                                        }
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 16)
                                        .background(toAccountID == account.id ? themeManager.getAccentColor(for: colorScheme).opacity(0.12) : Color(.systemBackground))
                                    }
                                    
                                    if account.id != availableToAccounts.last?.id {
                                        Divider()
                                    }
                                }
                            }
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(themeManager.getAccentColor(for: colorScheme).opacity(0.25), lineWidth: 1)
                            )
                        } else {
                            Button {
                                showFromAccountList = false
                                showToAccountList.toggle()
                            } label: {
                                HStack {
                                    Text(selectedToAccount?.name ?? "Select Account")
                                        .foregroundColor(selectedToAccount != nil ? .primary : .secondary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                                        .font(.caption)
                                        .rotationEffect(.degrees(showToAccountList ? 180 : 0))
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    // Amount Field
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    // Note Field
                    TextField("Note (Optional)", text: $note)
                }
                
                // Balance Information
                if let fromAccount = selectedFromAccount {
                    Section(header: Text("Account Balance")) {
                        HStack {
                            Text(fromAccount.name ?? "Unknown")
                            Spacer()
                            Text("\(selectedCurrency.symbol)\(String(format: "%.2f", fromAccount.calculateBalance(context: viewContext)))")
                                .foregroundColor(fromAccount.calculateBalance(context: viewContext) >= 0 ? .green : .red)
                        }
                        
                        // Show validation message if there's an issue
                        if let validationMessage = transferValidationMessage {
                            Text(validationMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                // Transfer Button
                Section {
                    Button(action: performTransfer) {
                        HStack {
                            if isTransferring {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isTransferring ? "Transferring..." : "Transfer Money")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                    }
                    .disabled(!canTransfer || isTransferring)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(canTransfer && !isTransferring ? themeManager.getAccentColor(for: colorScheme) : Color.gray)
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .overlay(alignment: .top) {
                LinearGradient(
                    gradient: Gradient(colors: [
                        themeManager.getAccentColor(for: colorScheme).opacity(0.16),
                        themeManager.getAccentColor(for: colorScheme).opacity(0.06),
                        .clear
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 210)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }
            .navigationTitle("Account Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("OK") {
                    if alertTitle == "Transfer Successful" {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var selectedFromAccount: Account? {
        guard let fromAccountID = fromAccountID else { 
            print("🔍 No fromAccountID selected")
            return nil 
        }
        let account = accounts.first { $0.id == fromAccountID }
        print("🔍 Looking for account with ID: \(fromAccountID.uuidString), found: \(account?.name ?? "nil")")
        return account
    }
    
    private var selectedToAccount: Account? {
        guard let toAccountID = toAccountID else { return nil }
        return accounts.first { $0.id == toAccountID }
    }
    
    private var availableFromAccounts: [Account] {
        Array(accounts)
    }
    
    private var availableToAccounts: [Account] {
        accounts.filter { account in
            account.id != fromAccountID
        }
    }
    
    private var canTransfer: Bool {
        guard let fromAccount = selectedFromAccount,
              let toAccount = selectedToAccount,
              let transferAmount = Double(amount),
              transferAmount > 0 else {
            return false
        }
        
        let fromBalance = fromAccount.calculateBalance(context: viewContext)
        return fromBalance >= transferAmount && fromAccount.id != toAccount.id
    }
    
    private var transferValidationMessage: String? {
        guard let fromAccount = selectedFromAccount,
              let transferAmount = Double(amount),
              transferAmount > 0 else {
            return nil
        }
        
        let fromBalance = fromAccount.calculateBalance(context: viewContext)
        if fromBalance < transferAmount {
            return "Insufficient balance for this transfer"
        }
        return nil
    }
    
    // MARK: - Transfer Logic
    
    private func performTransfer() {
        guard let fromAccount = selectedFromAccount,
              let toAccount = selectedToAccount,
              let transferAmount = Double(amount),
              transferAmount > 0 else {
            showAlert(title: "Invalid Input", message: "Please check your transfer details and try again.")
            return
        }
        
        let fromBalance = fromAccount.calculateBalance(context: viewContext)
        guard fromBalance >= transferAmount else {
            showAlert(title: "Insufficient Balance", message: "The selected account doesn't have enough balance for this transfer.")
            return
        }
        
        isTransferring = true
        
        // Perform transfer on background context for better performance
        let backgroundContext = viewContext
        backgroundContext.perform {
            do {
                // Create Account Transfer category if it doesn't exist
                let transferCategory = findOrCreateAccountTransferCategory(context: backgroundContext)
                
                // Create outgoing transaction (expense from source account)
                let outgoingTransaction = Transaction(context: backgroundContext)
                outgoingTransaction.id = UUID()
                outgoingTransaction.amount = transferAmount
                outgoingTransaction.date = Date()
                outgoingTransaction.note = note.isEmpty ? "Transfer to \(toAccount.name ?? "Unknown Account")" : note
                outgoingTransaction.isExpense = true
                outgoingTransaction.isCarryOver = false
                outgoingTransaction.isDemo = false
                outgoingTransaction.account = fromAccount
                outgoingTransaction.category = transferCategory
                
                // Create incoming transaction (income to destination account)
                let incomingTransaction = Transaction(context: backgroundContext)
                incomingTransaction.id = UUID()
                incomingTransaction.amount = transferAmount
                incomingTransaction.date = Date()
                incomingTransaction.note = note.isEmpty ? "Transfer from \(fromAccount.name ?? "Unknown Account")" : note
                incomingTransaction.isExpense = false
                incomingTransaction.isCarryOver = false
                incomingTransaction.isDemo = false
                incomingTransaction.account = toAccount
                incomingTransaction.category = transferCategory
                
                // Save changes
                try backgroundContext.save()
                
                DispatchQueue.main.async {
                    self.isTransferring = false
                    self.showAlert(
                        title: "Transfer Successful",
                        message: "Successfully transferred \(self.selectedCurrency.symbol)\(String(format: "%.2f", transferAmount)) from \(fromAccount.name ?? "Unknown") to \(toAccount.name ?? "Unknown")."
                    )
                    
                    // Post notification for UI updates
                    NotificationCenter.default.post(
                        name: NSNotification.Name("TransactionsUpdated"),
                        object: nil
                    )
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.isTransferring = false
                    self.showAlert(
                        title: "Transfer Failed",
                        message: "An error occurred while processing the transfer. Please try again."
                    )
                }
                print("❌ Account transfer error: \(error.localizedDescription)")
            }
        }
    }

    private func findOrCreateAccountTransferCategory(context: NSManagedObjectContext) -> Category {
        // Try to find existing Account Transfer category
        let fetchRequest: NSFetchRequest<Category> = Category.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name == %@", "Account Transfer")
        
        if let existingCategory = try? context.fetch(fetchRequest).first {
            return existingCategory
        }
        
        // Create new Account Transfer category
        let newCategory = Category(context: context)
        newCategory.id = UUID()
        newCategory.name = "Account Transfer"
        newCategory.icon = "arrow.left.arrow.right"
        newCategory.type = "expense" // Set as expense type (standard for transfers)
        newCategory.isCustom = false
        
        return newCategory
    }
    
    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}


#Preview {
    AccountTransferView()
        .environmentObject(AccountManager.shared)
        .environmentObject(ThemeManager())
} 