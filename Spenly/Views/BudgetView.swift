import SwiftUI
import UserNotifications
import CoreData

struct BudgetView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var accountManager: AccountManager
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd

    @FetchRequest(
        entity: Transaction.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)],
        animation: .default
    ) private var allTransactions: FetchedResults<Transaction>

    @FetchRequest(
        entity: Category.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
    ) private var allCategories: FetchedResults<Category>

    @State private var showingEditBudget = false
    @State private var budgetInput: String = ""
    // Search & Filter
    @State private var searchText: String = ""
    @State private var showingFilterSheet = false
    @State private var selectedFilterCategoryName: String? = nil
    @State private var editingTransaction: Transaction? = nil
    // Per-category budgets
    @State private var showingCategoryBudgets = false
    @State private var categoryBudgetInput: String = ""
    @State private var selectedCategoryForBudget: String? = nil
    @State private var refreshCategoryBudgets = UUID()
    @State private var showDeleteConfirm = false
    // Overall budget period (monthly only)
    enum BudgetPeriod: String { case monthly }
    @State private var editingPeriod: BudgetPeriod = .monthly
    @State private var editingStart = Date()
    @State private var editingEnd = Date()
    @State private var refreshOverall = UUID()
    @State private var showMedalInfo = false
    @State private var showMedalInfoSheet = false
    @State private var completionCount: Int = 0 // total (overall + categories) for medals
    @State private var overallCompletions: Int = 0
    @State private var categoryCompletions: Int = 0
    @StateObject private var medalManager = MedalManager.shared
    @State private var showDeleteExceededSheet = false
    @State private var toDeleteExceeded: Set<String> = []

    // MARK: - Derived Data
    private var currentAccountId: UUID? {
        accountManager.currentAccount?.id
    }

    private var monthKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMM"
        return formatter.string(from: Date())
    }
    private func monthKey(from date: Date) -> String { let f = DateFormatter(); f.dateFormat = "yyyyMM"; return f.string(from: date) }
    private func currentPeriodKey() -> String { monthKey(from: Date()) }

    // Active budget period stored per account
    private var activePeriod: BudgetPeriod { .monthly }

    private func setActivePeriod(_ p: BudgetPeriod) { /* monthly only */ }

    private func periodStartKey(_ p: BudgetPeriod) -> String { "budget_period_start_\(currentAccountId?.uuidString ?? "")_\(p.rawValue)" }
    private func periodEndKey(_ p: BudgetPeriod) -> String { "budget_period_end_\(currentAccountId?.uuidString ?? "")_\(p.rawValue)" }

    private var activeBudgetLimit: Double {
        guard let id = currentAccountId else { return 0 }
        return UserDefaults.standard.double(forKey: "budget_limit_\(id.uuidString)")
    }

    private func setBudgetLimit(_ value: Double, period: BudgetPeriod) {
        guard let id = currentAccountId else { return }
        UserDefaults.standard.set(value, forKey: "budget_limit_\(id.uuidString)")
        setActivePeriod(period)
    }

    private func clearBudgetLimit(period: BudgetPeriod) {
        guard let id = currentAccountId else { return }
        UserDefaults.standard.removeObject(forKey: "budget_limit_\(id.uuidString)")
        UserDefaults.standard.removeObject(forKey: periodStartKey(period))
        UserDefaults.standard.removeObject(forKey: periodEndKey(period))
    }

    private var periodStartEnd: (Date, Date)? {
        let cal = Calendar.current
        // use stored custom start/end if present
        if let s = UserDefaults.standard.object(forKey: periodStartKey(activePeriod)) as? Date,
           let e = UserDefaults.standard.object(forKey: periodEndKey(activePeriod)) as? Date {
            return (s, e)
        }
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: Date())),
              let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) else { return nil }
        return (start, end)
    }

    private var periodExpenses: Double {
        guard let account = accountManager.currentAccount, let (start, end) = periodStartEnd else { return 0 }
        return allTransactions.compactMap { t -> Double? in
            guard let d = t.date,
                  t.account == account,
                  t.isExpense,
                  !t.isCarryOver,
                  d >= start && d <= end else { return nil }
            return t.amount
        }.reduce(0, +)
    }

    private var progress: Double { // 0...1
        guard activeBudgetLimit > 0 else { return 0 }
        return min(1, periodExpenses / activeBudgetLimit)
    }

    private var remaining: Double {
        max(0, activeBudgetLimit - periodExpenses)
    }

    private var remainingDays: Int {
        max(1, periodDaysTotal - periodDaysElapsed + 1)
    }

    private var safeToSpendToday: Double {
        remainingDays > 0 ? remaining / Double(remainingDays) : 0
    }

    // Removed streak computations to reduce overhead; can be reintroduced period-aware if needed

    private var insights: [String] {
        var tips: [String] = []
        if projectedMonthEndSpend > activeBudgetLimit && activeBudgetLimit > 0 {
            tips.append("You're trending over budget. Consider lowering non-essential spend this month.")
        } else if activeBudgetLimit > 0 {
            tips.append("You're on track to finish within budget. Keep the pace!")
        }
        let overs = topExpenseCategories.filter { getCategoryBudget($0.name) > 0 && $0.amount > getCategoryBudget($0.name) }
        if let firstOver = overs.first {
            tips.append("Category ‘\(firstOver.name)’ exceeded its limit. Review or adjust its budget.")
        }
        // Streak tip removed to avoid stale computations
        if tips.isEmpty { tips.append("Set category budgets to get sharper guidance.") }
        return tips
    }

    private var monthStartEnd: (Date, Date)? {
        let calendar = Calendar.current
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())),
              let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) else { return nil }
        return (start, end)
    }

    private var periodDaysElapsed: Int {
        let cal = Calendar.current
        guard let (start, _) = periodStartEnd else { return 0 }
        return max(1, cal.dateComponents([.day], from: start, to: Date()).day! + 1)
    }

    private var periodDaysTotal: Int {
        let cal = Calendar.current
        guard let (start, _) = periodStartEnd else { return 7 }
        guard let range = cal.range(of: .day, in: .month, for: start) else { return 30 }
        return range.count
    }

    private var recommendedSpendToDate: Double { // linear pace
        guard activeBudgetLimit > 0 else { return 0 }
        return activeBudgetLimit * Double(periodDaysElapsed) / Double(periodDaysTotal)
    }

    private var projectedMonthEndSpend: Double {
        guard periodExpenses > 0 else { return 0 }
        return periodExpenses / Double(periodDaysElapsed) * Double(periodDaysTotal)
    }

    private var topExpenseCategories: [(name: String, amount: Double)] {
        guard let account = accountManager.currentAccount, let (start, end) = monthStartEnd else { return [] }
        let expenses = allTransactions.filter { t in
            guard let d = t.date else { return false }
            return t.account == account && t.isExpense && !t.isCarryOver && d >= start && d <= end
        }
        let dict = Dictionary(grouping: expenses) { $0.category?.name ?? "Uncategorized" }
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        return dict.sorted { $0.value > $1.value }.prefix(3).map { ($0.key, $0.value) }
    }

    // Prefer ID-based keys; fallback to name-based for backward compatibility
    private func categoryUUID(for name: String) -> UUID? {
        allCategories.first { $0.name == name }?.id
    }
    private func categoryBudgetKey(categoryName: String) -> String {
        guard let accountId = currentAccountId else { return "" }
        if let cid = categoryUUID(for: categoryName) {
            return "budget_limit_cat_\(accountId.uuidString)_id_\(cid.uuidString)"
        }
        return "budget_limit_cat_\(accountId.uuidString)_\(categoryName)"
    }

    private func getCategoryBudget(_ categoryName: String) -> Double {
        // Try ID-based first
        if let accountId = currentAccountId, let cid = categoryUUID(for: categoryName) {
            let idKey = "budget_limit_cat_\(accountId.uuidString)_id_\(cid.uuidString)"
            let v = UserDefaults.standard.double(forKey: idKey)
            if v > 0 { return v }
        }
        // Fallback to legacy name-based
        return UserDefaults.standard.double(forKey: categoryBudgetKey(categoryName: categoryName))
    }

    private func setCategoryBudget(_ categoryName: String, value: Double) {
        if let accountId = currentAccountId, let cid = categoryUUID(for: categoryName) {
            let idKey = "budget_limit_cat_\(accountId.uuidString)_id_\(cid.uuidString)"
            UserDefaults.standard.set(value, forKey: idKey)
            // Optional: clear legacy name key to avoid divergence
            let legacy = "budget_limit_cat_\(accountId.uuidString)_\(categoryName)"
            UserDefaults.standard.removeObject(forKey: legacy)
        } else {
            UserDefaults.standard.set(value, forKey: categoryBudgetKey(categoryName: categoryName))
        }
    }

    private var monthCategoryTotals: [String: Double] {
        Dictionary(uniqueKeysWithValues: topExpenseCategories.map { ($0.name, $0.amount) })
    }

    private var expenseCategoryNames: [String] {
        allCategories.compactMap { cat in
            let type = (cat.type ?? "").lowercased()
            if type == "expense", let name = cat.name { return name }
            return nil
        }.sorted()
    }

    private var monthExpenseTransactions: [Transaction] {
        guard let account = accountManager.currentAccount, let (start, end) = monthStartEnd else { return [] }
        return allTransactions.compactMap { t -> Transaction? in
            guard let d = t.date, t.account == account, t.isExpense, !t.isCarryOver, d >= start && d <= end else { return nil }
            // Search filter
            if !searchText.isEmpty {
                let hay = "\(t.category?.name ?? "") \(t.note ?? "")".lowercased()
                if !hay.contains(searchText.lowercased()) { return nil }
            }
            // Category filter
            if let cname = selectedFilterCategoryName {
                if (t.category?.name ?? "") != cname { return nil }
            }
            return t
        }
        .sorted { ($0.date ?? Date()) > ($1.date ?? Date()) }
    }

    // MARK: - Notifications
    private func notifyIfNeeded() {
        guard activeBudgetLimit > 0, let id = currentAccountId else { return }
        let thresholds: [Int] = [100, 80, 50]
        let pct = Int((progress * 100).rounded())
        let pKey = currentPeriodKey()
        let periodText = "month"

        if let t = thresholds.first(where: { pct >= $0 && !UserDefaults.standard.bool(forKey: "budget_notified_\(id.uuidString)_\(pKey)_\($0)") }) {
            let flagKey = "budget_notified_\(id.uuidString)_\(pKey)_\(t)"
            scheduleImmediate(title: "Budget Update",
                              body: t == 100 ? "You've fully used this \(periodText)'s budget." : "You've reached \(t)% of this \(periodText)'s budget.")
            UserDefaults.standard.set(true, forKey: flagKey)
        }

        // Per-category notifications (period-aware per category period)
        for name in expenseCategoryNames {
            let limit = getCategoryBudget(name)
            guard limit > 0 else { continue }
            let spent = spentForCategory(name)
            let catPct = Int(min(100, (spent / limit * 100)).rounded())
            let cp = categoryActivePeriod(name)
            let cEnd = categoryPeriodEnd(name, cp)
            let cKey = monthKey(from: cEnd)
            if let t = thresholds.first(where: { catPct >= $0 && !UserDefaults.standard.bool(forKey: "budget_cat_notified_\(id.uuidString)_\(cKey)_\(name)_\($0)") }) {
                let flagKey = "budget_cat_notified_\(id.uuidString)_\(cKey)_\(name)_\(t)"
                scheduleImmediate(title: "\(name) budget",
                                  body: t == 100 ? "You've fully used the budget for \(name)." : "You've reached \(t)% of \(name) budget.")
                UserDefaults.standard.set(true, forKey: flagKey)
            }
        }
    }

    private func scheduleImmediate(title: String, body: String) {
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

    // Reset monthly flags at month change (simple guard on appear each launch)
    private func ensureMonthFlagsInitialized() {
        guard let id = currentAccountId else { return }
        let key = currentPeriodKey()
        let base = "budget_notified_\(id.uuidString)_\(key)_"
        [50, 80, 100].forEach { _ in _ = base }
    }

    // MARK: - UI
    var body: some View {
        NavigationView {
            ScrollView {
                mainSections
                .padding()
                .foregroundColor(.white)
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
            .navigationTitle("Budget")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Group {
                        if let m = medalManager.currentMedal(for: currentAccountId) {
                            Image(systemName: m.name)
                                .foregroundColor(m.color)
                                .font(.system(size: 18, weight: .bold))
                        }
                    }
                }
            }
        }
        .onAppear {
            ensureMonthFlagsInitialized()
            budgetInput = activeBudgetLimit > 0 ? String(format: "%.2f", activeBudgetLimit) : ""
            notifyIfNeeded()
            overallCompletions = loadOverallCompletionCount()
            categoryCompletions = loadCategoryCompletionCount()
            completionCount = overallCompletions + categoryCompletions
            checkAndRecordCompletion(for: .monthly)
            checkAndRecordCategoryCompletions()
            medalManager.refresh(for: currentAccountId)
        }
        .onChange(of: allTransactions.count) { _ in
            // Re-evaluate on transaction changes
            notifyIfNeeded()
            refreshOverall = UUID()
            // Update completions if a period just finished
            overallCompletions = loadOverallCompletionCount()
            categoryCompletions = loadCategoryCompletionCount()
            completionCount = overallCompletions + categoryCompletions
            checkAndRecordCompletion(for: .monthly)
            checkAndRecordCategoryCompletions()
            medalManager.refresh(for: currentAccountId)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MedalProgressUpdated"))) { _ in
            // keep toolbar medal synced
            medalManager.refresh(for: currentAccountId)
        }
        .sheet(isPresented: $showingEditBudget) {
            editBudgetSheet
        }
        // Removed transactions sheet and filter per request
        .sheet(isPresented: $showingCategoryBudgets) {
            categoryBudgetSheet
        }
        .preferredColorScheme(.dark)
        .accentColor(themeManager.getAccentColor(for: colorScheme))
        .sheet(isPresented: $showDeleteExceededSheet) {
            NavigationView {
                List {
                    ForEach(Array(exceededCategoryNames), id: \.self) { name in
                        HStack {
                            Image(systemName: iconForCategory(name))
                            Text(name)
                            Spacer()
                            if toDeleteExceeded.contains(name) {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.red)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if toDeleteExceeded.contains(name) { toDeleteExceeded.remove(name) } else { toDeleteExceeded.insert(name) }
                        }
                    }
                }
                .navigationTitle("Delete Budgets")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { showDeleteExceededSheet = false } }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Delete") {
                            for name in toDeleteExceeded {
                                let key = categoryBudgetKey(categoryName: name)
                                UserDefaults.standard.removeObject(forKey: key)
                            }
                            showDeleteExceededSheet = false
                            refreshCategoryBudgets = UUID()
                            refreshOverall = UUID()
                        }.foregroundColor(.red).disabled(toDeleteExceeded.isEmpty)
                    }
                }
            }
        }
    }

    private var mainSections: some View {
        VStack(spacing: 20) {
            // Progress Card
            ZStack(alignment: .leading) { GlassCard(); progressHeader.padding() }

            badgesCard
            warningBanner

            paceCard
            categoryBudgetsCard
            summaryCard
            completionsCard
        }
        .id(refreshOverall)
    }

    // MARK: - Exceed Banner
    private var overallExceeded: Bool {
        activeBudgetLimit > 0 && periodExpenses > activeBudgetLimit
    }
    private var exceededCategoryNames: [String] {
        expenseCategoryNames.filter { name in
            let limit = getCategoryBudget(name)
            guard limit > 0 else { return false }
            return spentForCategory(name) > limit
        }
    }

    @ViewBuilder private var warningBanner: some View {
        if overallExceeded || !exceededCategoryNames.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.white)
                    Text(bannerTitle)
                        .font(selectedFont.font(size: 14, bold: true))
                    Spacer()
                }
                Text(bannerDetail)
                    .font(selectedFont.font(size: 12))
                    .foregroundColor(.white.opacity(0.9))

                HStack(spacing: 10) {
                    Button(action: { onIncreaseTapped() }) {
                        Text("Increase")
                            .font(selectedFont.font(size: 13, bold: true))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(10)
                    }
                    Button(action: { onDeleteTapped() }) {
                        Text("Delete")
                            .font(selectedFont.font(size: 13, bold: true))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(10)
                    }
                }
            }
            .padding()
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(0.5))
                    RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial.opacity(0.08))
                }
            )
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
    }

    private var bannerTitle: String {
        if overallExceeded && !exceededCategoryNames.isEmpty {
            return "Budget exceeded: Overall and \(exceededCategoryNames.count) category(ies)"
        } else if overallExceeded {
            return "Budget exceeded: Monthly"
        } else {
            return "Category budgets exceeded: \(exceededCategoryNames.prefix(2).joined(separator: ", "))\(exceededCategoryNames.count > 2 ? ", +\(exceededCategoryNames.count - 2)" : "")"
        }
    }

    private var bannerDetail: String {
        if overallExceeded && !exceededCategoryNames.isEmpty {
            return "Consider increasing or deleting the active budget(s)."
        } else if overallExceeded {
            return "Spent \(CurrencyFormatter.format(periodExpenses - activeBudgetLimit, currency: selectedCurrency)) over the limit."
        } else {
            // show first 3 category overages deltas
            let parts = exceededCategoryNames.prefix(3).compactMap { name -> String? in
                let spent = spentForCategory(name)
                let limit = getCategoryBudget(name)
                guard limit > 0 else { return nil }
                let over = max(0, spent - limit)
                return "\(name): +\(CurrencyFormatter.format(over, currency: selectedCurrency))"
            }
            return parts.joined(separator: " • ")
        }
    }

    private func onIncreaseTapped() {
        if overallExceeded {
            openEdit()
        } else if let first = exceededCategoryNames.first {
            openCategoryBudgetEditor(first)
        }
    }

    private func onDeleteTapped() {
        if overallExceeded {
            clearBudgetLimit(period: activePeriod)
            refreshOverall = UUID()
        } else {
            toDeleteExceeded = Set(exceededCategoryNames)
            showDeleteExceededSheet = true
        }
    }

    private var paceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Budget Pace").font(selectedFont.font(size: 14, bold: true))
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Should Have Spent").font(selectedFont.font(size: 12)).foregroundColor(.secondary)
                    Text(CurrencyFormatter.format(recommendedSpendToDate, currency: selectedCurrency)).font(selectedFont.font(size: 15, bold: true))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Actually Spent").font(selectedFont.font(size: 12)).foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        let over = periodExpenses - recommendedSpendToDate
                        Image(systemName: over > 0 ? "arrow.up.right" : "arrow.down.right").foregroundColor(over > 0 ? .orange : .green)
                        Text(CurrencyFormatter.format(periodExpenses, currency: selectedCurrency)).font(selectedFont.font(size: 15, bold: true)).foregroundColor(over > 0 ? .orange : .green)
                    }
                }
            }
            Divider().overlay(Color.white.opacity(0.08))
            HStack {
                Text("Projection").font(selectedFont.font(size: 12)).foregroundColor(.secondary)
                Spacer()
                Text(CurrencyFormatter.format(projectedMonthEndSpend, currency: selectedCurrency)).font(selectedFont.font(size: 15, bold: true)).foregroundColor(projectedMonthEndSpend > activeBudgetLimit && activeBudgetLimit > 0 ? .red : .white)
            }
        }
        .padding()
        .background(GlassBackgroundView())
        .cornerRadius(12)
    }

    private var topCategoriesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top Categories").font(selectedFont.font(size: 14, bold: true))
            ForEach(topExpenseCategories, id: \.name) { item in
                VStack(spacing: 6) {
                    HStack {
                        Text(item.name).font(selectedFont.font(size: 13)).lineLimit(1)
                        Spacer()
                        Text(CurrencyFormatter.format(item.amount, currency: selectedCurrency)).font(selectedFont.font(size: 13, bold: true))
                    }
                    GeometryReader { geo in
                        let total = max(periodExpenses, 1)
                        let width = geo.size.width * CGFloat(item.amount / total)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08))
                            RoundedRectangle(cornerRadius: 5)
                                .fill(LinearGradient(colors: [themeManager.getAccentColor(for: colorScheme), themeManager.getAccentColor(for: colorScheme).opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(4, width))
                        }
                    }
                    .frame(height: 10)
                }
            }
        }
        .padding()
        .background(GlassBackgroundView())
        .cornerRadius(12)
    }

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Smart Insights").font(selectedFont.font(size: 14, bold: true))
            ForEach(insights, id: \.self) { tip in
                HStack(alignment: .top, spacing: 8) { Image(systemName: "lightbulb.fill").foregroundColor(.yellow); Text(tip).font(selectedFont.font(size: 13)) }
            }
        }
        .padding()
        .background(GlassBackgroundView())
        .cornerRadius(12)
    }

    private var badgesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Budget Medals").font(selectedFont.font(size: 14, bold: true))
                Spacer()
                Button(action: { showMedalInfoSheet = true }) {
                    Image(systemName: "info.circle").foregroundColor(.white)
                }
            }
            let (bronze, silver, gold, perfect) = medalBreakdown(from: completionCount)
            HStack(spacing: 24) {
                MedalView(title: "Bronze", icon: "medal.fill", color: Color(red: 0.8, green: 0.5, blue: 0.2), count: bronze)
                MedalView(title: "Silver", icon: "medal.fill", color: Color(red: 0.75, green: 0.75, blue: 0.78), count: silver)
                MedalView(title: "Gold", icon: "crown.fill", color: Color(red: 1.0, green: 0.84, blue: 0.0), count: gold)
                MedalView(title: "Perfect", icon: "sparkles", color: Color.purple, count: perfect)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
        .background(
            ZStack {
                LinearGradient(colors: [
                    Color.purple.opacity(0.18),
                    Color.blue.opacity(0.18),
                    Color.green.opacity(0.18),
                    Color.cyan.opacity(0.18),
                    Color.indigo.opacity(0.18)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial.opacity(0.06)))
            }
        )
        .cornerRadius(12)
        .overlay {
            if showMedalInfoSheet {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("How medals are earned")
                            .font(selectedFont.font(size: 15, bold: true))
                        Spacer()
                        Button(action: { withAnimation { showMedalInfoSheet = false } }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.white)
                        }
                    }
                    HStack { Circle().fill(Color(red: 0.8, green: 0.5, blue: 0.2)).frame(width: 10, height: 10); Text("Bronze: every 1 budget completion") }
                    HStack { Circle().fill(Color(red: 0.75, green: 0.75, blue: 0.78)).frame(width: 10, height: 10); Text("Silver: every 5 completions") }
                    HStack { Circle().fill(Color(red: 1.0, green: 0.84, blue: 0.0)).frame(width: 10, height: 10); Text("Gold: every 50 completions") }
                    HStack { Circle().fill(Color.purple).frame(width: 10, height: 10); Text("Perfect: every 100 completions") }
                }
                .font(selectedFont.font(size: 12))
                .foregroundColor(.white)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12).fill(Color.black)
                )
                .padding()
                .transition(.opacity)
            }
        }
    }

    // Removed weekly challenge card (monthly only)

    private var categoryBudgetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Category Budgets").font(selectedFont.font(size: 14, bold: true)); Spacer() }
            if expenseCategoryNames.isEmpty {
                Text("No categories found.").font(selectedFont.font(size: 13)).foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(expenseCategoryNames, id: \.self) { name in
                        let amount = spentForCategory(name)
                        let limit = getCategoryBudget(name)
                        let prog = limit > 0 ? max(0, min(1, amount / limit)) : 0
                        CategoryBudgetCard(name: name, icon: iconForCategory(name), spent: amount, limit: limit, progress: prog, currency: selectedCurrency, accent: themeManager.getAccentColor(for: colorScheme))
                            .onTapGesture {
                                openCategoryBudgetEditor(name)
                            }
                    }
                }
            }
        }
        .padding()
        .background(GlassBackgroundView())
        .cornerRadius(12)
        .id(refreshCategoryBudgets)
    }

    // Summary card
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary").font(selectedFont.font(size: 14, bold: true))
            if activeBudgetLimit > 0 {
                if let (s, e) = periodStartEnd {
                    HStack { Text("Period:").foregroundColor(.secondary); Spacer(); Text("\(formattedDate(s)) – \(formattedDate(e))") }
                } else {
                    HStack { Text("Period:").foregroundColor(.secondary); Spacer(); Text("Not set") }
                }
            } else {
                HStack { Text("Period:").foregroundColor(.secondary); Spacer(); Text("Not set") }
            }
            HStack { Text("Limit:").foregroundColor(.secondary); Spacer(); Text(activeBudgetLimit > 0 ? CurrencyFormatter.format(activeBudgetLimit, currency: selectedCurrency) : "Not set") }
            HStack { Text("Spent:").foregroundColor(.secondary); Spacer(); Text(CurrencyFormatter.format(periodExpenses, currency: selectedCurrency)) }
            HStack { Text("Remaining:").foregroundColor(.secondary); Spacer(); Text(CurrencyFormatter.format(remaining, currency: selectedCurrency)) }
            Divider().overlay(Color.white.opacity(0.06))
            // Categories budgets overview
            VStack(alignment: .leading, spacing: 6) {
                Text("Active category budgets").foregroundColor(.secondary).font(.system(size: 12))
                ForEach(expenseCategoryNames, id: \.self) { name in
                    let limit = getCategoryBudget(name)
                    if limit > 0 {
                        let spent = spentForCategory(name)
                        HStack {
                            Text(name).font(.system(size: 12))
                            Spacer()
                            Text("\(CurrencyFormatter.format(spent, currency: selectedCurrency)) / \(CurrencyFormatter.format(limit, currency: selectedCurrency))")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(GlassBackgroundView())
        .cornerRadius(12)
    }

    // MARK: - Completions card (at the end)
    private var completionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Completions").font(selectedFont.font(size: 14, bold: true))
            HStack {
                Text("Overall (Monthly)").foregroundColor(.secondary).font(.system(size: 12))
                Spacer()
                Text("\(overallCompletions)").font(.system(size: 13, weight: .semibold))
            }
            HStack {
                Text("Category Budgets").foregroundColor(.secondary).font(.system(size: 12))
                Spacer()
                Text("\(categoryCompletions)").font(.system(size: 13, weight: .semibold))
            }
            Divider().overlay(Color.white.opacity(0.06))
            HStack {
                Text("Total (for medals)").foregroundColor(.secondary).font(.system(size: 12))
                Spacer()
                Text("\(completionCount)").font(.system(size: 13, weight: .bold))
                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))
            }
        }
        .padding()
        .background(GlassBackgroundView())
        .cornerRadius(12)
    }

    private func formattedDate(_ d: Date) -> String { let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: d) }

    // Extracted header to simplify type checking
    private var progressHeader: some View {
        HStack(spacing: 18) {
            GradientRingView(progress: progress,
                             baseColor: themeManager.getAccentColor(for: colorScheme),
                             stateColor: progress >= 1 ? .red : (progress >= 0.8 ? .orange : .green))
                .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Budget")
                        .font(selectedFont.font(size: 14, bold: true))
                    Spacer()
                    Button("Edit") { openEdit() }
                        .font(selectedFont.font(size: 14, bold: true))
                }

                Text(activeBudgetLimit > 0 ? CurrencyFormatter.format(activeBudgetLimit, currency: selectedCurrency) : "Not set")
                    .font(selectedFont.font(size: 16))

                if activeBudgetLimit > 0 {
                    HStack(spacing: 10) {
                        ChipView(text: "Spent: \(CurrencyFormatter.format(periodExpenses, currency: selectedCurrency))", color: .white.opacity(0.12))
                        ChipView(text: "Left: \(CurrencyFormatter.format(remaining, currency: selectedCurrency))", color: (progress >= 1 ? Color.red.opacity(0.12) : Color.white.opacity(0.12)))
                    }
                    HStack(spacing: 10) {
                        ChipView(text: "Safe today: \(CurrencyFormatter.format(safeToSpendToday, currency: selectedCurrency))", color: .white.opacity(0.08))
                        ChipView(text: "Monthly", color: .white.opacity(0.08))
                    }
                } else {
                    HStack(spacing: 10) {
                        ChipView(text: "No budget set", color: .white.opacity(0.08))
                    }
                }
            }
        }
    }

    private func iconForCategory(_ name: String) -> String {
        let match = allCategories.first { $0.name == name }
        return match?.icon ?? "square.grid.2x2"
    }

    // MARK: - Edit Budget
    private var editBudgetFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        return f
    }

    @ViewBuilder private var editBudgetSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Set Budget")
                    .font(selectedFont.font(size: 18, bold: true))
                // Monthly-only UI
                Text("Period: Monthly")
                    .font(selectedFont.font(size: 14))
                .disabled(false)
                .onChange(of: editingPeriod) { newValue in
                    // Reset to today's default range when switching period
                    editingStart = defaultStart(for: newValue)
                    editingEnd = autoAdjustedEnd(from: editingStart, period: newValue)
                    // Persist immediately so the UI elsewhere reflects the change
                    setActivePeriod(newValue)
                    UserDefaults.standard.set(editingStart, forKey: periodStartKey(newValue))
                    UserDefaults.standard.set(editingEnd, forKey: periodEndKey(newValue))
                    refreshOverall = UUID()
                }

                // Start/End pickers with auto-adjust and anti-backdating guards
                let todayStart = Calendar.current.startOfDay(for: Date())
                DatePicker("Start", selection: Binding(get: {
                    max(editingStart, todayStart)
                }, set: { newStart in
                    // Clamp to today and keep a rolling 1-month window
                    let finalStart = max(newStart, todayStart)
                    let newEnd = autoAdjustedEnd(from: finalStart, period: editingPeriod)
                    editingStart = finalStart
                    editingEnd = max(newEnd, finalStart)
                }), displayedComponents: .date)

                DatePicker("End", selection: Binding(get: {
                    let minEnd = max(todayStart, editingStart)
                    return max(editingEnd, minEnd)
                }, set: { newEnd in
                    // Clamp to >= start and keep rolling 1-month
                    let clampedEnd = max(newEnd, max(todayStart, editingStart))
                    let newStart = autoAdjustedStart(towards: clampedEnd, period: editingPeriod)
                    editingStart = max(newStart, todayStart)
                    editingEnd = max(clampedEnd, editingStart)
                }), displayedComponents: .date)

                TextField("Amount", text: $budgetInput)
                    .keyboardType(.decimalPad)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)

                Spacer()
            }
            .padding()
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { showingEditBudget = false } }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if activeBudgetLimit > 0 { Button("Delete") { clearBudgetLimit(period: editingPeriod); showingEditBudget = false } .foregroundColor(.red) }
                    Button("Save") { saveBudgetPeriod() } .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func openEdit() {
        editingPeriod = activePeriod
        budgetInput = activeBudgetLimit > 0 ? String(format: "%.2f", activeBudgetLimit) : ""
        // preload start/end
        if let (s, _) = periodStartEnd {
            let todayStart = Calendar.current.startOfDay(for: Date())
            // Default to rolling 1-month window from today
            let baseStart = max(s, todayStart)
            editingStart = baseStart
            editingEnd = max(autoAdjustedEnd(from: baseStart, period: editingPeriod), baseStart)
        } else {
            editingStart = Date()
            editingEnd = autoAdjustedEnd(from: editingStart, period: editingPeriod)
        }
        showingEditBudget = true
    }

    private func saveBudgetPeriod() {
        let cleaned = budgetInput.replacingOccurrences(of: ",", with: "")
        if let value = Double(cleaned), value > 0 {
            setBudgetLimit(value, period: editingPeriod)
            // Persist start/end consistent with period
            let todayStart = Calendar.current.startOfDay(for: Date())
            let clampedStart = max(editingStart, todayStart)
            let end = max(autoAdjustedEnd(from: clampedStart, period: editingPeriod), clampedStart)
            let start = clampedStart
            editingStart = start
            editingEnd = end
            UserDefaults.standard.set(start, forKey: periodStartKey(editingPeriod))
            UserDefaults.standard.set(end, forKey: periodEndKey(editingPeriod))
            showingEditBudget = false
            notifyIfNeeded()
            refreshOverall = UUID()
        }
    }

    private func deleteTransaction(_ transaction: Transaction) {
        withAnimation {
            // Respect carry-over logic already handled elsewhere
            // Decrement contact usage if present
            if let contact = transaction.contact {
                ContactManager.shared.decrementUsageCount(contact: contact, context: viewContext)
            }
            viewContext.delete(transaction)
            do {
                try viewContext.save()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("TransactionUpdated"), object: nil)
                }
            } catch {
                print("Error deleting transaction: \(error.localizedDescription)")
            }
        }
    }

    // Removed filter sheet per request

    // Category Budget Editor
    @ViewBuilder private var categoryBudgetSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                let p = categoryActivePeriod(selectedCategoryForBudget)
                // Header with category icon and name
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.08)).frame(width: 44, height: 44)
                        Image(systemName: iconForCategory(selectedCategoryForBudget ?? "")).foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedCategoryForBudget ?? "Category")
                            .font(selectedFont.font(size: 18, bold: true))
                        let spent = spentForCategory(selectedCategoryForBudget)
                        Text("Spent this month: \(CurrencyFormatter.format(spent, currency: selectedCurrency))")
                            .font(selectedFont.font(size: 12))
                            .foregroundColor(.secondary)
                        if let c = selectedCategoryForBudget {
                            let cur = getCategoryBudget(c)
                            if cur > 0 {
                                Text("Current limit: \(CurrencyFormatter.format(cur, currency: selectedCurrency))")
                                    .font(selectedFont.font(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Period selector for category
                // Monthly-only for category budgets
                Text("Period: Monthly")
                    .font(selectedFont.font(size: 14))

                // Start/End pickers with auto duration and anti-backdating guards
                let todayStart = Calendar.current.startOfDay(for: Date())
                let currentStart = categoryPeriodStart(selectedCategoryForBudget, p)

                DatePicker("Start", selection: Binding(get: {
                    max(categoryPeriodStart(selectedCategoryForBudget, p), todayStart)
                }, set: { newStart in
                    // Clamp to today and keep a rolling 1-month window
                    let finalStart = max(newStart, todayStart)
                    let newEnd = autoAdjustedEnd(from: finalStart, period: p)
                    setCategoryPeriod(selectedCategoryForBudget, period: p, start: finalStart, end: max(newEnd, finalStart))
                }), in: todayStart..., displayedComponents: .date)

                DatePicker("End", selection: Binding(get: {
                    let s = categoryPeriodStart(selectedCategoryForBudget, p)
                    let minEnd = max(todayStart, s)
                    return max(categoryPeriodEnd(selectedCategoryForBudget, p), minEnd)
                }, set: { newEnd in
                    // Clamp to >= start and keep rolling 1-month
                    let s = categoryPeriodStart(selectedCategoryForBudget, p)
                    let clampedEnd = max(newEnd, max(todayStart, s))
                    let newStart = autoAdjustedStart(towards: clampedEnd, period: p)
                    let finalStart = max(newStart, todayStart)
                    setCategoryPeriod(selectedCategoryForBudget, period: p, start: finalStart, end: max(clampedEnd, finalStart))
                }), in: max(todayStart, currentStart)..., displayedComponents: .date)

                // Amount field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set monthly budget amount")
                        .font(selectedFont.font(size: 13))
                        .foregroundColor(.secondary)
                    TextField("Amount", text: $categoryBudgetInput)
                        .keyboardType(.decimalPad)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                }

                Spacer()
            }
            .padding()
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { showingCategoryBudgets = false } }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if let c = selectedCategoryForBudget, getCategoryBudget(c) > 0 {
                        Button("Delete") { showDeleteConfirm = true }.foregroundColor(.red)
                    }
                    Button("Save") { saveSelectedCategoryBudget() }
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                }
            }
            .alert("Delete Budget?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { deleteSelectedCategoryBudget() }
            } message: {
                Text("Are you sure you want to remove this category's budget?")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func openCategoryBudgetEditor(_ name: String) {
        selectedCategoryForBudget = name
        let v = getCategoryBudget(name)
        categoryBudgetInput = v > 0 ? String(format: "%.2f", v) : ""
        showingCategoryBudgets = true
    }

    private func saveSelectedCategoryBudget() {
        let cleaned = categoryBudgetInput.replacingOccurrences(of: ",", with: "")
        if let c = selectedCategoryForBudget, let v = Double(cleaned), v > 0 {
            setCategoryBudget(c, value: v)
            showingCategoryBudgets = false
            refreshCategoryBudgets = UUID()
            refreshOverall = UUID()
        }
    }

    private func deleteSelectedCategoryBudget() {
        if let c = selectedCategoryForBudget {
            let key = categoryBudgetKey(categoryName: c)
            UserDefaults.standard.removeObject(forKey: key)
            showingCategoryBudgets = false
            refreshCategoryBudgets = UUID()
            refreshOverall = UUID()
        }
    }

    private func spentForCategory(_ name: String?) -> Double {
        guard let n = name, let account = accountManager.currentAccount else { return 0 }
        let period = categoryActivePeriod(n)
        let s = categoryPeriodStart(n, period)
        let e = categoryPeriodEnd(n, period)
        return allTransactions.compactMap { t -> Double? in
            guard let d = t.date, t.account == account, t.isExpense, !t.isCarryOver, (t.category?.name ?? "") == n, d >= s && d <= e else { return nil }
            return t.amount
        }.reduce(0, +)
    }

    private func autoAdjustedEnd(from start: Date, period: BudgetPeriod) -> Date {
        // Keep a rolling 1-month window (same day next month when possible)
        let cal = Calendar.current
        return cal.date(byAdding: .month, value: 1, to: start) ?? start
    }

    private func autoAdjustedStart(towards end: Date, period: BudgetPeriod) -> Date {
        // Rolling 1-month back from end
        let cal = Calendar.current
        return cal.date(byAdding: .month, value: -1, to: end) ?? end
    }

    private func defaultStart(for period: BudgetPeriod) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    // Category budget period helpers
    private func categoryPeriodKey(_ name: String?, _ kind: String) -> String {
        "budget_cat_\(kind)_\(currentAccountId?.uuidString ?? "")_\(name ?? "")"
    }
    private func categoryActivePeriod(_ name: String?) -> BudgetPeriod { .monthly }
    private func setCategoryActivePeriod(_ name: String?, _ period: BudgetPeriod) {
        UserDefaults.standard.set(period.rawValue, forKey: categoryPeriodKey(name, "period"))
        // Reset to today's default range for the new period
        let s = defaultStart(for: period)
        let e = autoAdjustedEnd(from: s, period: period)
        setCategoryPeriod(name, period: period, start: s, end: e)
    }
    private func categoryPeriodStart(_ name: String?, _ period: BudgetPeriod) -> Date {
        if let d = UserDefaults.standard.object(forKey: categoryPeriodKey(name, "start_\(period.rawValue)")) as? Date { return d }
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }
    private func categoryPeriodEnd(_ name: String?, _ period: BudgetPeriod) -> Date {
        if let d = UserDefaults.standard.object(forKey: categoryPeriodKey(name, "end_\(period.rawValue)")) as? Date { return d }
        return autoAdjustedEnd(from: categoryPeriodStart(name, period), period: period)
    }
    private func setCategoryPeriod(_ name: String?, period: BudgetPeriod, start: Date, end: Date) {
        UserDefaults.standard.set(start, forKey: categoryPeriodKey(name, "start_\(period.rawValue)"))
        UserDefaults.standard.set(end, forKey: categoryPeriodKey(name, "end_\(period.rawValue)"))
        UserDefaults.standard.set(period.rawValue, forKey: categoryPeriodKey(name, "period"))
    }
}

