import SwiftUI
import CoreData
import GoogleMobileAds
#if canImport(UIKit)
import UIKit
#endif

// Adding AdBannerView from AdViews module

enum TimePeriod: String, CaseIterable, Identifiable {
    case day = "Day"
    case month = "Month"
    case year = "Year"
    
    var id: String { rawValue }
    
    func currentPeriodString(for date: Date) -> String {
        let formatter = DateFormatter()
        
        switch self {
        case .day:
            formatter.dateFormat = "EEEE, MMM d, yyyy"
            return formatter.string(from: date)
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        case .year:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: date)
        }
    }
}

extension Calendar {
    func date(byAddingDays days: Int) -> Date? {
        self.date(byAdding: .day, value: days, to: Date())
    }
}

struct RecentTransactionCard: View {
    let transaction: Transaction
    var onEdit: ((Transaction) -> Void)? = nil
    var onDelete: ((Transaction) -> Void)? = nil
    var onViewReceipt: ((Transaction) -> Void)? = nil
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @Environment(\.managedObjectContext) private var viewContext
    
    private var transactionColor: Color {
        transaction.isExpense ? .red : .green
    }
    
    private var categoryIcon: String {
        // Use category name to determine icon
        guard let categoryName = transaction.category?.name?.lowercased() else {
            return transaction.isExpense ? "cart.fill" : "dollarsign.circle.fill"
        }
        
        // Income icons
        if !transaction.isExpense {
            if categoryName.contains("salary") || categoryName.contains("wage") {
                return "briefcase.fill"
            } else if categoryName.contains("investment") {
                return "chart.line.uptrend.xyaxis.circle.fill"
            } else if categoryName.contains("gift") {
                return "gift.fill"
            } else if categoryName.contains("rental") {
                return "house.fill"
            } else if categoryName.contains("business") {
                return "building.2.fill"
            }
            return "dollarsign.circle.fill"
        }
        // Expense icons
        else {
            switch true {
            case categoryName.contains("food") || categoryName.contains("grocery"):
                return "fork.knife.circle.fill"
            case categoryName.contains("transport"):
                return "car.fill"
            case categoryName.contains("shopping"):
                return "bag.fill"
            case categoryName.contains("health"):
                return "cross.case.fill"
            case categoryName.contains("bill"):
                return "doc.text.fill"
            case categoryName.contains("entertainment"):
                return "tv.fill"
            case categoryName.contains("education"):
                return "book.fill"
            case categoryName.contains("home"):
                return "house.fill"
            case categoryName.contains("insurance"):
                return "checkmark.shield.fill"
            case categoryName.contains("pet"):
                return "pawprint.fill"
            case categoryName.contains("fitness"):
                return "figure.run.circle.fill"
            case categoryName.contains("tech"):
                return "desktopcomputer"
            default:
                return "cart.fill"
            }
        }
    }
    
    private var backgroundGradient: LinearGradient {
        if transaction.isExpense {
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color.black,
                    Color.black.opacity(0.9),
                    Color.red.opacity(0.2)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color.black,
                    Color.black.opacity(0.9),
                    Color.green.opacity(0.2)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Add carry-over indicator if this is a carry-over transaction
                if transaction.isCarryOver {
                    Text("Balance")
                        .font(selectedFont.font(size: 10))
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                // Add category icon
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: transaction.category?.icon ?? (transaction.isExpense ? "cart.fill" : "dollarsign.circle.fill"))
                        .foregroundColor(transaction.isExpense ? .red : .green)
                        .font(.system(size: 16))
                }
            }
            
                    VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(transaction.category?.name ?? "Uncategorized")
                    .font(selectedFont.font(size: 15))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                // Receipt icon beside category name
                if transaction.receiptFileName != nil {
                    Image(systemName: "paperclip")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
                
                Spacer()
            }
            
            Text(transaction.note ?? "")
                .font(selectedFont.font(size: 13))
                .foregroundColor(.gray)
                .lineLimit(1)
            
            // Contact info (Payee/Payer) if available
            if let contact = transaction.contact {
                Text("\(transaction.isExpense ? "Payee" : "Payer"): \(contact.name ?? "Contact")")
                    .font(selectedFont.font(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
            
            Text(CurrencyFormatter.format(transaction.amount, currency: selectedCurrency))
                .font(selectedFont.font(size: 16))
                .fontWeight(.semibold)
                .foregroundColor(transactionColor)
        }
        .padding()
        .frame(width: 160)
        .background(backgroundGradient)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .contextMenu {
            if transaction.receiptFileName != nil {
                Button { onViewReceipt?(transaction) } label: { Label("View Receipt", systemImage: "paperclip") }
                Divider()
            }
            Button { onEdit?(transaction) } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { onDelete?(transaction) } label: { Label("Delete", systemImage: "trash") }
        }
    }
    
}

struct HomeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var themeManager: ThemeManager
    @StateObject private var iapManager = IAPManager.shared
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @State private var isPresentingModal = false

    @State private var selectedPeriod: TimePeriod = .month
    @State private var currentDate = Date()
    @State private var selectedDate = Date() // Adding the missing selectedDate property
    @State private var isRefreshing = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var refreshID = UUID()
    
    @State private var showingSavingsDetails = false
    @State private var showingHelpSheet = false
    // Templates now use direct UIKit presentation
    @AppStorage("showCalculator") private var showCalculator = true
    @AppStorage("showCurrencyRates") private var showCurrencyRates = true
    @State private var showingCalculator = false
    @GestureState private var isDragging = false
    
    // Add state variables for day expenses popup
    @State private var showingDayExpensesPopup = false
    @State private var selectedDayExpenses: [Transaction] = []
    @State private var selectedDayDate: Date?
    
    // Add state variables for income/expense transaction popup
    @State private var showingTransactionPopup = false
    @State private var popupIsExpense = false
    
    // Store the current quote that refreshes when the app is reopened
    @State private var currentQuote: String = ""
    
