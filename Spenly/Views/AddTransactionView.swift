import SwiftUI
import GoogleMobileAds
import UserNotifications
import CoreData

// Adding AdBannerView from AdViews module

struct AddTransactionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    @State private var amount = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var isExpense = true
    @State private var selectedCategory: Category?
    @State private var showingCategoryPicker = false
    @State private var showingDatePicker = false
    @State private var showingAmountKeyboard = false
    @State private var isDemo = false
    @State private var selectedReceiptImage: UIImage?
    @State private var showingReceiptPicker = false
    @State private var showingAccountPicker = false
    @State private var accountDragOffset: CGFloat = 0
    @State private var arrowBounce: Bool = false
    @State private var selectedContact: Contact?
    @State private var showingContactPicker = false
    // Budget checks
    @State private var showBudgetExceedAlert = false
    @State private var budgetAlertMessage = ""
    @State private var pendingProceedAfterAlert = false
    @State private var pendingTransactionData: (amount: Double, category: Category)?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Banner ad at the top of the transaction form (no space when premium)
                    if !IAPManager.shared.isAdsRemoved {
                        AdBannerView(adPosition: .top, adPlacement: .addTransaction)
                            .padding(.top, 8)
                            .padding(.bottom, 16)
                    }
                    
                    // Account Header (Centered, no background)
                    VStack(spacing: 6) {
                        Text(accountManager.currentAccount?.name ?? "Select Account")
                            .font(selectedFont.font(size: 18, bold: true))
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme).opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .blur(radius: accountDragOffset > 0 ? min(6, accountDragOffset / 12) : 0)
                            .animation(.easeInOut(duration: 0.12), value: accountDragOffset)
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                            .opacity(0.9)
                            .offset(y: min(accountDragOffset * 0.12, 10))
                            .animation(.easeInOut(duration: 0.12), value: accountDragOffset)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .contentShape(Rectangle())
                    .rotation3DEffect(
                        .degrees(min(10, Double(accountDragOffset / 8))),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.7
                    )
                    .onTapGesture {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        showingAccountPicker = true
                    }
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { value in
                                let dy = value.translation.height
                                accountDragOffset = dy > 0 ? dy : 0
                            }
                            .onEnded { _ in
                                if accountDragOffset > 32 {
                                    let impact = UIImpactFeedbackGenerator(style: .medium)
                                    impact.impactOccurred()
                                    showingAccountPicker = true
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    accountDragOffset = 0
                                }
                            }
                    )
                    .padding(.horizontal)
                    
                    TransactionTypeToggle(isExpense: $isExpense, selectedFont: selectedFont)
                        .padding(.horizontal)
                    
                    // Category Section - Moved to second position
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(selectedFont.font(size: 14))
                            .foregroundColor(.secondary)
                        
                        Button {
                            showingCategoryPicker = true
                        } label: {
                            HStack {
                                if let category = selectedCategory {
                                    Text(category.name ?? "")
                                        .font(selectedFont.font(size: 16))
                                        .foregroundColor(.primary)
                                } else {
                                    Text("Select Category")
                                        .font(selectedFont.font(size: 16))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Amount Section with enhanced styling
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Amount")
                            .font(selectedFont.font(size: 14))
                            .foregroundColor(.secondary)
                        let amountColor: Color = isExpense ? .red : .green
                        HStack(spacing: 16) {
                            Text(selectedCurrency.symbol)
                                .font(selectedFont.font(size: 24, bold: true))
                                .foregroundColor(.secondary)
                            
                            TextField("0.00", text: $amount)
                                .font(selectedFont.font(size: 34, bold: true))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.leading)
                                .foregroundColor(amountColor)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, 20)
                        .padding(.horizontal, 24)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemGray5))
                                .shadow(
                                    color: Color.black.opacity(0.1),
                                    radius: 8,
                                    x: 0,
                                    y: 4
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color(.systemGray4), lineWidth: 0.5)
                        )
                    }
                    .padding(.horizontal)
                    
                    // Note Field with enhanced styling
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note")
                            .font(selectedFont.font(size: 14))
                            .foregroundColor(.secondary)
                        
                        TextField("Add a note", text: $note)
                            .font(selectedFont.font(size: 16))
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(16)
                    }
                    .padding(.horizontal)
                    
                    // Payee/Payer Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isExpense ? "Payee" : "Payer")
                            .font(selectedFont.font(size: 14))
                            .foregroundColor(.secondary)
                        
                        Button {
                            showingContactPicker = true
                        } label: {
                            HStack {
                                if let contact = selectedContact {
                                    Text(contact.safeName)
                                        .font(selectedFont.font(size: 16))
                                        .foregroundColor(.primary)
                                } else {
                                    Text(isExpense ? "Who did you pay?" : "Who paid you?")
                                        .font(selectedFont.font(size: 16))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedContact != nil {
                                    Button {
                                        let impact = UIImpactFeedbackGenerator(style: .light)
                                        impact.impactOccurred()
                                        selectedContact = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Image(systemName: "chevron.right")
                                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal)
                    
                    ReceiptSection(
                        selectedReceiptImage: $selectedReceiptImage,
                        showingReceiptPicker: $showingReceiptPicker,
                        selectedFont: selectedFont,
                        accentColor: themeManager.getAccentColor(for: colorScheme)
                    )
                    .padding(.horizontal)
                    
                    // Date Picker with enhanced styling
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Date")
                            .font(selectedFont.font(size: 14))
                            .foregroundColor(.secondary)
                        
                        DatePicker("", selection: $date, displayedComponents: [.date])
                            .datePickerStyle(.graphical)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(16)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        attemptSaveTransaction()
                    }
                    .font(selectedFont.font(size: 16, bold: true))
                    .foregroundColor(isValid ? themeManager.getAccentColor(for: colorScheme) : .gray)
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                CategoryPickerView(
                    selectedCategory: $selectedCategory,
                    type: isExpense ? "expense" : "income"
                )
            }
            .sheet(isPresented: $showingReceiptPicker) {
                ReceiptPickerView(
                    selectedImage: $selectedReceiptImage,
                    isPresented: $showingReceiptPicker
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingAccountPicker) {
                ElegantAccountPickerSheet()
                    .environmentObject(accountManager)
                    .environmentObject(themeManager)
            }
            .sheet(isPresented: $showingContactPicker) {
                ContactPickerView(
                    selectedContact: $selectedContact,
                    isPresented: $showingContactPicker
                )
                .environmentObject(themeManager)
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
        .alert("Confirm Budget Exceed?", isPresented: $showBudgetExceedAlert) {
            Button("Cancel", role: .cancel) { 
                pendingProceedAfterAlert = false
                pendingTransactionData = nil
            }
            Button("Proceed") { 
                pendingProceedAfterAlert = true
                if pendingTransactionData != nil {
                    saveTransactionCore()
                }
                pendingTransactionData = nil
            }
        } message: {
            Text(budgetAlertMessage)
        }
        .onDisappear {
            // Clear pending data if view disappears
            pendingTransactionData = nil
        }
    }
    
    private func attemptSaveTransaction() {
        guard let amountDouble = Double(amount),
              let category = selectedCategory else { 
            // Show error alert instead of print statement
            showErrorAlert(title: "Missing Information", 
                           message: "Please enter a valid amount and select a category.")
            return 
        }
        if isExpense, shouldWarnForBudgetExceed(amount: amountDouble, category: category) {
            // Store pending transaction data
            pendingTransactionData = (amount: amountDouble, category: category)
            // Alert will handle flow; do not proceed yet
            return
        }
        saveTransactionCore()
    }

    private func saveTransactionCore() {
        guard let amountDouble = Double(amount),
              let category = selectedCategory else { return }
              
        // Ensure we have a valid account - this is critical
        guard let currentAccount = accountManager.currentAccount,
              currentAccount.managedObjectContext != nil else {
            
            // Try to fix the account
            DispatchQueue.main.async {
                accountManager.ensureAccountInitialized(context: viewContext)
            }
            
            // Show an error to the user
            showErrorAlert(title: "Account Error", 
                           message: "There was a problem accessing your account. Please try again or restart the app.")
            return
        }
        
        // All checks passed, create the transaction
        let transaction = Transaction(context: viewContext)
        let transactionID = UUID()
        transaction.id = transactionID
        transaction.amount = amountDouble
        transaction.note = note
        transaction.date = date
        transaction.isExpense = isExpense
        transaction.category = category
        transaction.account = currentAccount
        
        // Set contact if selected
        if let contact = selectedContact {
            transaction.contact = contact
            ContactManager.shared.incrementUsageCount(contact: contact, context: viewContext)
        }
        
        // Initialize additional required boolean properties with default values
        transaction.isCarryOver = false
        transaction.isDemo = false
        
        // Handle receipt image if attached (with CloudKit sync)
        if let receiptImage = selectedReceiptImage {
            if !ReceiptManager.shared.saveReceiptImageData(receiptImage, to: transaction) {
                print("⚠️ Failed to save receipt image, but continuing with transaction")
            }
        }
        
        // If isPaused property exists in the model, set it to false
        // This avoids the "value defined but never used" warning
        if transaction.entity.propertiesByName["isPaused"] != nil {
            transaction.setValue(false, forKey: "isPaused")
        }
        
        do {
            try viewContext.save()
            if isExpense { postSaveBudgetNotifications(addedAmount: amountDouble, category: category) }
            dismiss()
        } catch {
            // If save fails, reset context and notify the user
            viewContext.rollback()
            
            showErrorAlert(title: "Save Failed", 
                           message: "Unable to save your transaction. Please try again.")
        }
    }
    
    private func showErrorAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        // Find the current view controller to present the alert
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            var currentController = rootViewController
            while let presentedController = currentController.presentedViewController {
                currentController = presentedController
            }
            currentController.present(alert, animated: true)
        }
    }
    
    private var isValid: Bool {
        !amount.isEmpty && selectedCategory != nil
    }
    
    private func getCategoryIcon(for category: Category) -> String {
        guard let name = category.name?.lowercased() else {
            return category.type == "income" ? "dollarsign.circle.fill" : "cart.fill"
        }
        
        if category.type == "income" {
            if name.contains("salary") { return "briefcase.fill" }
            if name.contains("investment") { return "chart.line.uptrend.xyaxis.circle.fill" }
            if name.contains("gift") { return "gift.fill" }
            if name.contains("rental") { return "house.fill" }
            if name.contains("business") { return "building.2.fill" }
            return "dollarsign.circle.fill"
        } else {
            switch true {
            case name.contains("food"): return "fork.knife.circle.fill"
            case name.contains("transport"): return "car.fill"
            case name.contains("shopping"): return "bag.fill"
            case name.contains("health"): return "cross.case.fill"
            case name.contains("bill"): return "doc.text.fill"
            case name.contains("entertainment"): return "tv.fill"
            case name.contains("education"): return "book.fill"
            case name.contains("home"): return "house.fill"
            case name.contains("insurance"): return "checkmark.shield.fill"
            case name.contains("pet"): return "pawprint.fill"
            case name.contains("fitness"): return "figure.run.circle.fill"
            case name.contains("tech"): return "desktopcomputer"
            default: return "cart.fill"
            }
        }
    }
    
    // MARK: - Budget Logic
    // MARK: - Period helpers (mirror of BudgetView logic)
    private enum BudgetPeriodLocal: String { case monthly }

    private func accountActivePeriod(_ account: Account) -> BudgetPeriodLocal {
        let key = "budget_period_\((account.id ?? UUID()).uuidString)"
        let raw = UserDefaults.standard.string(forKey: key) ?? BudgetPeriodLocal.monthly.rawValue
        return BudgetPeriodLocal(rawValue: raw) ?? .monthly
    }

    private func periodStartKey(_ account: Account, _ p: BudgetPeriodLocal) -> String { "budget_period_start_\((account.id ?? UUID()).uuidString)_\(p.rawValue)" }
    private func periodEndKey(_ account: Account, _ p: BudgetPeriodLocal) -> String { "budget_period_end_\((account.id ?? UUID()).uuidString)_\(p.rawValue)" }

    private func defaultStart(for p: BudgetPeriodLocal) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    private func autoAdjustedEnd(from start: Date, period: BudgetPeriodLocal) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
    }

    private func activePeriodRange(_ account: Account) -> (Date, Date) {
        let p = accountActivePeriod(account)
        if let s = UserDefaults.standard.object(forKey: periodStartKey(account, p)) as? Date,
           let e = UserDefaults.standard.object(forKey: periodEndKey(account, p)) as? Date { return (s, e) }
        let s = defaultStart(for: p); let e = autoAdjustedEnd(from: s, period: p); return (s, e)
    }

    private func periodExpenseTotal(for account: Account) -> Double {
        let (start, end) = activePeriodRange(account)
        let req: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        req.predicate = NSPredicate(format: "account == %@ AND isExpense == YES AND isCarryOver == NO AND date >= %@ AND date <= %@", account, start as NSDate, end as NSDate)
        let list = (try? viewContext.fetch(req)) ?? []
        return list.reduce(0) { $0 + $1.amount }
    }

    private func monthExpenseTotal(for account: Account, category: Category) -> Double {
        let (start, end) = activePeriodRange(account)
        let req: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        req.predicate = NSPredicate(format: "account == %@ AND isExpense == YES AND isCarryOver == NO AND category == %@ AND date >= %@ AND date <= %@", account, category, start as NSDate, end as NSDate)
        let list = (try? viewContext.fetch(req)) ?? []
        return list.reduce(0) { $0 + $1.amount }
    }

    private func accountBudgetLimit(_ account: Account) -> Double {
        let id = account.id ?? UUID()
        return UserDefaults.standard.double(forKey: "budget_limit_\(id.uuidString)")
    }

    private func categoryBudgetLimit(_ account: Account, _ category: Category) -> Double {
        let id = account.id ?? UUID()
        let name = category.name ?? ""
        let key = "budget_limit_cat_\(id.uuidString)_\(name)"
        return UserDefaults.standard.double(forKey: key)
    }

    private func monthKey() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMM"; return f.string(from: Date())
    }
    private func weekKey() -> String { monthKey() }

    private func shouldWarnForBudgetExceed(amount: Double, category: Category) -> Bool {
        guard let account = accountManager.currentAccount else { return false }
        var warnings: [String] = []
        // Overall budget for active period
        let oLimit = accountBudgetLimit(account)
        if oLimit > 0 {
            let oSpent = periodExpenseTotal(for: account)
            if oSpent + amount > oLimit {
                warnings.append("monthly budget")
            }
        }
        // Category budget
        let cLimit = categoryBudgetLimit(account, category)
        if cLimit > 0 {
            let cSpent = monthExpenseTotal(for: account, category: category)
            if cSpent + amount > cLimit {
                warnings.append("\(category.name ?? "category") budget")
            }
        }
        if !warnings.isEmpty {
            budgetAlertMessage = "This will exceed your \(warnings.joined(separator: " and ")). Do you want to proceed?"
            showBudgetExceedAlert = true
            return true
        }
        return false
    }

    private func postSaveBudgetNotifications(addedAmount: Double, category: Category) {
        guard let account = accountManager.currentAccount else { return }
        let id = account.id ?? UUID()
        let periodKey = monthKey()
        let thresholds: [Int] = [100, 80, 50]

        // Category thresholds
        let cLimit = categoryBudgetLimit(account, category)
        if cLimit > 0 {
            let newTotal = monthExpenseTotal(for: account, category: category)
            let pct = Int(min(100, (newTotal / cLimit * 100)).rounded())
            if let t = thresholds.first(where: { pct >= $0 && !UserDefaults.standard.bool(forKey: "budget_cat_notified_\(id.uuidString)_\(periodKey)_\(category.name ?? "")_\($0)") }) {
                let flag = "budget_cat_notified_\(id.uuidString)_\(periodKey)_\(category.name ?? "")_\(t)"
                scheduleLocalNotification(title: "\(category.name ?? "Category") budget", body: t == 100 ? "You've fully used the budget for \(category.name ?? "Category")." : "You've reached \(t)% of \(category.name ?? "Category") budget.")
                UserDefaults.standard.set(true, forKey: flag)
            }
        }
        // Overall thresholds (optional, keep consistent with app behavior)
        let oLimit = accountBudgetLimit(account)
        if oLimit > 0 {
            let newTotal = periodExpenseTotal(for: account)
            let pct = Int(min(100, (newTotal / oLimit * 100)).rounded())
            if let t = thresholds.first(where: { pct >= $0 && !UserDefaults.standard.bool(forKey: "budget_notified_\(id.uuidString)_\(periodKey)_\($0)") }) {
                let flag = "budget_notified_\(id.uuidString)_\(periodKey)_\(t)"
                scheduleLocalNotification(title: "Budget Update", body: t == 100 ? "You've fully used this month's budget." : "You've reached \(t)% of this month's budget.")
                UserDefaults.standard.set(true, forKey: flag)
            }
        }
    }

    private func scheduleLocalNotification(title: String, body: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                // Defer notification permission until after login (handled by AuthManager)
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }
}