// (Inline medals popup implemented in badgesCard)

// MARK: - Decorative Helpers
private struct GlassCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(
                LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .background(.ultraThinMaterial.opacity(0.02))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 6)
    }
}

private struct GlassBackgroundView: View {
    var body: some View {
        LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .background(.ultraThinMaterial.opacity(0.02))
    }
}

private struct ChipView: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12).fill(color))
    }
}

private struct GradientRingView: View {
    let progress: Double
    let baseColor: Color
    let stateColor: Color
    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 10)
                .fill(baseColor.opacity(0.18))
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                .stroke(
                    AngularGradient(colors: [baseColor, stateColor, baseColor], center: .center),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: stateColor.opacity(0.6), radius: 5, x: 0, y: 0)
            VStack(spacing: 2) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 16, weight: .bold))
                Text("of budget")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Gamified Views
private struct GamifiedBadgeView: View {
    let title: String
    let icon: String
    let achieved: Bool
    var body: some View { EmptyView() }
}

private struct MedalView: View {
    let title: String
    let icon: String
    let color: Color
    let count: Int
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(color.opacity(0.18)).frame(width: 52, height: 52)
                Image(systemName: icon).foregroundColor(color).font(.system(size: 22, weight: .bold))
            }
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
        }
    }
}

private struct BudgetHeatmapView: View {
    let map: [Date: Double]
    let accent: Color
    var body: some View {
        GeometryReader { geo in
            let cal = Calendar.current
            let dates = map.keys.sorted()
            let maxVal = max(map.values.max() ?? 1, 1)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(dates, id: \.self) { d in
                    let v = map[d] ?? 0
                    let op: Double = v == 0 ? 0.05 : min(0.9, max(0.15, v / maxVal))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accent.opacity(op))
                        .frame(height: (geo.size.height - 24) / 5)
                        .overlay(
                            Text("\(cal.component(.day, from: d))")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        )
                }
            }
        }
    }
}