    // Collection of financial quotes
    private let financialQuotes = [
        // Personal Finance Quotes
        "The best investment you can make is in yourself.",
        "A penny saved is a penny earned.",
        "Don't save what is left after spending, but spend what is left after saving.",
        "Money is a terrible master but an excellent servant.",
        "The habit of saving is itself an education; it fosters every virtue, teaches self-denial, cultivates the sense of order, trains to forethought.",
        "Financial peace isn't the acquisition of stuff. It's learning to live on less than you make.",
        "A budget is telling your money where to go instead of wondering where it went.",
        "Never spend your money before you have earned it.",
        "It's not about how much money you make, but how much money you keep.",
        "The art is not in making money, but in keeping it.",
        
        // Wealth Building Quotes
        "Money is only a tool. It will take you wherever you wish, but it will not replace you as the driver.",
        "The quickest way to double your money is to fold it in half and put it in your pocket.",
        "Don't tell me what you value, show me your budget, and I'll tell you what you value.",
        "An investment in knowledge pays the best interest.",
        "If you want to know what a man is really like, take notice of how he acts when he loses money.",
        "The more you learn, the more you earn.",
        "Wealth is the ability to fully experience life.",
        "Working because you want to, not because you have to, is financial freedom.",
        "Too many people spend money they earned to buy things they don't want to impress people they don't like.",
        "The price of anything is the amount of life you exchange for it.",
        
        // Investment Quotes
        "The goal isn't more money. The goal is living life on your terms.",
        "Money often costs too much.",
        "Wealth consists not in having great possessions, but in having few wants.",
        "It's not how much money you make, but how much money you keep, how hard it works for you, and how many generations you keep it for.",
        "If we command our wealth, we shall be rich and free. If our wealth commands us, we are poor indeed.",
        "Money is usually attracted, not pursued.",
        "Formal education will make you a living; self-education will make you a fortune.",
        "Money moves from those who do not manage it to those who do.",
        "You can only become truly accomplished at something you love. Don't make money your goal. Instead, pursue the things you love doing.",
        "Money grows on the tree of persistence.",
        
        // Business Quotes
        "Empty pockets never held anyone back. Only empty heads and empty hearts can do that.",
        "The only difference between a rich person and a poor person is how they use their time.",
        "Never depend on a single income. Make an investment to create a second source.",
        "Investing should be more like watching paint dry or watching grass grow. If you want excitement, take $800 and go to Las Vegas.",
        "In investing, what is comfortable is rarely profitable.",
        "Know what you own, and know why you own it.",
        "The best thing money can buy is financial freedom.",
        "Every time you borrow money, you're robbing your future self.",
        "Wealth is not his that has it, but his that enjoys it.",
        "It's good to have money and the things that money can buy, but it's good, too, to check up once in a while and make sure that you haven't lost the things that money can't buy.",
        
        // Success Quotes
        "The rich invest their money and spend what is left; the poor spend their money and invest what is left.",
        "It's not about timing the market, it's about time in the market.",
        "Do not save what is left after spending, but spend what is left after saving.",
        "Financial freedom is freedom from fear.",
        "Money is a guarantee that we may have what we want in the future.",
        "Income is like your health: if you ignore it, it will go away.",
        "Money can't buy happiness, but it will certainly get you a better class of memories.",
        "Time is more valuable than money. You can get more money, but you cannot get more time.",
        "Rule No.1: Never lose money. Rule No.2: Never forget rule No.1.",
        "The wealthy don't work for money; the wealthy have money work for them.",
        
        // Business Growth Quotes
        "In the business world, the rearview mirror is always clearer than the windshield.",
        "Business opportunities are like buses, there's always another one coming.",
        "If you don't find a way to make money while you sleep, you will work until you die.",
        "The stock market is designed to transfer money from the active to the patient.",
        "If you're not embarrassed by the first version of your product, you've launched too late.",
        "Your most unhappy customers are your greatest source of learning.",
        "Success is walking from failure to failure with no loss of enthusiasm.",
        "The only way to do great work is to love what you do.",
        "Chase the vision, not the money; the money will end up following you.",
        "Ideas are easy. Implementation is hard."
    ]
    
    // Function to get a random quote
    private func getRandomQuote() -> String {
        financialQuotes.randomElement() ?? "The best investment you can make is in yourself."
    }
    
    // Initialize the current quote when the view appears
    private func initializeQuote() {
        currentQuote = getRandomQuote()
    }
    