struct CategoryPickerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCategory: Category?
    let type: String
    
    @FetchRequest private var categories: FetchedResults<Category>
    @State private var uniqueCategories: [Category] = []
    
    init(selectedCategory: Binding<Category?>, type: String) {
        self._selectedCategory = selectedCategory
        self.type = type
        
        _categories = FetchRequest<Category>(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \Category.isCustom, ascending: true),
                NSSortDescriptor(keyPath: \Category.name, ascending: true)
            ],
            predicate: NSPredicate(format: "type == %@", type),
            animation: .default
        )
    }
    
    var body: some View {
        NavigationView {
            List {
                                        ForEach(uniqueCategories, id: \.objectID) { category in
                    Button {
                        selectedCategory = category
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: category.icon ?? "tag.fill")
                                .foregroundColor(type == "income" ? .green : .blue)
                                .frame(width: 24)
                            Text(category.name ?? "")
                                .foregroundColor(.primary)
                            Spacer()
                            if category.id == selectedCategory?.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Filter categories to ensure no duplicates are displayed
                filterCategories()
            }
        }
    }
    
    private func filterCategories() {
        // Create a dictionary to store unique categories by normalized name
        var uniqueCategoryDict: [String: Category] = [:]
        
        // Process all categories fetched from CoreData
        for category in categories {
            guard let name = category.name?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
            
            // Normalize the name to handle variations
            let normalizedName = name
                .replacingOccurrences(of: "&", with: "and")
                .replacingOccurrences(of: " ", with: "")
            
            // If this category name doesn't exist yet, add it
            if uniqueCategoryDict[normalizedName] == nil {
                uniqueCategoryDict[normalizedName] = category
            } else {
                // If it exists, prefer system categories over custom ones
                let existingIsCustom = uniqueCategoryDict[normalizedName]?.isCustom ?? true
                let newIsCustom = category.isCustom
                
                if !newIsCustom && existingIsCustom {
                    // Replace with system category
                    uniqueCategoryDict[normalizedName] = category
                }
            }
        }
        
        // Convert the dictionary values to an array and sort
        uniqueCategories = uniqueCategoryDict.values.sorted { 
            // First by custom/system
            if ($0.isCustom != $1.isCustom) {
                return !$0.isCustom
            }
            // Then by name
            return ($0.name ?? "") < ($1.name ?? "")
        }
    }
} 

