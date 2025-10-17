import SwiftUI
import CoreData

enum CategoryFilter: String, CaseIterable {
    case all = "All"
    case income = "Income"
    case expense = "Expense"
    case custom = "Custom"
    case system = "System"
}

enum CategorySortOrder: String, CaseIterable {
    case nameAscending = "Name (A-Z)"
    case nameDescending = "Name (Z-A)"
    case mostUsed = "Most Used"
    
    var sortDescriptors: [NSSortDescriptor] {
        switch self {
        case .nameAscending:
            return [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
        case .nameDescending:
            return [NSSortDescriptor(keyPath: \Category.name, ascending: false)]
        case .mostUsed:
            // Default to name sorting since we can't sort by transaction count directly
            return [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
        }
    }
}

struct CategoriesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var searchText = ""
    @State private var selectedFilter: CategoryFilter = .all
    @State private var selectedSort: CategorySortOrder = .nameAscending
    @State private var showingAddCategory = false
    @State private var editingCategory: Category?
    @State private var showingFilterSheet = false
    @State private var isRefreshing = false
    
    // Use FetchRequest for automatic updates
    @FetchRequest private var categories: FetchedResults<Category>
    
    // Add FetchRequest for transactions to use in groupedTransactions
    @FetchRequest private var transactions: FetchedResults<Transaction>
    
    init() {
        // Performance optimization: Add fetch limits and batch sizes
        let categorySortDescriptors = [
            NSSortDescriptor(keyPath: \Category.isCustom, ascending: true),
            NSSortDescriptor(keyPath: \Category.name, ascending: true)
        ]
        
        let categoryRequest = Category.fetchRequest()
        categoryRequest.sortDescriptors = categorySortDescriptors
        categoryRequest.fetchBatchSize = 20 // Optimize for typical category count
        
        _categories = FetchRequest<Category>(
            fetchRequest: categoryRequest,
            animation: .default
        )
        
        // Initialize transaction fetch request with performance optimizations
        let transactionRequest = Transaction.fetchRequest()
        transactionRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]
        transactionRequest.fetchBatchSize = 50
        transactionRequest.fetchLimit = 500 // Limit to 500 most recent transactions
        
        _transactions = FetchRequest<Transaction>(
            fetchRequest: transactionRequest,
            animation: .default
        )
    }
    
    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]
    
    // Add computed property for grouped transactions
    private var groupedTransactions: [(date: Date, transactions: [Transaction])] {
        let calendar = Calendar.current
        
        // Performance optimization: Limit transactions for better performance
        let limitedTransactions = Array(transactions.prefix(200))
        
        // Use more efficient grouping
        var grouped: [Date: [Transaction]] = [:]
        grouped.reserveCapacity(20) // Estimate for typical groupings
        
        for transaction in limitedTransactions {
            let groupDate = calendar.startOfDay(for: transaction.date ?? Date())
            if grouped[groupDate] != nil {
                grouped[groupDate]?.append(transaction)
            } else {
                grouped[groupDate] = [transaction]
            }
        }
        
        return grouped.map { (date: $0.key, transactions: $0.value) }
            .sorted { $0.date > $1.date }
    }
    
    // Add TransactionRowView function
    private func TransactionRowView(transaction: Transaction) -> some View {
        Button {
            // Implement action as needed
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if let note = transaction.note, !note.isEmpty {
                        Text(transaction.category?.name ?? "Uncategorized")
                            .font(.system(size: 16))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Text(note)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(transaction.category?.name ?? "Uncategorized")
                            .font(.system(size: 16))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                Spacer()
                Text(CurrencyFormatter.format(transaction.amount, currency: .usd))
                    .font(.system(size: 16))
                    .fontWeight(.semibold)
                    .foregroundColor(transaction.isExpense ? .red : .green)
            }
            .frame(height: 60)
            .padding(.horizontal, 16)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    var body: some View {
        VStack(spacing: 0) {
                // Search and Filter Bar
                HStack(spacing: 12) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search Categories", text: $searchText)
                            .font(selectedFont.font(size: 16))
                    }
                    .padding(8)
                    .background(Color.black)
                    .cornerRadius(10)
                    
                    // Filter button (includes both filter and sort)
                    Button {
                        showingFilterSheet = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .imageScale(.large)
                            .foregroundColor((selectedFilter != .all || selectedSort != .nameAscending) ? themeManager.getAccentColor(for: colorScheme) : .primary)
                    }
                    .padding(.horizontal, 4)
                }
                .padding()
                
                // Always show grid view
                if #available(iOS 15.0, *) {
                    ScrollView {
                        let filteredCategories = getFilteredCategories()
                        
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredCategories, id: \.objectID) { category in
                                CategoryGridItem(category: category)
                                    .onTapGesture {
                                        editingCategory = category
                                    }
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        await refreshData()
                    }
                } else {
                    ScrollView {
                        // Custom refresh control
                        PullToRefreshControl(isRefreshing: $isRefreshing) {
                            Task {
                                await refreshData()
                            }
                        }
                        .frame(height: 50)
                        
                        let filteredCategories = getFilteredCategories()
                        
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredCategories, id: \.objectID) { category in
                                CategoryGridItem(category: category)
                                    .onTapGesture {
                                        editingCategory = category
                                    }
                            }
                        }
                        .padding()
                    }
                }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddCategory = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                }
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            CategoryAddView()
                .onDisappear {
                    // Refresh when the add sheet is dismissed
                    Task {
                        await refreshData()
                    }
                }
        }
        .sheet(item: $editingCategory) { category in
            EditCategoryView(category: category)
                .onDisappear {
                    // Refresh when the edit sheet is dismissed
                    Task {
                        await refreshData()
                    }
                }
        }
        .sheet(isPresented: $showingFilterSheet) {
            FilterSortSheet(
                selectedFilter: $selectedFilter,
                selectedSort: $selectedSort
            )
        }
    }
    
    // Function to refresh data
    private func refreshData() async {
        isRefreshing = true
        
        // Reduced wait time for better UX
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds delay
        
        await MainActor.run {
            viewContext.refreshAllObjects()
            isRefreshing = false
        }
    }
    
    private func getFilteredCategories() -> [Category] {
        // Use a Set to track unique categories by name and type
        var uniqueCategories = Set<String>()
        var filteredCategories: [Category] = []
        
        // First pass: collect unique categories
        for category in categories {
            guard let name = category.name, let type = category.type else { continue }
            let key = "\(name)_\(type)"
            if !uniqueCategories.contains(key) {
                uniqueCategories.insert(key)
                filteredCategories.append(category)
            }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            filteredCategories = filteredCategories.filter { category in
                category.name?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
        
        // Apply type filter
        switch selectedFilter {
        case .income:
            filteredCategories = filteredCategories.filter { $0.type == "income" }
        case .expense:
            filteredCategories = filteredCategories.filter { $0.type == "expense" }
        case .custom:
            filteredCategories = filteredCategories.filter { $0.isCustom }
        case .system:
            filteredCategories = filteredCategories.filter { !$0.isCustom }
        case .all:
            break
        }
        
        // Apply sort
        switch selectedSort {
        case .nameAscending:
            filteredCategories.sort { ($0.name ?? "") < ($1.name ?? "") }
        case .nameDescending:
            filteredCategories.sort { ($0.name ?? "") > ($1.name ?? "") }
        case .mostUsed:
            filteredCategories.sort {
                ($0.transactions?.count ?? 0) > ($1.transactions?.count ?? 0)
            }
        }
        
        return filteredCategories
    }
    
    private var transactionListView: some View {
        List {
            if #available(iOS 15.0, *) {
                ForEach(Array(groupedTransactions.enumerated()), id: \.1.date) { index, group in
                    Section {
                        if index != 0 {
                            Rectangle()
                                .fill(Color.gray.opacity(0.25))
                                .frame(height: 1)
                                .padding(.vertical, 2)
                        }
                        Text(group.date, style: .date)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                        ForEach(group.transactions, id: \.objectID) { transaction in
                            TransactionRowView(transaction: transaction)
                                .padding(.vertical, 6)
                                .padding(.bottom, 6)
                        }
                    }
                }
                .refreshable {
                    await refreshData()
                }
            } else {
                PullToRefreshControl(isRefreshing: $isRefreshing) {
                    Task {
                        await refreshData()
                    }
                }
                .frame(height: 50)
                
                ForEach(Array(groupedTransactions.enumerated()), id: \.1.date) { index, group in
                    Section {
                        if index != 0 {
                            Rectangle()
                                .fill(Color.gray.opacity(0.25))
                                .frame(height: 1)
                                .padding(.vertical, 2)
                        }
                        Text(group.date, style: .date)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                        ForEach(group.transactions, id: \.objectID) { transaction in
                            TransactionRowView(transaction: transaction)
                                .padding(.vertical, 6)
                                .padding(.bottom, 6)
                        }
                    }
                }
            }
        }
        .optimizedList()
        .coordinateSpace(name: "transactionList")
    }
}