    // PERFORMANCE FIX: Optimize transaction fetching with relationship prefetching
    @FetchRequest(
        entity: Transaction.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)],
        animation: .default
    ) private var allTransactions: FetchedResults<Transaction>
    
    // PERFORMANCE FIX: Optimized cached filtered transactions with better filtering
    private var transactions: [Transaction] {
        guard let currentAccount = accountManager.currentAccount,
              let accountId = currentAccount.id else { return [] }
        
        // Use more efficient filtering by ID comparison instead of object comparison
        return allTransactions.prefix(1000).compactMap { transaction -> Transaction? in
            // Early exit for invalid transactions
            guard transaction.managedObjectContext != nil,
                  let transactionAccountId = transaction.account?.id else { return nil }
            
            // ID comparison is much faster than object comparison
            return transactionAccountId == accountId ? transaction : nil
        }
    }
    
    // Add these state variables to the HomeView struct after the other @State variables
    @AppStorage("isFirstLaunch") private var isFirstLaunch = true
    @AppStorage("isDemoEnabled") private var isDemoEnabled = false {
        didSet {
            // Force calendar to update when demo mode changes
            calendarUpdateID = UUID()
        }
    }
    @AppStorage("showDemoDataButton") private var showDemoDataButton = true
    @AppStorage("templatesEnabled") private var templatesEnabled = true
    @AppStorage("aiEnabled") private var aiEnabled = true
    @State private var showingPremiumSheet = false
    @State private var showingDemoPrompt = false
    @State private var showingClearDemoAlert = false
    @State private var isDemoDataLoading = false
    @State private var calendarUpdateID = UUID() // Added to force calendar updates
    @State private var refreshTrigger = UUID() // Force UI refresh for transactions
    @StateObject private var medalManager = MedalManager.shared
    @State private var editedTransaction: Transaction? = nil
    @State private var showingReceiptPreview: Bool = false
    @State private var receiptPreviewTransaction: Transaction? = nil
    @State private var scrollOffset: CGFloat = 0

    init() {
        // Initialize with a random quote
        _currentQuote = State(initialValue: getRandomQuote())
    }
    
    // Check if transactions are empty and show demo prompt if needed
    private func checkTransactionsAndShowDemoPrompt() {
        // Only run this check on first launch and if demo button is enabled in settings
        if !isFirstLaunch || !showDemoDataButton {
            return
        }
        
        // Check if there are any user-created transactions (non-demo)
        let userTransactions = transactions.filter { transaction in
            !transaction.isDemo && !(transaction.note?.contains("[DEMO]") == true)
        }
        
        // If user has transactions, mark first launch as complete and don't show demo prompt
        if userTransactions.count > 0 {
            isFirstLaunch = false
            return
        }
        
        // Only if it's first launch AND there are no user transactions, show the demo prompt
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation {
                self.showingDemoPrompt = true
            }
        }
    }
    
    private var filteredTransactions: [Transaction] {
        // Performance optimization: Use more efficient filtering
        let calendar = Calendar.current
        
        return transactions.compactMap { transaction -> Transaction? in
            guard let date = transaction.date else { return nil }
            
            // Filter out demo transactions when demo mode is disabled (early return)
            if !isDemoEnabled && transaction.isDemo {
                return nil
            }
            
            // Filter out carry-over transactions when viewing monthly or yearly periods
            // to prevent double-counting in transaction lists
            if transaction.isCarryOver && (selectedPeriod == .month || selectedPeriod == .year) {
                return nil
            }
            
            // Apply period filtering with optimized date comparisons
            switch selectedPeriod {
            case .day:
                return calendar.isDate(date, inSameDayAs: selectedDate) ? transaction : nil
            case .month:
                let dateComponents = calendar.dateComponents([.month, .year], from: date)
                let selectedComponents = calendar.dateComponents([.month, .year], from: selectedDate)
                return (dateComponents.month == selectedComponents.month && 
                       dateComponents.year == selectedComponents.year) ? transaction : nil
            case .year:
                let dateYear = calendar.component(.year, from: date)
                let selectedYear = calendar.component(.year, from: selectedDate)
                return dateYear == selectedYear ? transaction : nil
            }
        }
    }
    
    private var recentTransactions: [Transaction] {
        // Performance optimization: Efficient filtering for recent transactions
        // Removed artificial 15-transaction limit to fix deletion issues
        // Add refresh trigger dependency to ensure UI updates after deletions
        _ = refreshTrigger
        
        return transactions.compactMap { transaction -> Transaction? in
            // Filter out demo transactions when demo mode is disabled
            if isDemoEnabled || !transaction.isDemo {
                return transaction
            }
            return nil
        }
    }
    
    private var totalIncome: Double {
        // Force a re-evaluation when isDemoEnabled changes
        _ = calendarUpdateID
        
        // Regular income transactions 
        let regularIncome = filteredTransactions
            .filter { !$0.isExpense }
            .reduce(0) { $0 + $1.amount }
            
        // Include carry-overs for month and year periods
        let carryOverIncome: Double
        if selectedPeriod == .month || selectedPeriod == .year {
            carryOverIncome = transactions
                .filter { transaction in
                    guard let date = transaction.date,
                          transaction.isCarryOver,
                          !transaction.isExpense else { return false }
                    
                    // Apply demo filtering to carry-over transactions
                    if !isDemoEnabled && transaction.isDemo {
                        return false
                    }
                    
                    // Only include carry-overs for the current month/year
                    let calendar = Calendar.current
                    switch selectedPeriod {
                    case .day:
                        let dayStart = calendar.startOfDay(for: date)
                        let selectedDayStart = calendar.startOfDay(for: selectedDate)
                        return dayStart == selectedDayStart
                    case .month:
                        let components = calendar.dateComponents([.month, .year], from: date)
                        let selectedComponents = calendar.dateComponents([.month, .year], from: selectedDate)
                        return components.month == selectedComponents.month && components.year == selectedComponents.year
                    case .year:
                        return calendar.component(.year, from: date) == calendar.component(.year, from: selectedDate)
                    }
                }
                .reduce(0) { $0 + $1.amount }
        } else {
            carryOverIncome = 0
        }
        
        return regularIncome + carryOverIncome
    }
    
    private var totalExpenses: Double {
        // Force a re-evaluation when isDemoEnabled changes
        _ = calendarUpdateID
        
        return filteredTransactions
            .filter { $0.isExpense }
            .reduce(0) { $0 + $1.amount }
    }
    
    private var netBalance: Double {
        totalIncome - totalExpenses
    }
    
    private var largestTransaction: Transaction? {
        filteredTransactions.max(by: { $0.amount < $1.amount })
    }
    
    private var savingsRate: Double {
        // Calculate savings rate based on filtered transactions from the current account only
        let income = filteredTransactions.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount }
        let expenses = filteredTransactions.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
        
        guard income > 0 else { return 0 }
        return ((income - expenses) / income) * 100
    }
    
    
    
    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
    
    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    LazyVStack(spacing: 20, pinnedViews: []) {
                        
                        periodSelectorContent
                        navigationControlsContent
                        balanceCardsSectionContent
                        
                        Rectangle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(height: 2)
                            .padding(.horizontal)
                        
                        recentTransactionsSectionContent
                        
                        // Banner ad below recent transactions (no space when premium)
                        if !IAPManager.shared.isAdsRemoved {
                            AdBannerView(adPosition: .bottom, adPlacement: .home)
                                .padding(.vertical, 8)
                        }
                        
                        Rectangle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(height: 2)
                            .padding(.horizontal)
                        
                        quickStatsSectionContent
                        
                        Rectangle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(height: 2)
                            .padding(.horizontal)
                        
                        calendarExpensesSectionContent
                        
                        // Currency Rates Widget
                        if showCurrencyRates {
                            CurrencyRatesWidget()
                                .padding(.horizontal)
                        }
                        
                        quoteSection
                        
                        // Banner ad at the bottom of the home view (no space when premium)
                        if !IAPManager.shared.isAdsRemoved {
                            AdBannerView(adPosition: .bottom)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .onAppear {
                    print("🏠 HomeView appeared. templatesEnabled = \(templatesEnabled)")
                    checkTransactionsAndShowDemoPrompt()
                    if currentQuote.isEmpty {
                        initializeQuote()
                    }
                    // Initialize selectedDate to currentDate
                    selectedDate = currentDate
                }
                .refreshable {
                    await refreshData()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TransactionUpdated"))) { _ in
                    // Immediately trigger UI refresh for recent transactions
                    refreshTrigger = UUID()
                    
                    // Also do background refresh
                    Task {
                        await refreshData()
                    }
                }
                .navigationTitle("Home")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    applyLeadingToolbarItems()
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Group {
                            if let m = medalManager.currentMedal(for: accountManager.currentAccount?.id) {
                                Image(systemName: m.name)
                                    .foregroundColor(m.color)
                                    .font(.system(size: 18, weight: .bold))
                            }
                        }
                    }
                    applyTrailingToolbarItems()
                }
                .task {
                    // Force navigation bar to refresh and show glass containers
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = windowScene.windows.first,
                           let navController = window.rootViewController?.children.first as? UINavigationController {
                            navController.navigationBar.setNeedsLayout()
                            navController.navigationBar.layoutIfNeeded()
                        }
                    }
                }

                .sheet(isPresented: $showingSavingsDetails) {
                    FinancialHealthDetailView(transactions: filteredTransactions)
                }
                .sheet(isPresented: $showingHelpSheet) {
                    HelpOverviewView()
                }
            }
            .scrollContentBackground(.hidden)
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
            
            // Overlays positioned outside NavigationView for correct layering
            demoOverlays
            
            // Calculator overlay properly positioned in ZStack
            calculatorOverlay
            
        }
        .onAppear { MedalManager.shared.refresh(for: accountManager.currentAccount?.id) }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MedalProgressUpdated"))) { _ in
            MedalManager.shared.refresh(for: accountManager.currentAccount?.id)
        }
        // Inject global alert presenter for delete confirmations
        .overlay(deleteAlertPresenter)
        // Edit sheet for recent transaction cards
        .sheet(item: $editedTransaction) { t in
            EditTransactionView(transaction: t)
        }
        // Receipt preview sheet
        .sheet(isPresented: $showingReceiptPreview) {
            if let t = receiptPreviewTransaction {
                ReceiptPreviewWrapper(transaction: t, isPresented: $showingReceiptPreview)
            }
        }
        .alert("Remove Demo Data", isPresented: $showingClearDemoAlert) {
                Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                    disableDemoData()
                }
        } message: {
            Text("This will remove all demo transactions from your account. Your own transactions will not be affected.")
            }
            .alert(isPresented: $showingError) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .foregroundColor(Color.white)
            .sheet(isPresented: $showingTransactionPopup) {
                TransactionPopupView(
                    isExpense: popupIsExpense,
                    transactions: transactions
                )
            }
    }
    
    private var mainView: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 20) {
                    periodSelectorContent
                    navigationControlsContent
                    balanceCardsSectionContent
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(height: 2)
                        .padding(.horizontal)
                    
                    recentTransactionsSectionContent
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(height: 2)
                        .padding(.horizontal)
                    
                    quickStatsSectionContent
                    
                    quoteSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Home")
            .toolbar {
                applyLeadingToolbarItems()
                applyTrailingToolbarItems()
            }

            .sheet(isPresented: $showingSavingsDetails) {
                FinancialHealthDetailView(transactions: filteredTransactions)
            }
            .sheet(isPresented: $showingHelpSheet) {
                HelpOverviewView()
            }
            .sheet(isPresented: $showingPremiumSheet) {
                PremiumView()
            }
        }
        .sheet(isPresented: $showingTransactionPopup) {
            TransactionPopupView(
                isExpense: popupIsExpense,
                transactions: transactions
            )
        }
    }
    
    @ToolbarContentBuilder
    private func applyLeadingToolbarItems() -> some ToolbarContent {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 8) {
                        AccountMenu()
                        
                        if !isDemoEnabled && showDemoDataButton {
                            Button {
                                withAnimation {
                                    showingDemoPrompt = true
                                }
                            } label: {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.yellow)
                                    .imageScale(.medium)
                            }
                        }
                        
                        if showCalculator {
                            Button {
                                if !showingCalculator {
                                    showingCalculator = true
                                    centerCalculator()
                                } else {
                            // Hide if calculator is already showing
                            showingCalculator = false
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(.black)
                                        .frame(width: 32, height: 32)
                                    
                                    VStack(spacing: 2) {
                                        Rectangle()
                                            .fill(.white)
                                            .frame(width: 14, height: 2)
                                        Rectangle()
                                            .fill(.orange)
                                            .frame(width: 14, height: 2)
                            }
                                    }
                                }
                            }
                        }
                    }
                }
                
    @ToolbarContentBuilder
    private func applyTrailingToolbarItems() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 10) {
                // AI Button
                if aiEnabled {
                    Button(action: {
                        print("🤖 AI button tapped! Opening Spenly AI...")
                        if !iapManager.isPremiumUnlocked {
                            guard !isPresentingModal else { return }
                            isPresentingModal = true
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let window = windowScene.windows.first,
                               let rootViewController = window.rootViewController {
                                let premiumView = PremiumView()
                                    .environmentObject(themeManager)
                                let hosting = UIHostingController(rootView: premiumView)
                                hosting.modalPresentationStyle = .fullScreen
                                var presentingVC = rootViewController
                                while let presented = presentingVC.presentedViewController { presentingVC = presented }
                                presentingVC.present(hosting, animated: true) { isPresentingModal = false }
                            }
                        } else {
                            guard !isPresentingModal else { return }
                            isPresentingModal = true
                            openSpenlyChatView()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                isPresentingModal = false
                            }
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                                )
                                .overlay(
                                    LinearGradient(
                                        colors: [
                                            Color.cyan.opacity(0.6),
                                            Color.cyan.opacity(0.3)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    .clipShape(Circle())
                                )
                                .shadow(color: Color.cyan.opacity(0.3), radius: 4, x: 0, y: 2)
                            
                            Image(systemName: "brain.head.profile")
                                .foregroundColor(.white)
                                .font(.system(size: 13, weight: .bold))
                        }
                    }
                }
                
                // Template Button
                if templatesEnabled {
                    Button(action: { 
                        print("🎯 Template button tapped! Opening templates...")
                        
                        if !iapManager.isPremiumUnlocked {
                            // Present PremiumView as a full-screen sheet via UIKit to avoid any SwiftUI sheet conflicts
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let window = windowScene.windows.first,
                               let rootViewController = window.rootViewController {
                                let premiumView = PremiumView()
                                    .environmentObject(themeManager)
                                let hosting = UIHostingController(rootView: premiumView)
                                hosting.modalPresentationStyle = .fullScreen

                                var presentingVC = rootViewController
                                while let presented = presentingVC.presentedViewController {
                                    presentingVC = presented
                                }
                                presentingVC.present(hosting, animated: true) { isPresentingModal = false }
                            }
                            return
                        }
                        
                        // Use direct UIKit presentation (bypasses SwiftUI sheet issues)
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = windowScene.windows.first,
                           let rootViewController = window.rootViewController {
                            
                            // Create the actual template view controller
                            let templateView = TemplateListView()
                                .environmentObject(accountManager)
                                .environmentObject(themeManager)
                                .environment(\.managedObjectContext, viewContext)
                            let hostingController = UIHostingController(rootView: templateView)
                            hostingController.modalPresentationStyle = .fullScreen
                            
                            // Present it
                            var presentingVC = rootViewController
                            while let presented = presentingVC.presentedViewController {
                                presentingVC = presented
                            }
                            
                            presentingVC.present(hostingController, animated: true) { isPresentingModal = false }
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                                )
                                .overlay(
                                    LinearGradient(
                                        colors: [
                                            themeManager.getAccentColor(for: colorScheme).opacity(0.6),
                                            themeManager.getAccentColor(for: colorScheme).opacity(0.3)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    .clipShape(Circle())
                                )
                                .shadow(color: themeManager.getAccentColor(for: colorScheme).opacity(0.3), radius: 4, x: 0, y: 2)
                            
                            Image(systemName: "square.3.layers.3d")
                                .foregroundColor(.white)
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                }
            }
        }
    }
    
    // Function to open Spenly Chat View
    private func openSpenlyChatView() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            
            let chatView = SpenlyChatView()
                .environmentObject(themeManager)
                .environmentObject(accountManager)
                .environment(\.managedObjectContext, viewContext)
            let hostingController = UIHostingController(rootView: chatView)
            hostingController.modalPresentationStyle = .fullScreen
            
            var presentingVC = rootViewController
            while let presented = presentingVC.presentedViewController {
                presentingVC = presented
            }
            
            presentingVC.present(hostingController, animated: true) { isPresentingModal = false }
        }
    }
    
    // MARK: - Extracted Overlay Components
    
    @ViewBuilder
    private var calculatorOverlay: some View {
                    if showCalculator && showingCalculator {
                        GeometryReader { geo in
                        CalculatorView(isShowing: $showingCalculator)
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showingCalculator)
                    .zIndex(100) // Ensure calculator stays on top
                    }
                }
    }
    
    @ViewBuilder
    private var demoOverlays: some View {
        ZStack {
            // First Launch Demo Data Prompt - only show if setting is enabled
            if showingDemoPrompt && showDemoDataButton {
                demoPromptOverlay
            }
            
            // Demo Data Active Banner - only show if setting is enabled
            if isDemoEnabled && showDemoDataButton {
                demoEnabledBanner
            }
        }
        .animation(.spring(response: 0.3), value: showingDemoPrompt)
        .animation(.spring(response: 0.3), value: isDemoEnabled)
    }
    
    @ViewBuilder
    private var demoPromptOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22))
                    .foregroundColor(.yellow)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Try with Demo Data")
                        .font(selectedFont.font(size: 16, bold: true))
                        .foregroundColor(.white)
                    
                    Text("See how the app works with sample data")
                        .font(selectedFont.font(size: 12))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Button {
                    enableDemoData()
                } label: {
                    Text("Try")
                        .font(selectedFont.font(size: 14, bold: true))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(12)
                        .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                
                Button {
                    dismissDemoPrompt()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [.white.opacity(0.08), .white.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(.ultraThinMaterial.opacity(0.6))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    @ViewBuilder
    private var demoEnabledBanner: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundColor(.yellow)
                
                Text("Demo Data Enabled")
                    .font(selectedFont.font(size: 14, bold: true))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    showingClearDemoAlert = true
                } label: {
                    Text("Disable")
                        .font(selectedFont.font(size: 12, bold: true))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.7))
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(red: 0.12, green: 0.12, blue: 0.12))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 3)
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    @ViewBuilder
    private var demoLoadingOverlay: some View {
        ZStack {
            // Blur background with subtle animation
            Rectangle()
                .fill(Color.black.opacity(0.8))
                .background(.ultraThinMaterial)
                .edgesIgnoringSafeArea(.all)
            
            // Loading card with enhanced animations
            VStack(spacing: 24) {
                // Animated spinner
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                        .frame(width: 100, height: 100)
                    
                    // Animated spinner
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            Color.white,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(Angle(degrees: isDemoDataLoading ? 360 : 0))
                        .animation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false), value: isDemoDataLoading)
                }
                
                VStack(spacing: 10) {
                    Text("Creating Demo Data")
                        .font(selectedFont.font(size: 20, bold: true))
                        .foregroundColor(.white)
                    
                    // Animated progress dots
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(Color.white)
                                .frame(width: 6, height: 6)
                                .scaleEffect(isDemoDataLoading ? 1.0 : 0.01)
                                .animation(
                                    Animation.easeInOut(duration: 0.6)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(index) * 0.2),
                                    value: isDemoDataLoading
                                )
                        }
                    }
                    .frame(height: 10)
                    
                    Text("Setting up sample transactions")
                        .font(selectedFont.font(size: 14))
                        .foregroundColor(.gray)
                }
            }
            .padding(30)
            .background(Color.black)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        }
        .transition(.opacity)
        .onAppear {
            // Trigger animations immediately
            withAnimation(.easeInOut(duration: 0.01)) {
                isDemoDataLoading = true
            }
        }
        .onDisappear {
            // Stop animations when overlay goes away
            isDemoDataLoading = false
        }
    }
    
    var periodSelectorContent: some View {
        HStack(spacing: 12) {
            ForEach(TimePeriod.allCases) { period in
                Button(action: {
                    withAnimation {
                        selectedPeriod = period
                        // Update selectedDate to match currentDate when period changes
                        selectedDate = currentDate
                    }
                }) {
                    Text(period.rawValue)
                        .font(selectedFont.font(size: 15))
                        .fontWeight(selectedPeriod == period ? .semibold : .regular)
                        .foregroundColor(selectedPeriod == period ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(selectedPeriod == period ? themeManager.getAccentColor(for: colorScheme) : Color(.systemBackground))
                                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                        )
                }
            }
        }
        .padding(.horizontal)
    }
    
    var navigationControlsContent: some View {
        HStack {
                            Button {
                                moveToPreviousPeriod()
                            } label: {
                                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(8)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            }
            
            Spacer()
                            
                            Text(selectedPeriod.currentPeriodString(for: currentDate))
                .font(selectedFont.font(size: 16))
                .fontWeight(.medium)
            
            Spacer()
                            
                            Button {
                                moveToNextPeriod()
                            } label: {
                                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(8)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            }
        }
        .padding(.horizontal)
    }
    
    var balanceCardsSectionContent: some View {
        VStack(spacing: 16) {
            // Force update when demo mode changes with empty Text
            Text("").id(calendarUpdateID).frame(height: 0).opacity(0)
            
            // Total Balance Card
            BalanceCard(
                title: "Total Balance",
                amount: netBalance,
                trend: 0,
                color: .blue,
                icon: "",
                showIcon: false

            )
            
            HStack(spacing: 16) {
                // Income Card
                BalanceCard(
                    title: "Income",
                    amount: totalIncome,
                    trend: 0,
                    color: .green,
                    icon: "",
                    isCompact: true,
                    showIcon: false
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    print("💰 Income card tapped")
                    popupIsExpense = false
                    showingTransactionPopup = true
                    print("💰 showingTransactionPopup set to: \(showingTransactionPopup)")
                }
                
                // Expense Card
                BalanceCard(
                    title: "Expenses",
                    amount: totalExpenses,
                    trend: 0,
                    color: .red,
                    icon: "",
                    isCompact: true,
                    showIcon: false
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    print("💳 Expense card tapped")
                    popupIsExpense = true
                    showingTransactionPopup = true
                    print("💳 showingTransactionPopup set to: \(showingTransactionPopup)")
                }
                        }
                    }
                    .padding(.horizontal)
                }
                
    private var recentTransactionsSectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
            Text("Recent Transactions")
                .font(selectedFont.font(size: 18, bold: true))
                .foregroundColor(.white)
                
                Spacer()
                
                Text("Hold for edit / del")
                    .font(selectedFont.font(size: 12))
                    .foregroundColor(.gray)
            }
                .padding(.horizontal)
            
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                themeManager.getAccentColor(for: colorScheme).opacity(0.15),
                                themeManager.getAccentColor(for: colorScheme).opacity(0.05)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                if recentTransactions.isEmpty {
                    VStack(spacing: 12) {
                        Text("No recent transactions")
                            .font(selectedFont.font(size: 16))
                            .foregroundColor(.white.opacity(0.8))
                        Text("Add your first transaction using the '+' button")
                            .font(selectedFont.font(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 20) {
                            ForEach(recentTransactions, id: \.objectID) { transaction in
                                RecentTransactionCard(
                                    transaction: transaction,
                                    onEdit: { t in openEditSheet(for: t) },
                                    onDelete: { t in confirmDelete(t) },
                                    onViewReceipt: { t in openReceipt(for: t) }
                                )
                                .background(Color.clear)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }
                }
            }
            .frame(height: 180)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }
    
    var quickStatsSectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Stats")
                    .font(selectedFont.font(size: 18))
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("Tap for details")
                    .font(selectedFont.font(size: 12))
                            .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            // Widened Financial Health card
            FinancialHealthCard(transactions: filteredTransactions)
                .onTapGesture { showingSavingsDetails = true }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
        }
    }
    
    // Add the calendar expenses section
    private var calendarExpensesSectionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Calendar Expenses")
                    .font(selectedFont.font(size: 18))
                    .fontWeight(.semibold)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            // Use calendarUpdateID to force view to update when demo mode changes
            VStack(alignment: .leading, spacing: 16) {
                // Adding this empty Text with the ID forces the view to update
                Text("").id(calendarUpdateID).frame(height: 0).opacity(0)
                
                HStack {
                    Button(action: {
                        withAnimation {
                            currentDate = Calendar.current.date(byAdding: .month, value: -1, to: currentDate) ?? currentDate
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color(.systemGray6))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Text(formatMonthYear(currentDate))
                        .font(selectedFont.font(size: 16))
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            currentDate = Calendar.current.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color(.systemGray6))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                
                HStack(spacing: 0) {
                    ForEach(["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"], id: \.self) { day in
                        Text(day)
                            .font(selectedFont.font(size: 12))
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                
                let columns = Array(repeating: GridItem(.flexible()), count: 7)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(getDaysInMonth().prefix(42), id: \.self) { date in
                        let isCurrentMonth = Calendar.current.isDate(date, equalTo: currentDate, toGranularity: .month)
                        let isToday = Calendar.current.isDateInToday(date)
                        let dayExpense = getDailyExpenseTotal(for: date)
                        let day = Calendar.current.component(.day, from: date)
                        let hasExpense = dayExpense > 0
                        
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(getCalendarCellBackground(isToday: isToday, hasExpense: hasExpense, for: date))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(
                                            isToday ? Color.white.opacity(0.3) : Color.clear,
                                            lineWidth: isToday ? 1 : 0
                                        )
                                )
                                .shadow(
                                    color: isToday ? Color.blue.opacity(0.2) : Color.clear,
                                    radius: isToday ? 3 : 0, 
                                    x: 0, 
                                    y: 0
                                )
                            
                            VStack(spacing: 4) {
                                let textColor: Color = {
                                    if !isCurrentMonth {
                                        return .secondary.opacity(0.5)
                                    } else {
                                        return isToday ? .white : .primary
                                    }
                                }()
                                
                                Text("\(day)")
                                    .font(selectedFont.font(size: 15, bold: isToday))
                                    .foregroundColor(textColor)

                                if hasExpense {
                                    Text(formatCalendarCurrency(dayExpense))
                                        .font(selectedFont.font(size: 12))
                                        .fontWeight(.medium)
                                        .foregroundColor(isToday ? .white : .red)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .padding(.horizontal, 2)
                                        .padding(.vertical, 1)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(isToday ? Color.white.opacity(0.2) : Color.red.opacity(0.1))
                                        )
                                } else {
                                    Text("\(selectedCurrency.symbol)0")
                                        .font(selectedFont.font(size: 11))
                                        .foregroundColor(isToday ? .white.opacity(0.7) : .secondary.opacity(0.7))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(height: 48)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.3) {
                            if isCurrentMonth {
                                showDayExpensesPopup(for: date)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 16)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.03))
            .cornerRadius(20)
            .padding(.horizontal, 12)
        }
    }
    
    func moveToPreviousPeriod() {
        withAnimation {
            switch selectedPeriod {
            case .day:
                currentDate = Calendar.current.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
                selectedDate = currentDate
            case .month:
                currentDate = Calendar.current.date(byAdding: .month, value: -1, to: currentDate) ?? currentDate
                selectedDate = currentDate
            case .year:
                currentDate = Calendar.current.date(byAdding: .year, value: -1, to: currentDate) ?? currentDate
                selectedDate = currentDate
            }
        }
    }
    
    func moveToNextPeriod() {
        withAnimation {
            switch selectedPeriod {
            case .day:
                currentDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
                selectedDate = currentDate
            case .month:
                currentDate = Calendar.current.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
                selectedDate = currentDate
            case .year:
                currentDate = Calendar.current.date(byAdding: .year, value: 1, to: currentDate) ?? currentDate
                selectedDate = currentDate
            }
        }
    }

    // MARK: - Recent card actions
    @State private var pendingDelete: Transaction? = nil
    @State private var showDeleteAlert: Bool = false

    private func openEditSheet(for transaction: Transaction) {
        editedTransaction = transaction
    }

    private func openReceipt(for transaction: Transaction) {
        receiptPreviewTransaction = transaction
        showingReceiptPreview = true
    }

    private func confirmDelete(_ transaction: Transaction) {
        pendingDelete = transaction
        showDeleteAlert = true
    }

    private func deleteTransaction(_ transaction: Transaction) {
        withAnimation {
            if transaction.isCarryOver, let date = transaction.date, let account = transaction.account {
                CarryOverManager.shared.markCarryOverDeleted(for: date, account: account)
            }
            
            // THREAD SAFE deletion
            viewContext.perform { [self] in
                // Decrement contact usage if present
                if let contact = transaction.contact {
                    ContactManager.shared.decrementUsageCount(contact: contact, context: viewContext)
                }
                
                self.viewContext.delete(transaction)
                do {
                    try self.viewContext.save()
                    DispatchQueue.main.async {
                        self.refreshTrigger = UUID()
                        NotificationCenter.default.post(name: NSNotification.Name("TransactionUpdated"), object: nil)
                    }
                } catch {
                    print("Error deleting transaction: \(error.localizedDescription)")
                }
            }
        }
    }

    // Present the delete confirmation at top level
    @ViewBuilder
    private var deleteAlertPresenter: some View {
        EmptyView()
            .alert("Delete Transaction", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { pendingDelete = nil }
                Button("Delete", role: .destructive) {
                    if let t = pendingDelete { deleteTransaction(t) }
                    pendingDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete this transaction?")
            }
    }


    
    
    
    struct AccountMenu: View {
        @Environment(\.managedObjectContext) private var viewContext
        @EnvironmentObject private var accountManager: AccountManager
        @State private var showingAccountSettings = false
        
        @FetchRequest(
            entity: Account.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)]
        ) private var accounts: FetchedResults<Account>
        
        var body: some View {
            Menu {
                ForEach(accounts, id: \.id) { account in
                    Button {
                        accountManager.switchToAccount(account)
                    } label: {
                        HStack {
                            Text(account.name ?? "Unnamed Account")
                            if accountManager.currentAccount?.id == account.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                
                Divider()
                
                Button {
                    showingAccountSettings = true
                } label: {
                    Label("Manage Accounts", systemImage: "gear")
                }
            } label: {
                Image(systemName: "person.circle.fill")
                    .imageScale(.large)
                    .foregroundColor(.accentColor)
            }
            .sheet(isPresented: $showingAccountSettings) {
                AccountSettingsView()
            }
        }
    }
    
// MARK: - Extracted Components
// BalanceCard moved to separate file  
// StatCard moved to separate file
// ExpenseRankingSheet removed
// SavingsDetailView moved to separate file  
// HelpOverviewView moved to separate file


    
    // MARK: - Missing Methods (restored from extraction)
    
    private var quoteSection: some View {
        VStack(spacing: 20) {
            Text(currentQuote)
                    .font(selectedFont.font(size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 30)
                .padding(.vertical, 20)
                .background(
                RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                )
                .padding(.horizontal)
        }
        .padding(.top, 20)
        .padding(.bottom, 30)
    }
    
    private func refreshData() async {
        isRefreshing = true
        
        // Add a small delay to show refresh indicator
        try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
        
        // Refresh context on main thread
        await MainActor.run {
            // Immediately trigger UI refresh
            refreshTrigger = UUID()
            
            viewContext.refreshAllObjects()
            isRefreshing = false
        }
    }
    
    private func centerCalculator() {
        // Make sure calculator becomes visible
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showingCalculator = true
        }
    }
    
    private func enableDemoData() {
        withAnimation {
            showingDemoPrompt = false
            isFirstLaunch = false
        }
        
        // Create demo data first, THEN enable
        viewContext.perform { [self] in
            let calendar = Calendar.current
            let today = Date()
            
            // Clear any existing demo data first
            clearDemoDataSync()
            
            // Ensure account
            if AccountManager.shared.currentAccount == nil {
                AccountManager.shared.ensureAccountInitialized(context: viewContext)
            }
            
            guard AccountManager.shared.currentAccount != nil else {
                print("❌ Cannot create demo data - no account")
                return
            }
            
            // Create demo
            proceedWithDemoDataCreation(calendar: calendar, today: today)
            
            // Enable AFTER data is created
            DispatchQueue.main.async {
                withAnimation {
                    self.isDemoEnabled = true
                }
                
                // Refresh UI
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.viewContext.refreshAllObjects()
                    self.selectedDate = self.currentDate
                }
            }
        }
    }
    
    private func disableDemoData() {
        withAnimation {
            clearDemoData()
            isDemoEnabled = false
        }
    }
    
    private func dismissDemoPrompt() {
        withAnimation {
            showingDemoPrompt = false
            isFirstLaunch = false
        }
    }
    
    private func formatMonthYear(_ date: Date) -> String {
            let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
    }
    
    private func getDaysInMonth() -> [Date] {
        var days = [Date]()
        let calendar = Calendar.current
        
        guard let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: currentDate)) else {
            return days
        }

        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let weekdayOffset = firstWeekday - calendar.firstWeekday
        let startDate = calendar.date(byAdding: .day, value: -weekdayOffset, to: firstDay) ?? firstDay
        
        // Get the range of days in the current month
        guard let range = calendar.range(of: .day, in: .month, for: currentDate),
              let _ = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: firstDay) else {
            return days
        }
        
        let totalDaysInMonth = range.count
        
        // Calculate how many days we need to show (days before first day of month + total days in month)
        let numberOfDaysToShow = weekdayOffset + totalDaysInMonth
        
        // Calculate how many weeks we need (ceiling of days/7)
        let numberOfWeeksToShow = Int(ceil(Double(numberOfDaysToShow) / 7.0))
        
        // Show at most 42 days (6 weeks)
        for day in 0..<(numberOfWeeksToShow * 7) {
            if let date = calendar.date(byAdding: .day, value: day, to: startDate) {
                days.append(date)
            }
        }
        
        return days
    }
    
    private func getDailyExpenseTotal(for date: Date) -> Double {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // Force a re-evaluation of transactions whenever the isDemoEnabled changes
        // by adding a dummy expression that uses calendarUpdateID
        _ = calendarUpdateID
        
        let dailyExpenses = transactions.filter { transaction in
            guard let transactionDate = transaction.date else { return false }
            
            // Exclude carry-over transactions from daily totals
            if transaction.isCarryOver {
                return false
            }
            
            // Exclude demo transactions if demo mode is disabled
            if !isDemoEnabled && transaction.isDemo {
                return false
            }
            
            let isInDateRange = transactionDate >= startOfDay && transactionDate < endOfDay
            let isExpense = transaction.isExpense
            
            return isInDateRange && isExpense
        }
        
        let total = dailyExpenses.reduce(0) { $0 + $1.amount }
        return total
    }
    
    private func getCalendarCellBackground(isToday: Bool, hasExpense: Bool, for date: Date) -> Color {
        let accentColor = themeManager.getAccentColor(for: colorScheme)
        
        if isToday {
            return accentColor
        } else if hasExpense {
            // Get the daily expense amount for this date
            let expenseAmount = getDailyExpenseTotal(for: date)
            
            // Return different opacity based on expense amount
            if expenseAmount > 500 {
                return accentColor.opacity(0.3) // Darker shade for expenses > $500
            } else if expenseAmount >= 50 {
                return accentColor.opacity(0.2) // Medium shade for expenses $50-$500
            } else {
                return accentColor.opacity(0.1) // Light shade for expenses < $50
            }
        } else {
            return Color(.systemGray6)
        }
    }
    
    private func formatCalendarCurrency(_ amount: Double) -> String {
        if amount >= 1000 {
            return "\(selectedCurrency.symbol)\(String(format: "%.1f", amount / 1000))k"
        } else {
            return "\(selectedCurrency.symbol)\(Int(amount))"
        }
    }

    private func showDayExpensesPopup(for date: Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)

        selectedDayExpenses = transactions.filter { transaction in
            guard let transactionDate = transaction.date else { return false }
            let transactionDay = calendar.startOfDay(for: transactionDate)

            if !isDemoEnabled && transaction.isDemo {
                return false
            }
            
            return transactionDay == dayStart
        }.sorted { 
            ($0.isExpense ? 0 : 1) < ($1.isExpense ? 0 : 1)
        }
        
        selectedDayDate = date
        showingDayExpensesPopup = true
    }
    
    // Removed - logic moved into enableDemoData() to avoid race condition
    
    private func proceedWithDemoDataCreation(calendar: Calendar, today: Date) {
        // Get account ID for safe context switching
        guard let accountId = AccountManager.shared.currentAccount?.id else {
            print("ERROR: Cannot create demo data without a current account")
            return
        }
        
        // Fetch account in the SAME context as transaction
        let accountFetch: NSFetchRequest<Account> = Account.fetchRequest()
        accountFetch.predicate = NSPredicate(format: "id == %@", accountId as CVarArg)
        guard let currentAccount = try? viewContext.fetch(accountFetch).first else {
            print("ERROR: Cannot fetch account in current context for demo data")
            return
        }
        
        // Create demo categories if they don't exist
        let categories = [
            ("Food & Dining", "fork.knife", "expense"),
            ("Transportation", "car.fill", "expense"),
            ("Entertainment", "tv.fill", "expense"),
            ("Shopping", "cart.fill", "expense"),
            ("Salary", "dollarsign.circle.fill", "income"),
            ("Freelance", "briefcase.fill", "income")
        ]
        
        // Create a set of existing category names and types for quick lookup
        let fetchRequest: NSFetchRequest<Category> = Category.fetchRequest()
        let existingCategories = (try? viewContext.fetch(fetchRequest)) ?? []
        let existingCategoryKeys = Set(existingCategories.compactMap { category -> String? in
            guard let name = category.name, let type = category.type else { return nil }
            return "\(name)_\(type)"
        })
        
        // Only create categories that don't already exist
        for (name, icon, type) in categories {
            let categoryKey = "\(name)_\(type)"
            if !existingCategoryKeys.contains(categoryKey) {
                let category = Category(context: viewContext)
                category.id = UUID()
                category.name = name
                category.icon = icon
                category.type = type
                category.isCustom = true
            }
        }
        
        // Save categories immediately
        do {
            try viewContext.save()
        } catch {
            print("Error saving demo categories: \(error)")
            viewContext.rollback()
            return
        }
        
        // Get the start of the current month
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        
        // Get the number of days in the current month to ensure we don't exceed boundaries
        guard let daysInMonth = calendar.range(of: .day, in: .month, for: today)?.count else {
            print("ERROR: Could not determine days in current month")
            return
        }
        
        // Generate dates distributed throughout the current month for demo data
        // Ensure we don't exceed the month boundaries
        let maxDay = min(daysInMonth, 28) // Use 28 as safe maximum to work with all months
        let demoDateOffsets = [1, 3, 5, 7, 9, 12, 15, 18, 20, 22].map { min($0, maxDay) }
        
        // Helper function to get demo date by index
        func getDemoDate(at index: Int) -> Date {
            let dayOffset = demoDateOffsets[min(index, demoDateOffsets.count - 1)]
            let demoDate = calendar.date(byAdding: .day, value: dayOffset, to: currentMonthStart) ?? today
            
            // Extra safety check: ensure the date is still in the current month
            let demoMonth = calendar.dateComponents([.year, .month], from: demoDate)
            let currentMonth = calendar.dateComponents([.year, .month], from: today)
            
            if demoMonth.year == currentMonth.year && demoMonth.month == currentMonth.month {
                return demoDate
            } else {
                // Fallback to a safe date within the current month
                return calendar.date(byAdding: .day, value: min(dayOffset, 15), to: currentMonthStart) ?? today
            }
        }
        
        // Create demo transactions with dates distributed throughout the current month
        let demoData: [[String: Any]] = [
            [
                "amount": 45.99,
                "note": "[DEMO] Lunch at Cafe",
                "date": getDemoDate(at: 0),
                "isExpense": true,
                "category": "Food & Dining"
            ],
            [
                "amount": 29.99,
                "note": "[DEMO] Movie Tickets",
                "date": getDemoDate(at: 1),
                "isExpense": true,
                "category": "Entertainment"
            ],
            [
                "amount": 2500.00,
                "note": "[DEMO] Monthly Salary",
                "date": getDemoDate(at: 2),
                "isExpense": false,
                "category": "Salary"
            ],
            [
                "amount": 34.50,
                "note": "[DEMO] Uber Ride",
                "date": getDemoDate(at: 3),
                "isExpense": true,
                "category": "Transportation"
            ],
            [
                "amount": 120.75,
                "note": "[DEMO] Grocery Shopping",
                "date": getDemoDate(at: 4),
                "isExpense": true,
                "category": "Food & Dining"
            ],
            [
                "amount": 79.99,
                "note": "[DEMO] New Shirt",
                "date": getDemoDate(at: 5),
                "isExpense": true,
                "category": "Shopping"
            ],
            [
                "amount": 199.99,
                "note": "[DEMO] Concert Tickets",
                "date": getDemoDate(at: 6),
                "isExpense": true,
                "category": "Entertainment"
            ],
            [
                "amount": 350.00,
                "note": "[DEMO] Freelance Project",
                "date": getDemoDate(at: 7),
                "isExpense": false,
                "category": "Freelance"
            ],
            [
                "amount": 15.99,
                "note": "[DEMO] Coffee and Pastry",
                "date": getDemoDate(at: 8),
                "isExpense": true,
                "category": "Food & Dining"
            ],
            [
                "amount": 65.50,
                "note": "[DEMO] Gas Refill",
                "date": getDemoDate(at: 9),
                "isExpense": true,
                "category": "Transportation"
            ]
        ]
        
        // Re-fetch categories after save to ensure they're in the same context
        let categoryFetch: NSFetchRequest<Category> = Category.fetchRequest()
        let categoriesInContext = (try? viewContext.fetch(categoryFetch)) ?? []
        
        for transactionData in demoData {
            let newTransaction = Transaction(context: viewContext)
            newTransaction.id = UUID()
            newTransaction.amount = transactionData["amount"] as? Double ?? 0.0
            newTransaction.note = transactionData["note"] as? String ?? ""
            newTransaction.date = transactionData["date"] as? Date ?? Date()
            newTransaction.isExpense = transactionData["isExpense"] as? Bool ?? true
            newTransaction.isDemo = true
            newTransaction.account = currentAccount
            
            // Set category from already fetched categories
            if let categoryName = transactionData["category"] as? String {
                if let category = categoriesInContext.first(where: { $0.name == categoryName }) {
                    newTransaction.category = category
                }
            }
        }
        
        // Save transactions
        do {
            try viewContext.save()
            
            // Post notification that demo data was created
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("DemoDataCreated"),
                    object: nil
                )
            }
        } catch {
            print("Error saving demo transactions: \(error.localizedDescription)")
            
            // Rollback to avoid inconsistent state
            viewContext.rollback()
            
            // Handle error gracefully - show alert to user
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    let alert = UIAlertController(
                        title: "Demo Data Error",
                        message: "There was a problem creating demo data. Please try again later.",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    rootViewController.present(alert, animated: true)
                }
            }
        }
    }
    
    // Synchronous version for use within viewContext.perform blocks
    private func clearDemoDataSync() {
        let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isDemo == YES")
        
        guard let demoTransactions = try? viewContext.fetch(fetchRequest) else {
            print("Error fetching demo transactions for deletion")
            return
        }
        
        // Delete demo transactions
        for transaction in demoTransactions {
            viewContext.delete(transaction)
        }
        
        // Save context
        do {
            try viewContext.save()
        } catch {
            print("Error clearing demo data: \(error.localizedDescription)")
            viewContext.rollback()
        }
    }
    
    private func clearDemoData() {
        // Async wrapper for public API
        viewContext.perform { [self] in
            clearDemoDataSync()
        }
    }
}

