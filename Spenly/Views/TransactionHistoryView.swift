import SwiftUI
import CoreData
import Combine

enum TransactionSortOrder: String, CaseIterable, Identifiable {
    case dateDescending = "Newest First"
    case dateAscending = "Oldest First"
    case amountDescending = "Highest Amount"
    case amountAscending = "Lowest Amount"
    
    var id: String { rawValue }
    
    var description: String { rawValue }
    
    var sortDescriptor: NSSortDescriptor {
        switch self {
        case .dateDescending:
            return NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
        case .dateAscending:
            return NSSortDescriptor(keyPath: \Transaction.date, ascending: true)
        case .amountDescending:
            return NSSortDescriptor(keyPath: \Transaction.amount, ascending: false)
        case .amountAscending:
            return NSSortDescriptor(keyPath: \Transaction.amount, ascending: true)
        }
    }
}

struct TransactionHistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("selectedTheme") private var selectedTheme: Theme = .ocean
    @State private var searchText = ""
    @State private var showingSortOptions = false
    @State private var showingClearAlert = false
    @State private var selectedSortOrder: TransactionSortOrder = .dateDescending
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showingDeleteAlert = false
    @State private var transactionToDelete: Transaction?
    @State private var showFilterSheet = false
    @State private var selectedFilter: TransactionFilter = .all
    @State private var sortOrder: SortOrder = .dateDescending
    @State private var showingClearAllAlert = false
    @State private var debouncedSearchText = ""
    @State private var transactionToEdit: Transaction?
    @State private var showingEditSheet = false
    @State private var showingOptions = false
    @FetchRequest private var transactions: FetchedResults<Transaction>
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var isGridView = false
    @AppStorage("isGridViewEnabled") private var isGridViewEnabled = false
    @FetchRequest(
        entity: Category.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
    ) private var categories: FetchedResults<Category>
    @State private var showingAddTransaction = false
    @State private var showEmptySearchPopup = false
    @StateObject private var medalManager = MedalManager.shared
    @State private var searchDebouncer: AnyCancellable?
    @State private var contactFilter: Contact? = nil
    
    // Add state for refresh control
    @State private var isRefreshing = false
    
    // Multi-select functionality
    @State private var isMultiSelectMode = false
    @State private var selectedTransactions: Set<NSManagedObjectID> = []
    @State private var showingBulkDeleteAlert = false
    @State private var isTransferMode = false
    @State private var showingTransferAccountPicker = false
    @State private var selectedTransferAccount: Account?
    @State private var showingTransferConfirm = false
    
    // Static date formatter to avoid creating new ones repeatedly
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()
    
    // Static amount formatter to avoid creating new ones repeatedly
    private static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter
    }()
    
    init() {
        let request = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]
        
        // Performance optimization: Add fetch batch size and limit
        request.fetchBatchSize = 50
        request.fetchLimit = 1000 // Limit to 1000 most recent transactions
        
        // Create account predicate
        let accountPredicate = NSPredicate(format: "account == %@", AccountManager.shared.currentAccount ?? NSNull())
        request.predicate = accountPredicate
        
        // Initialize the fetch request
        _transactions = FetchRequest(
            fetchRequest: request,
            animation: .default
        )
        
        // Removed NotificationCenter observer for ShowTransactionsForContact as instructed
    }
    
    // Modify the grouped transactions property to limit maximum number of transactions and ensure proper ID management
    private var groupedTransactions: [(id: UUID, date: Date, transactions: [Transaction])] {
        let calendar = Calendar.current
        
        // Performance optimization: Limit to 300 transactions max to prevent performance issues
        let maxTransactions = 300
        let transactionsToGroup = Array(filteredAndSortedTransactions.prefix(maxTransactions))
        
        // Use more efficient grouping with pre-allocated capacity
        var grouped: [Date: [Transaction]] = [:]
        grouped.reserveCapacity(30) // Estimate for typical month groupings
        
        for transaction in transactionsToGroup {
            let groupDate = calendar.startOfDay(for: transaction.date ?? Date())
            if grouped[groupDate] != nil {
                grouped[groupDate]?.append(transaction)
            } else {
                grouped[groupDate] = [transaction]
            }
        }
        
        // Create result array with proper capacity and sort efficiently
        var result: [(id: UUID, date: Date, transactions: [Transaction])] = []
        result.reserveCapacity(grouped.count)
        
        for (date, transactions) in grouped {
            result.append((id: UUID(), date: date, transactions: transactions))
        }
        
        // Sort by date (newest first) - more efficient than during creation
        return result.sorted { $0.date > $1.date }
    }
    
    // Add date formatting function
    private func formatDate(_ date: Date) -> String {
        // Use the static formatter
        return Self.dateFormatter.string(from: date)
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemBackground) : Color(.systemGroupedBackground)
    }
    
    private var filteredAndSortedTransactions: [Transaction] {
        // Use debounced search text for filtering to reduce computation frequency
        let searchTextToUse = debouncedSearchText
        
        // Performance optimization: Limit initial dataset for faster processing
        let limitedTransactions = Array(transactions.prefix(500))
        
        // Apply filters to reduce the array size first - more efficient filtering order
        let filtered = limitedTransactions.compactMap { transaction -> Transaction? in
            // Early return for invalid transactions
            guard transaction.managedObjectContext != nil else { return nil }
            
            // Apply search filter first (most selective)
            if !searchTextToUse.isEmpty {
                let noteMatch = transaction.note?.localizedCaseInsensitiveContains(searchTextToUse) ?? false
                let categoryMatch = transaction.category?.name?.localizedCaseInsensitiveContains(searchTextToUse) ?? false
                if !noteMatch && !categoryMatch { return nil }
            }
            
            // Apply contact filter if set
            if let cf = contactFilter {
                if transaction.contact != cf { return nil }
            }
            
            // Then apply time-based filters with early returns
            switch selectedFilter {
            case .all:
                return transaction
            case .income:
                return !transaction.isExpense ? transaction : nil
            case .expenses:
                return transaction.isExpense ? transaction : nil
            case .lastWeek:
                guard let transactionDate = transaction.date else { return nil }
                let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                return transactionDate >= oneWeekAgo ? transaction : nil
            case .lastMonth:
                guard let transactionDate = transaction.date else { return nil }
                let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
                return transactionDate >= oneMonthAgo ? transaction : nil
            case .last3Months:
                guard let transactionDate = transaction.date else { return nil }
                let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
                return transactionDate >= threeMonthsAgo ? transaction : nil
            case .category(let category):
                return transaction.category?.id == category.id ? transaction : nil
            }
        }
        
        // Apply sorting with optimized date handling
        return filtered.sorted { first, second in
            switch selectedSortOrder {
            case .dateDescending:
                let firstDate = first.date ?? Date.distantPast
                let secondDate = second.date ?? Date.distantPast
                return firstDate > secondDate
            case .dateAscending:
                let firstDate = first.date ?? Date.distantPast
                let secondDate = second.date ?? Date.distantPast
                return firstDate < secondDate
            case .amountDescending:
                return first.amount > second.amount
            case .amountAscending:
                return first.amount < second.amount
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Group {
                    if transactions.isEmpty {
                        EmptyTransactionView(showingAddTransaction: $showingAddTransaction)
                    } else {
                        transactionListContentWithSearch
                    }
                }
                
                // Empty search popup
                if showEmptySearchPopup {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass.circle")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                        
                        Text("No transactions to search")
                            .font(selectedFont.font(size: 16))
                            .foregroundColor(.white)
                        
                        Button {
                            showingAddTransaction = true
                            showEmptySearchPopup = false
                        } label: {
                            Text("Add Transaction")
                                .font(selectedFont.font(size: 14))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(8)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.6))
                            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                    )
                    .padding(.horizontal, 48)
                    .transition(.opacity)
                }
            }
            .navigationTitle(isMultiSelectMode ? "Select Transactions" : "History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Group {
                        if let m = medalManager.currentMedal(for: accountManager.currentAccount?.id) {
                            Image(systemName: m.name)
                                .foregroundColor(m.color)
                                .font(.system(size: 18, weight: .bold))
                        }
                    }
                }
            }
            .navigationBarItems(
                leading: isMultiSelectMode ? AnyView(
                    Button("Cancel") {
                        exitMultiSelectMode()
                    }
                    .foregroundColor(.blue)
                ) : AnyView(EmptyView()),
                trailing: isMultiSelectMode ? AnyView(
                    HStack {
                        if isTransferMode {
                            Button("Transfer (\(selectedTransactions.count))") {
                                if !selectedTransactions.isEmpty { showingTransferAccountPicker = true }
                            }
                            .foregroundColor(selectedTransactions.isEmpty ? .gray : themeManager.getAccentColor(for: colorScheme))
                            .disabled(selectedTransactions.isEmpty)
                        } else {
                            Button("Delete (\(selectedTransactions.count))") {
                                showingBulkDeleteAlert = true
                            }
                            .foregroundColor(.red)
                            .disabled(selectedTransactions.isEmpty)
                        }
                    }
                ) : AnyView(
                    Button {
                        contactFilter = nil
                        showingClearAlert = true
                    } label: {
                        Text("Clear All")
                            .foregroundColor(.red)
                            .font(selectedFont.font(size: 16))
                    }
                )
            )
            .withTransactionSheets(
                showFilterSheet: $showFilterSheet,
                selectedFilter: $selectedFilter,
                transactionToEdit: $transactionToEdit,
                showingAddTransaction: $showingAddTransaction
            )
            .withTransactionAlerts(
                showingDeleteAlert: $showingDeleteAlert,
                showingClearAlert: $showingClearAlert,
                transactionToDelete: $transactionToDelete,
                deleteTransaction: deleteTransaction,
                clearAllTransactions: clearAllTransactions
            )
            .sheet(isPresented: $showingTransferAccountPicker) {
                TransferAccountPickerSheet { account in
                    selectedTransferAccount = account
                    showingTransferConfirm = true
                }
                .environmentObject(accountManager)
                .environmentObject(themeManager)
            }
            .alert("Transfer Transactions", isPresented: $showingTransferConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Move (remove from this account)", role: .destructive) {
                    if let target = selectedTransferAccount { performTransfer(to: target, move: true) }
                }
                Button("Copy (keep in both)") {
                    if let target = selectedTransferAccount { performTransfer(to: target, move: false) }
                }
            } message: {
                Text("Choose how to transfer the selected transactions.")
            }
            .alert("Delete Selected Transactions", isPresented: $showingBulkDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete \(selectedTransactions.count) Transactions", role: .destructive) {
                    bulkDeleteTransactions()
                }
            } message: {
                Text("This action cannot be undone.")
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
        .onAppear {
            setupSearchDebouncer()
        }
        .onDisappear {
            searchDebouncer?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TransactionUpdated"))) { _ in
            // Force refresh when a transaction is updated
            Task {
                await refreshData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowTransactionsForContact"))) { notification in
            if let contact = notification.object as? Contact {
                contactFilter = contact
            }
        }
        .onAppear { MedalManager.shared.refresh(for: accountManager.currentAccount?.id) }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MedalProgressUpdated"))) { _ in
            MedalManager.shared.refresh(for: accountManager.currentAccount?.id)
        }
    }
    
    // MARK: - Multi-Select Functions
    private func exitMultiSelectMode() {
        withAnimation {
            isMultiSelectMode = false
            selectedTransactions.removeAll()
        }
    }
    
    private func selectAllTransactions() {
        selectedTransactions = Set(filteredAndSortedTransactions.map { $0.objectID })
    }
    
    private func bulkDeleteTransactions() {
        withAnimation {
            // Get all selected transactions
            let transactionsToDelete = filteredAndSortedTransactions.filter { 
                selectedTransactions.contains($0.objectID) 
            }
            
            // Track carry-over transactions before deleting
            for transaction in transactionsToDelete {
                if transaction.isCarryOver, let date = transaction.date, let account = transaction.account {
                    CarryOverManager.shared.markCarryOverDeleted(for: date, account: account)
                }
            }
            
            // Delete all selected transactions - THREAD SAFE
            viewContext.perform { [self] in
                
                for transaction in transactionsToDelete {
                    self.viewContext.delete(transaction)
                }
                
                do {
                    try self.viewContext.save()
                    DispatchQueue.main.async {
                        self.exitMultiSelectMode()
                    }
                } catch {
                    print("Error deleting transactions: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // Function to setup search debouncer with optimized performance
    private func setupSearchDebouncer() {
        searchDebouncer?.cancel() // Cancel any existing debouncer to prevent memory leaks
        
        // Use simple timer-based debouncing that works reliably
        searchDebouncer = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if self.debouncedSearchText != self.searchText {
                    self.debouncedSearchText = self.searchText
                }
            }
    }
    
    // New main content with embedded search
    private var transactionListContentWithSearch: some View {
        Group {
            if isGridView {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Search bar with buttons (now inside scroll view)
                        searchBarSection
                            .padding()
                        
                        // Grid content
                        gridContent
                    }
                }
                .coordinateSpace(name: "transactionGrid")
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Search bar with buttons (now inside scroll view)
                        searchBarSection
                            .padding()
                        
                        // List content
                        if #available(iOS 15.0, *) {
                            listContent
                                .refreshable {
                                    await refreshData()
                                }
                        } else {
                            VStack {
                                PullToRefreshControl(isRefreshing: $isRefreshing) {
                                    Task {
                                        await refreshData()
                                    }
                                }
                                .frame(height: 50)
                                
                                listContent
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Search bar section as a separate component
    private var searchBarSection: some View {
        HStack {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search Transactions", text: $searchText)
                    .onChange(of: searchText) { newValue in
                        if transactions.isEmpty && !newValue.isEmpty {
                            withAnimation {
                                showEmptySearchPopup = true
                            }
                            // Auto-hide after 1 second
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                withAnimation {
                                    showEmptySearchPopup = false
                                }
                            }
                        }
                    }
                    .onSubmit {
                        if transactions.isEmpty && !searchText.isEmpty {
                            withAnimation {
                                showEmptySearchPopup = true
                            }
                            // Auto-hide after 1 second
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                withAnimation {
                                    showEmptySearchPopup = false
                                }
                            }
                        }
                    }
            }
            .padding(8)
            .background(Color.black)
            .cornerRadius(10)
            
            // Filter and grid buttons
            Button {
                if transactions.isEmpty {
                    withAnimation {
                        showEmptySearchPopup = true
                    }
                    // Auto-hide after 1 second
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        withAnimation {
                            showEmptySearchPopup = false
                        }
                    }
                } else {
                    showFilterSheet = true
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .imageScale(.large)
            }
            .padding(.horizontal, 4)
            
            Button {
                if transactions.isEmpty {
                    withAnimation {
                        showEmptySearchPopup = true
                    }
                    // Auto-hide after 1 second
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        withAnimation {
                            showEmptySearchPopup = false
                        }
                    }
                } else {
                    withAnimation {
                        isGridView.toggle()
                    }
                }
            } label: {
                Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                    .imageScale(.large)
            }
        }
    }
    
    // Grid content
    private var gridContent: some View {
        Group {
            if #available(iOS 15.0, *) {
                TransactionGridView(
                    transactions: filteredAndSortedTransactions,
                    transactionToEdit: $transactionToEdit,
                    showingEditSheet: $showingEditSheet,
                    transactionToDelete: $transactionToDelete,
                    showingDeleteAlert: $showingDeleteAlert,
                    isMultiSelectMode: $isMultiSelectMode,
                    selectedTransactions: $selectedTransactions,
                    isTransferMode: $isTransferMode
                )
                .refreshable {
                    await refreshData()
                }
            } else {
                VStack {
                    PullToRefreshControl(isRefreshing: $isRefreshing) {
                        Task {
                            await refreshData()
                        }
                    }
                    .frame(height: 50)
                    
                    TransactionGridView(
                        transactions: filteredAndSortedTransactions,
                        transactionToEdit: $transactionToEdit,
                        showingEditSheet: $showingEditSheet,
                        transactionToDelete: $transactionToDelete,
                        showingDeleteAlert: $showingDeleteAlert,
                        isMultiSelectMode: $isMultiSelectMode,
                        selectedTransactions: $selectedTransactions,
                        isTransferMode: $isTransferMode
                    )
                }
            }
        }
    }
    
    // List content
    private var listContent: some View {
        LazyVStack(spacing: 0, pinnedViews: []) {
            if groupedTransactions.isEmpty {
                emptyStateView
            } else {
                ForEach(groupedTransactions, id: \.id) { group in
                    // Date Header
                    dateSectionHeader(for: group.date)
                        .padding(.horizontal)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                    
                    // Transactions
                    ForEach(group.transactions, id: \.objectID) { transaction in
                        TransactionRowCell(
                            transaction: transaction,
                            selectedFont: selectedFont,
                            transactionToEdit: $transactionToEdit,
                            showingEditSheet: $showingEditSheet,
                            transactionToDelete: $transactionToDelete,
                            showingDeleteAlert: $showingDeleteAlert,
                            isMultiSelectMode: $isMultiSelectMode,
                            selectedTransactions: $selectedTransactions,
                            isTransferMode: $isTransferMode
                        )
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .padding(.bottom, 6)
                    }
                
                    // Divider
                    Rectangle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(height: 1)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }
                
                // Bottom spacing
                Color.clear.frame(height: 20)
            }
        }
        .background(Color.black)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.fill")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.6))
            Text("No transactions to show")
                        .font(selectedFont.font(size: 16))
                .foregroundColor(.white)
                .padding(.top, 8)
            Text("Try a different filter or clear your search")
                .font(selectedFont.font(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private func dateSectionHeader(for date: Date) -> some View {
        HStack {
            Text(date, style: .date)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    // Break out the main list content
    private var transactionListContent: some View {
        Group {
            if isGridView {
                ScrollView(showsIndicators: false) {
                    if #available(iOS 15.0, *) {
                        TransactionGridView(
                            transactions: filteredAndSortedTransactions,
                            transactionToEdit: $transactionToEdit,
                            showingEditSheet: $showingEditSheet,
                            transactionToDelete: $transactionToDelete,
                            showingDeleteAlert: $showingDeleteAlert,
                            isMultiSelectMode: $isMultiSelectMode,
                            selectedTransactions: $selectedTransactions,
                            isTransferMode: $isTransferMode
                        )
                        .refreshable {
                            await refreshData()
                        }
                    } else {
                        VStack {
                            PullToRefreshControl(isRefreshing: $isRefreshing) {
                                Task {
                                    await refreshData()
                                }
                            }
                            .frame(height: 50)
                            
                            TransactionGridView(
                                transactions: filteredAndSortedTransactions,
                                transactionToEdit: $transactionToEdit,
                                showingEditSheet: $showingEditSheet,
                                transactionToDelete: $transactionToDelete,
                                showingDeleteAlert: $showingDeleteAlert,
                                isMultiSelectMode: $isMultiSelectMode,
                                selectedTransactions: $selectedTransactions,
                                isTransferMode: $isTransferMode
                            )
                        }
                    }
                }
                .coordinateSpace(name: "transactionGrid")
            } else {
                CustomTransactionListView(
                    groupedTransactions: groupedTransactions,
                    selectedFont: selectedFont,
                    transactionToEdit: $transactionToEdit,
                    showingEditSheet: $showingEditSheet,
                    transactionToDelete: $transactionToDelete,
                    showingDeleteAlert: $showingDeleteAlert,
                    isMultiSelectMode: $isMultiSelectMode,
                    selectedTransactions: $selectedTransactions,
                    isTransferMode: $isTransferMode,
                    isRefreshing: $isRefreshing,
                    refreshAction: refreshData
                )
                }
        }
    }
    
    // MARK: - Custom List View Implementation
    struct CustomTransactionListView: View {
        let groupedTransactions: [(id: UUID, date: Date, transactions: [Transaction])]
        let selectedFont: AppFont
        @Binding var transactionToEdit: Transaction?
        @Binding var showingEditSheet: Bool
        @Binding var transactionToDelete: Transaction?
        @Binding var showingDeleteAlert: Bool
        @Binding var isMultiSelectMode: Bool
        @Binding var selectedTransactions: Set<NSManagedObjectID>
        @Binding var isTransferMode: Bool
        @Binding var isRefreshing: Bool
        let refreshAction: () async -> Void
        
        var body: some View {
            ScrollView {
                if #available(iOS 15.0, *) {
                    pullToRefreshContent
                .refreshable {
                            await refreshAction()
                }
            } else {
                    VStack {
                PullToRefreshControl(isRefreshing: $isRefreshing) {
                    Task {
                                await refreshAction()
                    }
                }
                .frame(height: 50)
                
                        pullToRefreshContent
                    }
                }
            }
            .background(Color.black)
        }
        
        private var pullToRefreshContent: some View {
            LazyVStack(spacing: 0, pinnedViews: []) {
                if groupedTransactions.isEmpty {
                    emptyStateView
                } else {
                    ForEach(groupedTransactions, id: \.id) { group in
                        // Date Header
                        dateSectionHeader(for: group.date)
                            .padding(.horizontal)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                        
                        // Transactions
                        ForEach(group.transactions, id: \.objectID) { transaction in
                            TransactionRowCell(
                                transaction: transaction,
                                selectedFont: selectedFont,
                                transactionToEdit: $transactionToEdit,
                                showingEditSheet: $showingEditSheet,
                                transactionToDelete: $transactionToDelete,
                                showingDeleteAlert: $showingDeleteAlert,
                                isMultiSelectMode: $isMultiSelectMode,
                                selectedTransactions: $selectedTransactions,
                                isTransferMode: $isTransferMode
                            )
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            .padding(.bottom, 6)
                        }
                    
                        // Divider
                        Rectangle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(height: 1)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                    }
                    
                    // Bottom spacing
                    Color.clear.frame(height: 20)
    }
            }
        }
        
        private var emptyStateView: some View {
            VStack(spacing: 16) {
                Image(systemName: "tray.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.6))
                Text("No transactions to show")
                            .font(selectedFont.font(size: 16))
                    .foregroundColor(.white)
                    .padding(.top, 8)
                Text("Try a different filter or clear your search")
                    .font(selectedFont.font(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        }
        
        private func dateSectionHeader(for date: Date) -> some View {
            HStack {
                Text(date, style: .date)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }
    
    struct TransactionRowCell: View {
        let transaction: Transaction
        let selectedFont: AppFont
        @Binding var transactionToEdit: Transaction?
        @Binding var showingEditSheet: Bool
        @Binding var transactionToDelete: Transaction?
        @Binding var showingDeleteAlert: Bool
        @Binding var isMultiSelectMode: Bool
        @Binding var selectedTransactions: Set<NSManagedObjectID>
        @Binding var isTransferMode: Bool
        @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
        @State private var showingReceiptPreview = false
        
        private var isSelected: Bool {
            selectedTransactions.contains(transaction.objectID)
        }
        
        var body: some View {
            HStack(spacing: 12) {
                // Selection circle for multi-select mode
                if isMultiSelectMode {
                    Button {
                        toggleSelection()
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? .blue : .gray)
                            .font(.system(size: 22))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(transaction.category?.name ?? "Uncategorized")
                            .font(selectedFont.font(size: 16))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        
                        // Add receipt indicator
                        if transaction.receiptFileName != nil {
                            Image(systemName: "paperclip")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                                .padding(4)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(4)
                        }
                        
                        // Add carry-over indicator
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
                    }
                    
                    if let note = transaction.note, !note.isEmpty {
                        Text(note)
                            .font(selectedFont.font(size: 14))
                            .foregroundColor(.gray)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // Show contact info if available
                    if let contact = transaction.contact {
                        Text("\(transaction.isExpense ? "Payee" : "Payer"): \(contact.safeName)")
                            .font(selectedFont.font(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                
                // Use the pre-optimized format method
                Text(CurrencyFormatter.format(transaction.amount, currency: selectedCurrency))
                    .font(selectedFont.font(size: 16))
                    .fontWeight(.semibold)
                    .foregroundColor(transaction.isExpense ? .red : .green)
            }
            .frame(height: 60)
            .padding(.horizontal, 16)
            .background(
                // Create gradient only once to avoid redrawing frequently
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: transaction.isExpense ? Color.red.opacity(0.1) : Color.green.opacity(0.1), location: 0),
                        .init(color: Color.black, location: 0.3)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .contentShape(Rectangle())
            .onTapGesture {
                if isMultiSelectMode {
                    toggleSelection()
                }
            }
            .contextMenu {
                if transaction.receiptFileName != nil {
                    Button {
                        showingReceiptPreview = true
                    } label: {
                        Label("View Receipt", systemImage: "paperclip")
                    }
                    Divider()
                }
                Button {
                    // Enter transfer multi-select mode
                    isMultiSelectMode = true
                    isTransferMode = true
                    selectedTransactions.insert(transaction.objectID)
                } label: {
                    Label("Transfer", systemImage: "arrow.left.arrow.right")
                }
                Button {
                    transactionToEdit = transaction
                    showingEditSheet = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    // Instead of direct delete, enter multi-select mode
                    isMultiSelectMode = true
                    isTransferMode = false
                    selectedTransactions.insert(transaction.objectID)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .sheet(isPresented: $showingReceiptPreview) {
                ReceiptPreviewWrapper(
                    transaction: transaction,
                    isPresented: $showingReceiptPreview
                )
            }
        }
        
        private func toggleSelection() {
            if isSelected {
                selectedTransactions.remove(transaction.objectID)
            } else {
                selectedTransactions.insert(transaction.objectID)
            }
        }
    }
    
    // Original TransactionRowView (keeping this for backward compatibility)
    private func TransactionRowView(transaction: Transaction) -> some View {
        TransactionRowCell(
            transaction: transaction,
            selectedFont: selectedFont,
            transactionToEdit: $transactionToEdit,
            showingEditSheet: $showingEditSheet,
            transactionToDelete: $transactionToDelete,
            showingDeleteAlert: $showingDeleteAlert,
            isMultiSelectMode: $isMultiSelectMode,
            selectedTransactions: $selectedTransactions,
            isTransferMode: $isTransferMode
        )
    }
    
    // MARK: - View Components
    
    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    // Grid/List toggle
                    Button {
                        withAnimation {
                            isGridView.toggle()
                        }
                    } label: {
                        Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                            .font(.system(size: 20))
                    }
                    
                    // Clear all button
                    Button {
                        showingClearAlert = true
                    } label: {
                        Text("Clear All")
                            .foregroundColor(.red)
                            .font(selectedFont.font(size: 16))
                    }
                }
            }
        }
    }
    
    // Helper Views
    struct TransactionDateHeader: View {
        let date: Date
        
        var body: some View {
            HStack {
                Text(date, style: .date)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }
    
    private func deleteTransaction(_ transaction: Transaction) {
        // Track if this is a carry-over transaction before deleting it
        if transaction.isCarryOver, let date = transaction.date, let account = transaction.account {
            // Mark this carry-over as manually deleted so it won't be recreated
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
            } catch {
                print("Error deleting transaction: \(error.localizedDescription)")
            }
        }
    }
    
    private func clearAllTransactions() {
        withAnimation {
            guard let currentAccount = accountManager.currentAccount else { return }
            
            // Store account ID before any operations that might affect it
            let accountId = currentAccount.id
            
            // First, find all carry-over transactions to mark them as deleted
            let carryOverFetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            carryOverFetchRequest.predicate = NSPredicate(format: "account == %@ AND isCarryOver == YES", currentAccount)
            
            if let carryOvers = try? viewContext.fetch(carryOverFetchRequest) {
                for transaction in carryOvers {
                    if let date = transaction.date {
                        // Mark each carry-over as manually deleted
                        CarryOverManager.shared.markCarryOverDeleted(for: date, account: currentAccount)
                    }
                }
            }
            
            // THREAD SAFE batch delete
            viewContext.perform { [self] in
                // First, decrement contact usage for all transactions being deleted
                let contactFetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
                contactFetchRequest.predicate = NSPredicate(format: "account == %@", currentAccount)
                contactFetchRequest.propertiesToFetch = ["contact"]
                
                if let transactionsToDelete = try? self.viewContext.fetch(contactFetchRequest) {
                    for transaction in transactionsToDelete {
                        if let contact = transaction.contact {
                            ContactManager.shared.decrementUsageCount(contact: contact, context: self.viewContext)
                        }
                    }
                }
                
                let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Transaction.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "account == %@", currentAccount)
                
                let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                batchDelete.resultType = .resultTypeObjectIDs
                
                do {
                    let result = try self.viewContext.execute(batchDelete) as? NSBatchDeleteResult
                    let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: result?.result as? [NSManagedObjectID] ?? []]
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.viewContext])
                    
                    // Save changes
                    try self.viewContext.save()
                    
                    // Reset and restore on main thread
                    DispatchQueue.main.async {
                        self.viewContext.reset()
                        
                        // Restore the current account after reset
                        if let accountId = accountId {
                            self.accountManager.restoreAccountAfterReset(context: self.viewContext, accountId: accountId)
                        }
                        
                        // Force refresh the UI
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: NSManagedObjectContext.didSaveObjectsNotification, object: nil)
                        }
                    }
                } catch {
                    print("Error clearing transactions: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func editTransaction(_ transaction: Transaction) {
        transactionToEdit = transaction
        showingEditSheet = true
    }
    
    private func showTransactionOptions(_ transaction: Transaction) {
        transactionToEdit = transaction
        showingOptions = true
    }
    
    // Add formatAmount function - optimize to use static formatter
    private func formatAmount(_ amount: Double) -> String {
        Self.amountFormatter.currencySymbol = selectedCurrency.symbol
        return Self.amountFormatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
    
    // Add this computed property for total amount
    private var totalAmount: Double {
        transactions.reduce(0) { sum, transaction in
            sum + (transaction.isExpense ? -transaction.amount : transaction.amount)
        }
    }
    
    // Improved refresh implementation 
    private func refreshData() async {
        // Set refreshing state
        isRefreshing = true
        
        await MainActor.run {
            // Use a lighter refresh approach that doesn't reset the entire context
            viewContext.refreshAllObjects()
            
            // Immediately turn off refreshing state
                withAnimation {
            isRefreshing = false
            }
        }
    }
}

enum TransactionFilter: Identifiable {
    case all
    case income
    case expenses
    case lastWeek
    case lastMonth
    case last3Months
    case category(Category)
    
    var id: String {
        switch self {
        case .all: return "all"
        case .income: return "income"
        case .expenses: return "expenses"
        case .lastWeek: return "lastWeek"
        case .lastMonth: return "lastMonth"
        case .last3Months: return "last3Months"
        case .category(let category): return "category-\(category.id?.uuidString ?? "")"
        }
    }
    
    var name: String {
        switch self {
        case .all: return "All Transactions"
        case .income: return "Income"
        case .expenses: return "Expenses"
        case .lastWeek: return "Last Week"
        case .lastMonth: return "Last Month"
        case .last3Months: return "Last 3 Months"
        case .category(let category): return category.name ?? "Uncategorized"
        }
    }
    
    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .income: return "arrow.down.circle.fill"
        case .expenses: return "arrow.up.circle.fill"
        case .lastWeek: return "clock.fill"
        case .lastMonth: return "calendar"
        case .last3Months: return "calendar.badge.clock"
        case .category(let category): return category.icon ?? "tag.fill"
        }
    }
    
    var predicate: NSPredicate? {
        switch self {
        case .all:
            return nil
        case .income:
            return NSPredicate(format: "isExpense == NO")
        case .expenses:
            return NSPredicate(format: "isExpense == YES")
        case .lastWeek:
            let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return NSPredicate(format: "date >= %@", oneWeekAgo as NSDate)
        case .lastMonth:
            let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            return NSPredicate(format: "date >= %@", oneMonthAgo as NSDate)
        case .last3Months:
            let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
            return NSPredicate(format: "date >= %@", threeMonthsAgo as NSDate)
        case .category(let category):
            return NSPredicate(format: "category == %@", category)
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case dateDescending = "Newest First"
    case dateAscending = "Oldest First"
    case amountDescending = "Highest Amount"
    case amountAscending = "Lowest Amount"
    
    var id: String { self.rawValue }
    var displayText: String { self.rawValue }
    
    var sortDescriptor: NSSortDescriptor {
        switch self {
        case .dateDescending:
            return NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
        case .dateAscending:
            return NSSortDescriptor(keyPath: \Transaction.date, ascending: true)
        case .amountDescending:
            return NSSortDescriptor(keyPath: \Transaction.amount, ascending: false)
        case .amountAscending:
            return NSSortDescriptor(keyPath: \Transaction.amount, ascending: true)
        }
    }
    
    var icon: String {
        switch self {
        case .dateDescending: return "calendar.badge.minus"
        case .dateAscending: return "calendar.badge.plus"
        case .amountDescending: return "dollarsign.arrow.circlepath"
        case .amountAscending: return "dollarsign.arrow.circlepath"
        }
    }
}

struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedFilter: TransactionFilter
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @FetchRequest(
        entity: Category.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
    ) private var categories: FetchedResults<Category>
    
    private var filters: [[TransactionFilter]] {
        [
            [.all], // General section
            [.income, .expenses], // Type section
            [.lastWeek, .lastMonth, .last3Months], // Time section
            categories.map { TransactionFilter.category($0) } // Categories section
        ]
    }
    
    var body: some View {
        NavigationView {
            List {
                // General Section
                Section("General") {
                    filterRow(filter: .all)
                }
                
                // Type Section
                Section("Type") {
                    filterRow(filter: .income)
                    filterRow(filter: .expenses)
                }
                
                // Time Period Section
                Section("Time Period") {
                    filterRow(filter: .lastWeek)
                    filterRow(filter: .lastMonth)
                    filterRow(filter: .last3Months)
                }
                
                // Categories Section
                if !categories.isEmpty {
                    Section("Categories") {
                        ForEach(categories, id: \.objectID) { category in
                            filterRow(filter: .category(category))
                        }
                    }
                }
            }
            .navigationTitle("Filter Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        selectedFilter = .all
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func filterRow(filter: TransactionFilter) -> some View {
        Button {
            selectedFilter = filter
            dismiss()
        } label: {
            HStack {
                // Icon
                Image(systemName: filter.icon)
                    .foregroundColor(iconColor(for: filter))
                    .font(.system(size: 20))
                    .frame(width: 24)
                
                // Title
                Text(filter.name)
                    .font(selectedFont.font(size: 16))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Selection indicator
                if filter.id == selectedFilter.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 20))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func iconColor(for filter: TransactionFilter) -> Color {
        switch filter {
        case .income: return .green
        case .expenses: return .red
        case .category: return .blue
        default: return .blue
        }
    }
}

struct TransactionSummaryView: View {
    let transactions: FetchedResults<Transaction>
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    
    private var totalIncome: Double {
        transactions.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount }
    }
    
    private var totalExpenses: Double {
        transactions.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Total Income")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(CurrencyFormatter.format(totalIncome, currency: selectedCurrency))
                        .font(.headline)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Total Expenses")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(CurrencyFormatter.format(totalExpenses, currency: selectedCurrency))
                        .font(.headline)
                        .foregroundColor(.red)
                }
            }
            
            // Monthly chart or additional statistics could be added here
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

// New View for Editing Transactions
struct EditTransactionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    let transaction: Transaction
    @State private var amount: String
    @State private var note: String
    @State private var date: Date
    @State private var isExpense: Bool
    @State private var selectedCategory: Category?
    @State private var showingCategoryPicker = false
    @State private var selectedReceiptImage: UIImage?
    @State private var showingReceiptPicker = false
    @State private var showingReceiptPreview = false
    @State private var existingReceiptImage: UIImage?
    @State private var selectedContact: Contact?
    @State private var showingContactPicker = false
    
    init(transaction: Transaction) {
        self.transaction = transaction
        _amount = State(initialValue: String(format: "%.2f", abs(transaction.amount)))
        _note = State(initialValue: transaction.note ?? "")
        _date = State(initialValue: transaction.date ?? Date())
        _isExpense = State(initialValue: transaction.isExpense)
        _selectedCategory = State(initialValue: transaction.category)
        _selectedContact = State(initialValue: transaction.contact)
        
        // Load existing receipt image if available (CloudKit-enabled)
        if let image = ReceiptManager.shared.getReceiptImage(from: transaction) {
            _existingReceiptImage = State(initialValue: image)
        } else {
            _existingReceiptImage = State(initialValue: nil)
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Small note about reopening the app
                    Text("Reopen the app to see changes")
                        .font(selectedFont.font(size: 12))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                    
                    // Amount Card
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "banknote.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 20))
                            Text("Amount")
                                .font(selectedFont.font(size: 14, bold: true))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .font(selectedFont.font(size: 24, bold: true))
                            .multilineTextAlignment(.center)
                            .foregroundColor(isExpense ? .red : .green)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    // Transaction Type Selector
                    HStack(spacing: 15) {
                        // Income Button
                        Button {
                            withAnimation { isExpense = false }
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 24))
                                Text("Income")
                                    .font(selectedFont.font(size: 16))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(!isExpense ? Color.green.opacity(0.2) : Color(.systemGray6))
                            .foregroundColor(!isExpense ? .green : .gray)
                            .cornerRadius(12)
                        }
                        
                        // Expense Button
                        Button {
                            withAnimation { isExpense = true }
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 24))
                                Text("Expense")
                                    .font(selectedFont.font(size: 16))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isExpense ? Color.red.opacity(0.2) : Color(.systemGray6))
                            .foregroundColor(isExpense ? .red : .gray)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Category Selector
                    Button {
                        showingCategoryPicker = true
                    } label: {
                        HStack {
                            Image(systemName: selectedCategory?.icon ?? "folder.fill")
                                .font(.system(size: 20))
                            Text(selectedCategory?.name ?? "Select Category")
                                .font(selectedFont.font(size: 17))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .foregroundColor(.primary)
                    }
                    .padding(.horizontal)
                    
                    // Receipt Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "paperclip")
                                .foregroundColor(.blue)
                            Text("Receipt")
                                .font(selectedFont.font(size: 14, bold: true))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                        if let receiptImage = selectedReceiptImage ?? existingReceiptImage {
                            VStack(spacing: 16) {
                                // Enhanced receipt preview
                                VStack(spacing: 12) {
                                    Image(uiImage: receiptImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 280, height: 140)
                                        .clipped()
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                                        )
                                        .shadow(color: Color.blue.opacity(0.2), radius: 8, x: 0, y: 4)
                                        .onTapGesture {
                                            showingReceiptPreview = true
                                        }
                                    
                                    HStack {
                                        Image(systemName: "doc.text.image")
                                            .foregroundColor(.blue)
                                            .font(.system(size: 14))
                                        Text("Tap to view full size")
                                            .font(selectedFont.font(size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                // Action buttons with enhanced styling
                                HStack(spacing: 16) {
                                    Button {
                                        showingReceiptPreview = true
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "magnifyingglass")
                                                .font(.system(size: 12))
                                            Text("View")
                                                .font(selectedFont.font(size: 14))
                                        }
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                    
                                    Button {
                                        showingReceiptPicker = true
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                                .font(.system(size: 12))
                                            Text("Replace")
                                                .font(selectedFont.font(size: 14))
                                        }
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.orange.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                    
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            selectedReceiptImage = nil
                                            existingReceiptImage = nil
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 12))
                                            Text("Remove")
                                                .font(selectedFont.font(size: 14))
                                        }
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.red.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(16)
                            .padding(.horizontal)
                        } else {
                            Button {
                                showingReceiptPicker = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("Add Receipt")
                                        .font(selectedFont.font(size: 16))
                                        .foregroundColor(.blue)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Note Field
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "note.text")
                                    .foregroundColor(.blue)
                            Text("Note")
                                .font(selectedFont.font(size: 14, bold: true))
                                    .foregroundColor(.secondary)
                            }
                        
                        TextField("Add note", text: $note)
                            .font(selectedFont.font(size: 17))
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // Contact Field
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue)
                            Text(isExpense ? "Payee" : "Payer")
                                .font(selectedFont.font(size: 14, bold: true))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                        Button {
                            showingContactPicker = true
                        } label: {
                            HStack {
                                if let contact = selectedContact {
                                    Text(contact.safeName)
                                        .font(selectedFont.font(size: 17))
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Button {
                                        selectedContact = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Text("Select \(isExpense ? "Payee" : "Payer")")
                                        .font(selectedFont.font(size: 17))
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 14))
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Calendar
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.blue)
                            Text("Date")
                                .font(selectedFont.font(size: 14, bold: true))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                        DatePicker("", selection: $date, displayedComponents: [.date])
                            .datePickerStyle(.graphical)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(16)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(selectedFont.font(size: 17))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .font(selectedFont.font(size: 17))
                    .disabled(amount.isEmpty || selectedCategory == nil)
                }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                CategoryPickerView(
                    selectedCategory: $selectedCategory,
                    type: isExpense ? "expense" : "income"
                )
            }
            .sheet(isPresented: $showingContactPicker) {
                ContactPickerView(
                    selectedContact: $selectedContact,
                    isPresented: $showingContactPicker
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
            .sheet(isPresented: $showingReceiptPreview) {
                ReceiptPreviewWrapper(
                    transaction: transaction,
                    isPresented: $showingReceiptPreview
                )
            }
        }
        .background(Color(.systemBackground))
    }
    
    private func saveChanges() {
        guard let amountDouble = Double(amount),
              let category = selectedCategory else { return }
        
        // Handle receipt changes first
        handleReceiptChanges()
        
        // THREAD SAFE update and save
        viewContext.perform { [self] in
            
            // Update the transaction properties
            self.transaction.amount = amountDouble
            self.transaction.note = note
            self.transaction.date = date
            self.transaction.isExpense = isExpense
            self.transaction.category = category
            self.transaction.contact = selectedContact
            
            do {
                // Save the changes to Core Data
                try self.viewContext.save()
                
                // Immediate UI refresh with multiple strategies
                DispatchQueue.main.async {
                    // 1. Refresh the specific transaction object
                    self.viewContext.refresh(self.transaction, mergeChanges: true)
                    
                    // 2. Force the context to refresh all objects to trigger @FetchRequest updates
                    self.viewContext.refreshAllObjects()
                    
                    // 3. Post notification for any custom observers
                    NotificationCenter.default.post(
                        name: NSNotification.Name("TransactionUpdated"),
                        object: self.transaction
                    )
                    
                    // Dismiss the edit view
                    self.dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    print("Error saving changes: \(error.localizedDescription)")
                    // Show error alert to user
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootViewController = windowScene.windows.first?.rootViewController {
                        let alert = UIAlertController(
                            title: "Save Failed",
                            message: "Failed to save your changes. Please try again.",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        rootViewController.present(alert, animated: true)
                    }
                }
            }
        }
    }
    
    private func handleReceiptChanges() {
        // Check if user removed the receipt
        if selectedReceiptImage == nil && existingReceiptImage == nil {
            // Remove existing receipt (both local and CloudKit)
            ReceiptManager.shared.deleteReceiptImage(from: transaction)
            return
        }
        
        // Check if user selected a new receipt image
        if let newReceiptImage = selectedReceiptImage {
            // Delete old receipt first (both local and CloudKit)
            ReceiptManager.shared.deleteReceiptImage(from: transaction)
            
            // Save new receipt with CloudKit sync
            if !ReceiptManager.shared.saveReceiptImageData(newReceiptImage, to: transaction) {
                print("⚠️ Failed to save new receipt image")
            }
        }
        // If no new image selected but existing image is present, keep it unchanged
    }
}

// New Grid View for Transactions
struct TransactionGridView: View {
    let transactions: [Transaction]
    @Binding var transactionToEdit: Transaction?
    @Binding var showingEditSheet: Bool
    @Binding var transactionToDelete: Transaction?
    @Binding var showingDeleteAlert: Bool
    @Binding var isMultiSelectMode: Bool
    @Binding var selectedTransactions: Set<NSManagedObjectID>
    @Binding var isTransferMode: Bool
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
            ], spacing: 20) {
                ForEach(transactions, id: \.objectID) { transaction in
                    TransactionGridCell(
                        transaction: transaction,
                        transactionToEdit: $transactionToEdit,
                        showingEditSheet: $showingEditSheet,
                        transactionToDelete: $transactionToDelete,
                        showingDeleteAlert: $showingDeleteAlert,
                        isMultiSelectMode: $isMultiSelectMode,
                        selectedTransactions: $selectedTransactions,
                        isTransferMode: $isTransferMode
                    )
                }
            }
            .padding()
        }
        .background(Color.black)
    }
}

struct TransactionGridCell: View {
    let transaction: Transaction
    @Binding var transactionToEdit: Transaction?
    @Binding var showingEditSheet: Bool
    @Binding var transactionToDelete: Transaction?
    @Binding var showingDeleteAlert: Bool
    @Binding var isMultiSelectMode: Bool
    @Binding var selectedTransactions: Set<NSManagedObjectID>
    @Binding var isTransferMode: Bool
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    
    private var isSelected: Bool {
        selectedTransactions.contains(transaction.objectID)
    }
    
    // Pre-calculate background gradient to avoid recreation on each render
    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: transaction.isExpense ? 
                [Color.red.opacity(0.1), Color.black] :
                [Color.green.opacity(0.1), Color.black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Selection indicator for multi-select mode
            if isMultiSelectMode {
                HStack {
                    Spacer()
                    Button {
                        toggleSelection()
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? .blue : .gray)
                            .font(.system(size: 20))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Header row with amount and carry-over indicator
            HStack {
                // Amount
                Text(CurrencyFormatter.format(transaction.amount, currency: selectedCurrency))
                    .font(selectedFont.font(size: 17))
                    .fontWeight(.semibold)
                    .foregroundColor(transaction.isExpense ? .red : .green)
                
                Spacer()
                
                // Carry-over indicator
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
            }
            
            // Category
            Text(transaction.category?.name ?? "Uncategorized")
                .font(selectedFont.font(size: 14))
                .foregroundColor(.white)
            
            // Note (if exists)
            if let note = transaction.note, !note.isEmpty {
                Text(note)
                    .font(selectedFont.font(size: 14))
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }
            
            // Contact info (if available)
            if let contact = transaction.contact {
                Text("\(transaction.isExpense ? "Payee" : "Payer"): \(contact.safeName)")
                    .font(selectedFont.font(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            // Date
            if let date = transaction.date {
                Text(date, style: .date)
                .font(selectedFont.font(size: 12))
                .foregroundColor(.gray)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(backgroundGradient)
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture {
            if isMultiSelectMode {
                toggleSelection()
            }
        }
        .contextMenu {
            Button("Transfer") {
                isMultiSelectMode = true
                isTransferMode = true
                selectedTransactions.insert(transaction.objectID)
            }
            Button("Edit") {
                transactionToEdit = transaction
                showingEditSheet = true
            }
            Button("Delete", role: .destructive) {
                // Instead of direct delete, enter multi-select mode
                isMultiSelectMode = true
                isTransferMode = false
                selectedTransactions.insert(transaction.objectID)
            }
        }
    }
    
    private func toggleSelection() {
        if isSelected {
            selectedTransactions.remove(transaction.objectID)
        } else {
            selectedTransactions.insert(transaction.objectID)
        }
    }
}

// Custom button style for controls
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

struct GridTransactionCard: View {
    let transaction: Transaction
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    var body: some View {
        VStack(spacing: 16) {
            // Amount at top
            Text(CurrencyFormatter.format(transaction.amount, currency: selectedCurrency))
                .font(selectedFont.font(size: 17))
                .fontWeight(.semibold)
                .foregroundColor(transaction.isExpense ? .red : .green)
                .frame(maxWidth: .infinity, alignment: .trailing)
            
            // Category and Note
            VStack(alignment: .leading, spacing: 6) {
                Text(transaction.category?.name ?? "Uncategorized")
                    .font(selectedFont.font(size: 16))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                if let note = transaction.note, !note.isEmpty {
                    Text(note)
                        .font(selectedFont.font(size: 14))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.black)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// Add SearchBar component
struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search transactions", text: $text)
                .textFieldStyle(PlainTextFieldStyle())
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// Update EmptyTransactionView
struct EmptyTransactionView: View {
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @AppStorage("selectedTheme") private var selectedTheme: Theme = .ocean
    @Environment(\.colorScheme) private var colorScheme
    @Binding var showingAddTransaction: Bool
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Simplified animation with just the empty circle
                Circle()
                    .fill(Color.accentColor.opacity(0.05))
                    .frame(width: 120, height: 120)
                .scaleEffect(isAnimating ? 1.2 : 1.0)
            .padding(.bottom, 20)
            .onAppear {
                // Use a more efficient, less CPU-intensive animation
                withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
            .onDisappear {
                isAnimating = false
            }
            
            Text("No Transactions Yet")
                .font(selectedFont.font(size: 24))
                .fontWeight(.semibold)
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Text("Track your finances by adding your first transaction")
                .font(selectedFont.font(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // Tips list
            VStack(alignment: .leading, spacing: 12) {
                tipRow(icon: "dollarsign", text: "Record incomes and expenses")
                tipRow(icon: "calendar", text: "View spending patterns over time")
                tipRow(icon: "chart.pie", text: "Analyze where your money goes")
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6).opacity(0.5))
            )
            .padding(.horizontal, 24)
            
            // CTA Button
            Button(action: {
                showingAddTransaction = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                    Text("Add Your First Transaction")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(16)
                .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }
    
    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Color.accentColor)
                .imageScale(.medium)
                .frame(width: 24, height: 24)
            
            Text(text)
                .font(selectedFont.font(size: 14))
                .foregroundColor(.secondary)
        }
    }
}

// Extension to handle sheets
extension View {
    func withTransactionSheets(
        showFilterSheet: Binding<Bool>,
        selectedFilter: Binding<TransactionFilter>,
        transactionToEdit: Binding<Transaction?>,
        showingAddTransaction: Binding<Bool>
    ) -> some View {
        self
            .sheet(isPresented: showFilterSheet) {
                FilterSheet(selectedFilter: selectedFilter)
            }
            .sheet(item: transactionToEdit) { transaction in
                EditTransactionView(transaction: transaction)
            }
            .sheet(isPresented: showingAddTransaction) {
                AddTransactionView()
            }
    }
    
    func withTransactionAlerts(
        showingDeleteAlert: Binding<Bool>,
        showingClearAlert: Binding<Bool>,
        transactionToDelete: Binding<Transaction?>,
        deleteTransaction: @escaping (Transaction) -> Void,
        clearAllTransactions: @escaping () -> Void
    ) -> some View {
        self
            .alert("Delete Transaction", isPresented: showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let transaction = transactionToDelete.wrappedValue {
                        deleteTransaction(transaction)
                    }
                }
            }
            .alert("Clear All Transactions", isPresented: showingClearAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear All", role: .destructive) {
                    clearAllTransactions()
                }
            } message: {
                Text("This action cannot be undone.")
            }
    }
}

private func transactionRow(_ transaction: Transaction) -> some View {
    HStack {
        if let category = transaction.category {
            Image(systemName: category.icon ?? "questionmark.circle")
                .foregroundColor(.blue)
                .frame(width: 30)
        }
        
        VStack(alignment: .leading) {
            Text(transaction.note ?? "")
                .font(.headline)
            if let category = transaction.category {
                Text(category.name ?? "")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        
        Spacer()
        
        VStack(alignment: .trailing) {
            Text(CurrencyFormatter.format(transaction.amount, currency: .usd))
                .font(.headline)
                .foregroundColor(transaction.isExpense ? .red : .green)
            
            if let date = transaction.date {
                Text(DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
    .padding(.vertical, 8)
}

// Helper function to limit transaction fetch count for better performance
private func filteredTransactionsWithLimit(_ transactions: [Transaction], limit: Int = 200) -> [Transaction] {
    Array(transactions.prefix(limit))
}

// Add fix for PullToRefreshControl
extension PullToRefreshControl {
    func limitHeightImpact() -> some View {
        self.frame(maxHeight: 50)
    }
}

// MARK: - Transfer Account Picker
private struct TransferAccountPickerSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)]
    ) private var accounts: FetchedResults<Account>
    let onSelect: (Account) -> Void
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(accounts.filter { $0 != accountManager.currentAccount }, id: \.objectID) { account in
                        Button {
                            onSelect(account)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(Color(.systemGray6).opacity(0.2))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "arrow.left.arrow.right")
                                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                                }
                                Text(account.name ?? "Account")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(.ultraThinMaterial)
                                    LinearGradient(
                                        colors: [
                                            themeManager.getAccentColor(for: colorScheme).opacity(0.1),
                                            themeManager.getAccentColor(for: colorScheme).opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    .cornerRadius(14)
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Transfer To")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Transfer Logic
private extension TransactionHistoryView {
    func performTransfer(to target: Account, move: Bool) {
        let ids = selectedTransactions
        guard !ids.isEmpty else { return }
        _ = accountManager.currentAccount
        viewContext.perform { [self] in
            do {
                for transaction in filteredAndSortedTransactions where ids.contains(transaction.objectID) {
                    if move {
                        transaction.account = target
                    } else {
                        let newT = Transaction(context: viewContext)
                        newT.id = UUID()
                        newT.amount = transaction.amount
                        newT.date = transaction.date
                        newT.note = transaction.note
                        newT.isExpense = transaction.isExpense
                        newT.isCarryOver = transaction.isCarryOver
                        newT.isDemo = transaction.isDemo
                        if transaction.entity.propertiesByName["isPaused"] != nil {
                            newT.setValue(transaction.value(forKey: "isPaused") as? Bool ?? false, forKey: "isPaused")
                        }
                        newT.category = transaction.category
                        newT.account = target
                        newT.receiptFileName = transaction.receiptFileName
                        newT.receiptUploadDate = transaction.receiptUploadDate
                    }
                }
                try viewContext.save()
                DispatchQueue.main.async {
                    exitMultiSelectMode()
                    isTransferMode = false
                    showingTransferAccountPicker = false
                    selectedTransferAccount = nil
                    showingTransferConfirm = false
                    NotificationCenter.default.post(name: NSNotification.Name("TransactionUpdated"), object: nil)
                }
            } catch {
                print("❌ Transfer error: \(error.localizedDescription)")
            }
        }
    }
}

 