struct FilterSortSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedFilter: CategoryFilter
    @Binding var selectedSort: CategorySortOrder
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @EnvironmentObject private var themeManager: ThemeManager
    
    var body: some View {
        NavigationView {
            List {
                // Filter Section
                Section("Filter Categories") {
                    filterRow(filter: .all, icon: "square.grid.2x2", iconColor: themeManager.getAccentColor(for: colorScheme))
                    filterRow(filter: .income, icon: "arrow.down.circle", iconColor: .green)
                    filterRow(filter: .expense, icon: "arrow.up.circle", iconColor: .red)
                    filterRow(filter: .custom, icon: "person.crop.circle", iconColor: .purple)
                    filterRow(filter: .system, icon: "gear.circle", iconColor: .gray)
                }
                
                // Sort Section  
                Section("Sort Order") {
                    sortRow(sort: .nameAscending, icon: "textformat.alt", iconColor: themeManager.getAccentColor(for: colorScheme))
                    sortRow(sort: .nameDescending, icon: "textformat", iconColor: themeManager.getAccentColor(for: colorScheme))
                    sortRow(sort: .mostUsed, icon: "chart.bar.fill", iconColor: .orange)
                }
            }
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        selectedFilter = .all
                        selectedSort = .nameAscending
                    }
                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func filterRow(filter: CategoryFilter, icon: String, iconColor: Color) -> some View {
        Button {
            selectedFilter = filter
        } label: {
            HStack {
                // Icon
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 20))
                    .frame(width: 24)
                
                // Title
                Text(filter.rawValue)
                    .font(selectedFont.font(size: 16))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Selection indicator
                if filter == selectedFilter {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                        .font(.system(size: 20))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func sortRow(sort: CategorySortOrder, icon: String, iconColor: Color) -> some View {
        Button {
            selectedSort = sort
        } label: {
            HStack {
                // Icon
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 20))
                    .frame(width: 24)
                
                // Title
                Text(sort.rawValue)
                    .font(selectedFont.font(size: 16))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Selection indicator
                if sort == selectedSort {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                        .font(.system(size: 20))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CategoryGridItem: View {
    let category: Category
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    var categoryColor: Color {
        if category.type == "income" {
            return .green
        } else {
            return .blue
        }
    }
    
    var transactionCount: Int {
        if let transactions = category.transactions as? Set<Transaction> {
            return transactions.count
        }
        return 0
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(categoryColor.opacity(0.1))
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: category.icon ?? "tag.fill")
                        .font(.system(size: 24))
                        .foregroundColor(categoryColor)
                }
            
            VStack(spacing: 4) {
                Text(category.name ?? "")
                    .font(selectedFont.font(size: 16, bold: true))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text("\(transactionCount) transactions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct CategoryList: View {
    @Environment(\.managedObjectContext) private var viewContext
    let searchText: String
    let filter: CategoryFilter
    let sortOrder: CategorySortOrder
    
    @FetchRequest private var categories: FetchedResults<Category>
    
    init(searchText: String, filter: CategoryFilter, sortOrder: CategorySortOrder) {
        self.searchText = searchText
        self.filter = filter
        self.sortOrder = sortOrder
        
        var predicates: [NSPredicate] = []
        
        // Search predicate
        if !searchText.isEmpty {
            predicates.append(NSPredicate(format: "name CONTAINS[cd] %@", searchText))
        }
        
        // Filter predicate
        switch filter {
        case .income:
            predicates.append(NSPredicate(format: "type == %@", "income"))
        case .expense:
            predicates.append(NSPredicate(format: "type == %@", "expense"))
        case .custom:
            predicates.append(NSPredicate(format: "isCustom == YES"))
        case .system:
            predicates.append(NSPredicate(format: "isCustom == NO"))
        case .all:
            break
        }
        
        // Add predicate to prevent duplicates
        predicates.append(NSPredicate(format: "name != nil"))
        
        let predicate = predicates.isEmpty ? nil :
            NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        _categories = FetchRequest<Category>(
            sortDescriptors: sortOrder.sortDescriptors,
            predicate: predicate,
            animation: .default
        )
    }
    
    var sortedCategories: [Category] {
        let array = Array(categories)
        if sortOrder == .mostUsed {
            return array.sorted { cat1, cat2 in
                let count1 = (cat1.transactions?.count ?? 0)
                let count2 = (cat2.transactions?.count ?? 0)
                return count1 > count2
            }
        }
        return array
    }
    
    var body: some View {
        List {
            ForEach(sortedCategories, id: \.objectID) { category in
                CategoryRow(category: category)
            }
            .onDelete(perform: deleteCategories)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
    
    private func deleteCategories(at offsets: IndexSet) {
        withAnimation {
            offsets.map { sortedCategories[$0] }.forEach { category in
                // Only allow deleting custom categories
                if category.isCustom {
                    viewContext.delete(category)
                }
            }
            try? viewContext.save()
        }
    }
}

struct CategoryRow: View {
    let category: Category
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(category.name ?? "")
                    .font(selectedFont.font(size: 18))
                
                HStack {
                    Text(category.type ?? "")
                        .font(selectedFont.font(size: 15))
                        .foregroundColor(.secondary)
                    
                    if !category.isCustom {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("System")
                            .font(selectedFont.font(size: 15))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Text("\(category.transactions?.count ?? 0) transactions")
                .font(selectedFont.font(size: 15))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(.systemGray3), lineWidth: 1.0)
        )
    }
}

struct EditCategoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    let category: Category
    
    @State private var name: String = ""
    @State private var selectedIcon: String = "tag.fill"
    @State private var showingDeleteAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Category Name", text: $name)
                            .onChange(of: name) { newValue in
                                // Limit to 25 characters
                                if newValue.count > 25 {
                                    name = String(newValue.prefix(25))
                                }
                            }
                        
                        // Character counter
                        HStack {
                            Spacer()
                            Text("\(name.count)/25")
                                .font(.caption)
                                .foregroundColor(name.count > 20 ? (name.count == 25 ? .red : .orange) : .secondary)
                        }
                    }
                    
                    IconPickerView(selectedIcon: $selectedIcon)
                }
                
                if category.isCustom {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete Category", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveCategory()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Delete Category", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteCategory()
                }
            } message: {
                Text("Are you sure you want to delete this category? This action cannot be undone.")
            }
            .onAppear {
                name = category.name ?? ""
                selectedIcon = category.icon ?? "tag.fill"
            }
        }
    }
    
    private func saveCategory() {
        category.name = name.trimmingCharacters(in: .whitespaces)
        category.icon = selectedIcon
        
        try? viewContext.save()
        dismiss()
    }
    
    private func deleteCategory() {
        viewContext.delete(category)
        try? viewContext.save()
        dismiss()
    }
}

struct IconPickerView: View {
    @Binding var selectedIcon: String
    
    let icons = [
        "tag.fill",
        "cart.fill",
        "dollarsign.circle.fill",
        "creditcard.fill",
        "house.fill",
        "car.fill",
        "fork.knife.circle.fill",
        "bag.fill",
        "cross.case.fill",
        "doc.text.fill",
        "tv.fill",
        "book.fill",
        "checkmark.shield.fill",
        "pawprint.fill",
        "figure.run.circle.fill",
        "desktopcomputer"
    ]
    
    let columns = Array(repeating: GridItem(.flexible()), count: 4)
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(icons, id: \.self) { icon in
                Circle()
                    .fill(icon == selectedIcon ? Color.accentColor.opacity(0.2) : Color.clear)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: icon)
                            .foregroundColor(icon == selectedIcon ? .accentColor : .primary)
                    }
                    .onTapGesture {
                        selectedIcon = icon
                    }
            }
        }
        .padding(.vertical)
    }
}