// Day Expenses Popup View
struct DayExpensesPopupView: View {
    let transactions: [Transaction]
    let date: Date
    @Binding var isShowing: Bool
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @AppStorage("isDemoEnabled") private var isDemoEnabled = false
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }
    
    // Filter transactions to exclude demo data when demo mode is disabled
    // And ensure we're only accessing valid transactions
    private var filteredTransactions: [Transaction] {
        transactions.compactMap { transaction in
            // Skip this transaction if it's a demo transaction and demo mode is disabled
            if !isDemoEnabled && (transaction.note?.contains("[DEMO]") == true || transaction.isDemo) {
                return nil
            }
            // Skip transactions that might have been deleted or are invalid
            if transaction.isDeleted || transaction.managedObjectContext == nil {
                return nil
            }
            return transaction
        }
    }
    
    private var totalExpenses: Double {
        filteredTransactions.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
    }
    
    private var totalIncome: Double {
        filteredTransactions.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Date header with summary
                VStack(spacing: 12) {
                    Text(formattedDate)
                        .font(selectedFont.font(size: 18, bold: true))
                    
                    HStack(spacing: 24) {
                        VStack {
                            Text("Expenses")
                                .font(selectedFont.font(size: 14))
                                .foregroundColor(.secondary)
                            
                            Text(CurrencyFormatter.format(totalExpenses, currency: selectedCurrency))
                                .font(selectedFont.font(size: 18, bold: true))
                                .foregroundColor(.red)
                        }
                        
                        Divider()
                            .frame(height: 40)
                        
                        VStack {
                            Text("Income")
                                .font(selectedFont.font(size: 14))
                                .foregroundColor(.secondary)
                            
                            Text(CurrencyFormatter.format(totalIncome, currency: selectedCurrency))
                                .font(selectedFont.font(size: 18, bold: true))
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(themeManager.getAccentColor(for: colorScheme).opacity(0.1))
                
                if filteredTransactions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                            .padding(.top, 60)
                        
                        Text("No transactions on this day")
                            .font(selectedFont.font(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                } else {
                    // Transaction list
                    List {
                        Section(header: Text("Transactions")) {
                            ForEach(filteredTransactions, id: \.objectID) { transaction in
                                HStack(spacing: 16) {
                                    // Category icon
                                    ZStack {
                                        Circle()
                                            .fill(transaction.isExpense ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                                            .frame(width: 40, height: 40)
                                        
                                        Image(systemName: transaction.category?.icon ?? (transaction.isExpense ? "cart.fill" : "dollarsign.circle.fill"))
                                            .foregroundColor(transaction.isExpense ? .red : .green)
                                    }
                                    
                                    // Transaction details
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(transaction.category?.name ?? "Uncategorized")
                                            .font(selectedFont.font(size: 16, bold: true))
                                            
                                        if let note = transaction.note, !note.isEmpty {
                                            Text(note)
                                                .font(selectedFont.font(size: 14))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // Amount
                                    Text(CurrencyFormatter.format(transaction.amount, currency: selectedCurrency))
                                        .font(selectedFont.font(size: 16, bold: true))
                                        .foregroundColor(transaction.isExpense ? .red : .green)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isShowing = false
                    }
                }
            }
        }
    }
}

// Track home scroll offset
private struct HomeScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