private struct CategoryBudgetCard: View {
    let name: String
    let icon: String
    let spent: Double
    let limit: Double
    let progress: Double
    let currency: Currency
    let accent: Color

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [accent.opacity(0.18), Color.black], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.08)).frame(width: 36, height: 36)
                        Image(systemName: icon).foregroundColor(.white)
                    }
                    Spacer()
                    Text(limit > 0 ? "\(Int(progress * 100))%" : "No limit")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(limit > 0 ? (progress >= 1 ? .red : (progress >= 0.8 ? .orange : .green)) : .secondary)
                }
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 10)
                    .overlay(
                        GeometryReader { geo in
                            Capsule()
                                .fill(LinearGradient(colors: [accent, accent.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(4, geo.size.width * CGFloat(progress)))
                        }
                    )
                HStack {
                    Text(CurrencyFormatter.format(spent, currency: currency))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    if limit > 0 {
                        Text("Limit: \(CurrencyFormatter.format(limit, currency: currency))")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

// MARK: - Medal logic
extension BudgetView {
    // Separate counters: overall (monthly) and category-based. Total = sum for medals.
    private func overallCompletionCountKey() -> String { "budget_overall_completion_count_\(currentAccountId?.uuidString ?? "")" }
    private func categoryCompletionCountKey() -> String { "budget_category_completion_count_\(currentAccountId?.uuidString ?? "")" }
    private func loadOverallCompletionCount() -> Int { UserDefaults.standard.integer(forKey: overallCompletionCountKey()) }
    private func loadCategoryCompletionCount() -> Int { UserDefaults.standard.integer(forKey: categoryCompletionCountKey()) }
    private func setOverallCompletionCount(_ n: Int) { UserDefaults.standard.set(n, forKey: overallCompletionCountKey()) }
    private func setCategoryCompletionCount(_ n: Int) { UserDefaults.standard.set(n, forKey: categoryCompletionCountKey()) }
    private func recordedKey(_ period: BudgetPeriod, _ key: String) -> String { "budget_completion_recorded_\(currentAccountId?.uuidString ?? "")_\(period.rawValue)_\(key)" }
    private func weekKey() -> String { monthKey }

    private func checkAndRecordCompletion(for period: BudgetPeriod) {
        guard let account = accountManager.currentAccount else { return }
        let limit: Double = {
            return UserDefaults.standard.double(forKey: "budget_limit_\(account.id?.uuidString ?? "")")
        }()
        guard limit > 0 else { return }
        let (start, end): (Date, Date) = {
            if let s = UserDefaults.standard.object(forKey: periodStartKey(period)) as? Date,
               let e = UserDefaults.standard.object(forKey: periodEndKey(period)) as? Date { return (s, e) }
            let s = defaultStart(for: period); let e = autoAdjustedEnd(from: s, period: period); return (s, e)
        }()
        // Only record when period ended
        guard Date() > end else { return }
        let spent = allTransactions.compactMap { t -> Double? in
            guard let d = t.date, t.account == account, t.isExpense, !t.isCarryOver, d >= start && d <= end else { return nil }
            return t.amount
        }.reduce(0, +)
        // Do not count exceeded periods as completion
        guard spent <= limit else { return }
        let pKey: String = {
            switch period {
            case .monthly: return monthKey(from: end)
            }
        }()
        let rKey = recordedKey(period, pKey)
        guard !UserDefaults.standard.bool(forKey: rKey) else { return }
        let c = loadOverallCompletionCount() + 1
        setOverallCompletionCount(c)
        UserDefaults.standard.set(true, forKey: rKey)
    }

    private func medalBreakdown(from total: Int) -> (bronze: Int, silver: Int, gold: Int, perfect: Int) {
        var remaining = total
        let perfect = remaining / 100; remaining %= 100
        let gold = remaining / 50; remaining %= 50
        let silver = remaining / 5; remaining %= 5
        let bronze = remaining
        return (bronze, silver, gold, perfect)
    }

    // Category completion recording: count per-category periods completed under limit
    private func checkAndRecordCategoryCompletions() {
        guard let account = accountManager.currentAccount else { return }
        var added = 0
        for name in expenseCategoryNames {
            let limit = getCategoryBudget(name)
            guard limit > 0 else { continue }
            let period = categoryActivePeriod(name)
            let s = categoryPeriodStart(name, period)
            let e = categoryPeriodEnd(name, period)
            // Only record when period ended
            guard Date() > e else { continue }
            // Calculate spent for the period
            let spent = allTransactions.compactMap { t -> Double? in
                guard let d = t.date, t.account == account, t.isExpense, !t.isCarryOver, (t.category?.name ?? "") == name, d >= s && d <= e else { return nil }
                return t.amount
            }.reduce(0, +)
            // success only if not exceeded
            guard spent <= limit else { continue }
            let recKey = "budget_cat_completion_recorded_\(currentAccountId?.uuidString ?? "")_\(name)_\(period.rawValue)_\(dateKey(for: period))"
            if !UserDefaults.standard.bool(forKey: recKey) {
                added += 1
                UserDefaults.standard.set(true, forKey: recKey)
            }
        }
        if added > 0 {
            let total = loadCategoryCompletionCount() + added
            setCategoryCompletionCount(total)
        }
        // Update medals total
        completionCount = loadOverallCompletionCount() + loadCategoryCompletionCount()
    }

    private func dateKey(for period: BudgetPeriod) -> String { monthKey }
}