// CategoryGridCell implementation
struct CategoryGridCell: View {
    let category: Category
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    private var categoryColor: Color {
        if category.type == "income" {
            return .green
        } else {
            return .blue
        }
    }
    
    private var categoryIcon: String {
        // First check if it's a custom category with a saved icon
        if category.isCustom, let savedIcon = category.icon {
            return savedIcon
        }
        
        // Default icons if name doesn't match any case
        let defaultIncomeIcon = "dollarsign.circle.fill"
        let defaultExpenseIcon = "cart.fill"
        
        guard let name = category.name?.lowercased() else {
            return category.type == "income" ? defaultIncomeIcon : defaultExpenseIcon
        }
        
        // Income categories
        if category.type == "income" {
            if name.contains("salary") || name.contains("wage") {
                return "briefcase.fill"
            } else if name.contains("investment") || name.contains("dividend") {
                return "chart.line.uptrend.xyaxis.circle.fill"
            } else if name.contains("gift") {
                return "gift.fill"
            } else if name.contains("rental") {
                return "house.fill"
            } else if name.contains("business") {
                return "building.2.fill"
            }
            return defaultIncomeIcon
        }
        // Expense categories
        else {
            switch true {
            case name.contains("food") || name.contains("grocery") || name.contains("restaurant"):
                return "fork.knife.circle.fill"
            case name.contains("transport") || name.contains("travel"):
                return "car.fill"
            case name.contains("shopping") || name.contains("cloth"):
                return "bag.fill"
            case name.contains("health") || name.contains("medical"):
                return "cross.case.fill"
            case name.contains("bill") || name.contains("utility"):
                return "doc.text.fill"
            case name.contains("entertainment") || name.contains("fun"):
                return "tv.fill"
            case name.contains("education") || name.contains("school"):
                return "book.fill"
            case name.contains("home") || name.contains("rent"):
                return "house.fill"
            case name.contains("insurance"):
                return "checkmark.shield.fill"
            case name.contains("pet"):
                return "pawprint.fill"
            case name.contains("fitness") || name.contains("sport"):
                return "figure.run.circle.fill"
            case name.contains("tech") || name.contains("gadget"):
                return "desktopcomputer"
            default:
                return defaultExpenseIcon
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(categoryColor.opacity(0.15))
                .frame(width: 50, height: 50)
                .overlay {
                    Image(systemName: categoryIcon)
                        .foregroundColor(categoryColor)
                        .font(.system(size: 24))
                }
            
            Text(category.name ?? "")
                .font(selectedFont.font(size: 16, bold: true))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            if let transactionCount = category.transactions?.count {
                Text("\(transactionCount) transactions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(.systemGray3), lineWidth: 0.5)
        )
    }
}

// MARK: - Performance Optimization Extensions
extension List {
    func optimizedList() -> some View {
        self
            .listStyle(PlainListStyle())
            .background(Color.clear)
    }
}

extension LazyVStack {
    func optimizedLazyStack() -> some View {
        self
            .background(Color.clear)
    }
} 