private struct TransactionTypeToggle: View {
    @Binding var isExpense: Bool
    let selectedFont: AppFont

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type")
                .font(selectedFont.font(size: 14))
                .foregroundColor(.secondary)

            HStack(spacing: 0) {
                ToggleButton(title: "Expense", systemImage: "arrow.up.circle.fill", isSelected: isExpense, selectedFont: selectedFont, selectedColor: .red) {
                    withAnimation(.spring()) { isExpense = true }
                }
                ToggleButton(title: "Income", systemImage: "arrow.down.circle.fill", isSelected: !isExpense, selectedFont: selectedFont, selectedColor: .green) {
                    withAnimation(.spring()) { isExpense = false }
                }
            }
            .padding(4)
            .background(Color(.systemGray5))
            .cornerRadius(16)
        }
    }

    private struct ToggleButton: View {
        let title: String
        let systemImage: String
        let isSelected: Bool
        let selectedFont: AppFont
        let selectedColor: Color
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack {
                    Image(systemName: systemImage)
                    Text(title)
                }
                .font(selectedFont.font(size: 16))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? selectedColor : Color(.systemGray6))
                )
            }
        }
    }
}

// MARK: - Account Picker
private struct AccountPickerSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountManager: AccountManager
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)]
    ) private var accounts: FetchedResults<Account>
    
    var body: some View {
        NavigationView {
            List {
                ForEach(accounts, id: \.objectID) { account in
                    Button {
                        accountManager.switchToAccount(account)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: account == accountManager.currentAccount ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(account == accountManager.currentAccount ? .green : .secondary)
                            Text(account.name ?? "Account")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Select Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// A more elegant account picker presentation
private struct ElegantAccountPickerSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)]
    ) private var accounts: FetchedResults<Account>
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(accounts, id: \.objectID) { account in
                        Button {
                            accountManager.switchToAccount(account)
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(Color(.systemGray6))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "wallet.pass")
                                        .foregroundColor(.accentColor)
                                }
                                Text(account.name ?? "Account")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer()
                                if account == accountManager.currentAccount {
                                    ZStack {
                                        Circle()
                                            .fill(themeManager.getAccentColor(for: colorScheme))
                                            .frame(width: 24, height: 24)
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.white)
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [
                                        themeManager.getAccentColor(for: colorScheme).opacity(0.12),
                                        themeManager.getAccentColor(for: colorScheme).opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .background(.ultraThinMaterial)
                            )
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Choose Account")
            .navigationBarTitleDisplayMode(.inline)
            
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ReceiptSection: View {
    @Binding var selectedReceiptImage: UIImage?
    @Binding var showingReceiptPicker: Bool
    let selectedFont: AppFont
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Receipt")
                .font(selectedFont.font(size: 14))
                .foregroundColor(.secondary)

            if let receiptImage = selectedReceiptImage {
                VStack(spacing: 16) {
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 16))
                            Text("Receipt attached")
                                .font(selectedFont.font(size: 16))
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedReceiptImage = nil
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                Text("Remove")
                                    .font(selectedFont.font(size: 14))
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)

                    VStack(spacing: 12) {
                        Image(uiImage: receiptImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 280, height: 140)
                            .clipped()
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 2)
                            )
                            .shadow(color: Color.green.opacity(0.2), radius: 8, x: 0, y: 4)

                        HStack {
                            Image(systemName: "doc.text.image")
                                .foregroundColor(.green)
                                .font(.system(size: 14))
                            Text("Receipt ready for saving")
                                .font(selectedFont.font(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
            } else {
                Button {
                    showingReceiptPicker = true
                } label: {
                    HStack {
                        Image(systemName: "paperclip")
                            .foregroundColor(.blue)
                        Text("Attach Receipt")
                            .font(selectedFont.font(size: 16))
                            .foregroundColor(.blue)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(accentColor)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
            }
        }
    }
}
