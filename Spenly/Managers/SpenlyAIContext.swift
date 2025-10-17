import Foundation
import CoreData

// Transaction creation intent
struct TransactionIntent {
    let shouldCreate: Bool
    let amount: Double?
    let isExpense: Bool
    let note: String?
    let category: String?
}

// System prompt that teaches GPT about Spenly
class SpenlyAIContext {
    
    // Build comprehensive context about Spenly app
    static func buildSystemPrompt(with transactions: [Transaction], currency: Currency, accountId: UUID? = nil, conversationHistory: String = "") -> String {
        let transactionSummary = buildTransactionSummary(transactions: transactions, currency: currency)
        let budgetInfo = buildBudgetInfo(for: accountId, transactions: transactions, currency: currency)
        let templateInfo = buildTemplateInsights(currency: currency)
        
        return """
        You are Spenly AI, an intelligent financial assistant for the Spenly personal finance tracking app.
        
        YOUR CAPABILITIES:
        1. Analyze user's financial data (spending, income, balance, trends)
        2. Help create transactions when user requests
        3. Answer questions about Spenly app features
        4. Provide financial insights and recommendations
        
        SPENLY APP FEATURES (Answer questions about these ONLY):
        • Transaction Tracking: Income & expense tracking with categories, notes, and receipts
        • Multiple Accounts: Users can create separate accounts (Personal, Business, etc.) and switch between them
        • Categories: Organize transactions with custom categories, icons, and colors
        • Budgets: Set monthly spending limits for categories, track progress in real-time
        • Transaction Templates: Quick shortcuts for recurring transactions (Premium feature)
        • Currency Support: 150+ currencies with real-time exchange rates widget
        • Export Data: Export transactions to PDF or CSV format (Premium feature)
        • Receipt Management: Attach photos of receipts to transactions
        • iCloud Sync: Automatic data sync across user's devices
        • Reminders: Set transaction reminders and monthly notifications
        • Themes: Customize app appearance with different themes and colors
        • Premium Features: Ad-free experience, unlimited templates, export capabilities, premium fonts
        • Demo Data: Sample transactions to explore app features
        
        NAVIGATION GUIDANCE:
        • Budget: Bottom tab bar
        • Categories: Settings → Categories
        • Templates: Top right button in Home (template icon)
        • Export: Settings → Export Data
        • Accounts: Profile icon top left in Home
        • Currency: Settings → Currency
        • Theme: Settings → Theme
        • Premium: Settings → Premium (crown icon)
        
        USER'S CURRENT DATA:
        \(transactionSummary)
        
        \(budgetInfo)
        
        \(templateInfo)
        
        CONVERSATION HISTORY:
        \(conversationHistory.isEmpty ? "No previous conversation" : conversationHistory)
        
        CONTEXT AWARENESS RULES:
        • Remember what the user asked in previous messages
        • If user asks for "details" or "more info", refer to their last question
        • If they said "7 expenses today" and ask "give me details", list those 7 expenses with amounts, categories, and notes
        • Use pronouns like "them", "those", "it" to refer to previously mentioned items
        • Don't ask clarifying questions if context is clear from conversation history
        
        TRANSACTION CREATION FORMAT:
        When user asks to add/create/record a transaction, respond with:
        "✅ Creating transaction: [AMOUNT]|[TYPE:expense/income]|[NOTE]|[CATEGORY_HINT]"
        
        NOTE FIELD RULES (IMPORTANT):
        • Extract only the main subject/item, NOT prepositions or articles
        • Remove words like: "for", "in", "on", "at", "to", "from", "with", "a", "an", "the"
        • Keep it clean and simple - just the item/description
        • Capitalize properly
        
        Examples:
        - User: "Add $50 for groceries"
          You: "✅ Creating transaction: 50|expense|Groceries|Food & Dining"
        - User: "Spent $30 on dinner at restaurant"
          You: "✅ Creating transaction: 30|expense|Dinner|Food & Dining"
        - User: "Record $2000 salary income"
          You: "✅ Creating transaction: 2000|income|Salary|Income"
        - User: "Add $100 for gas in car"
          You: "✅ Creating transaction: 100|expense|Gas|Transportation"
        - User: "Paid $45 for movie tickets"
          You: "✅ Creating transaction: 45|expense|Movie Tickets|Entertainment"
        
        RESPONSE GUIDELINES:
        • Be concise but helpful - give direct answers with specific numbers
        • Use emojis appropriately (💰📊✅❓⚠️💡🎯)
        • Always cite ACTUAL numbers from user's data above
        • For budget questions, refer to the BUDGET INFORMATION section
        • Explain trends and insights, not just raw numbers
        • Provide actionable advice when appropriate
        • Compare periods (this month vs last month, this week vs last week)
        • Identify spending patterns and unusual transactions
        • Don't mention features Spenly doesn't have
        • If user asks about unavailable features, suggest alternatives
        • Stay focused on finances - politely redirect off-topic questions
        • Use user's currency: \(currency.symbol)
        • When discussing spending, mention top categories to provide context
        • End responses with relevant follow-up suggestions when helpful
        
        FORMATTING RULES (IMPORTANT):
        • Start with emoji section headers (📊, 💰, 📈, etc.) for main topics
        • Use bullet points (•) for lists and details
        • Add blank lines between different sections
        • Keep paragraphs short (2-3 sentences max)
        • Use clear spacing between numbers and text
        • Format numbers clearly: "\(currency.symbol)1,234" not "1234"
        • Break long responses into organized sections
        • Do NOT use markdown (no **bold**, _italic_, *asterisks*, or backticks). Plain text only with emojis and bullets.
        • Example format:
          
          📊 Your spending this month is \(currency.symbol)500
          
          That's 20% less than last month - great job!
          
          💡 Top categories:
          • Food: \(currency.symbol)200
          • Transport: \(currency.symbol)150
          
          🎯 You're on track to save \(currency.symbol)300 this month!
        
        BUDGET RESPONSES:
        • If asked "how's my budget" - give overall status AND mention any category budgets
        • If budget is exceeded, acknowledge it and suggest specific ways to cut spending in top categories
        • If budget is on track, congratulate and show remaining amount with daily/weekly average
        • Compare current spending to previous trends when helpful
        • Suggest creating budgets if none are set
        
        INSIGHTS TO PROVIDE:
        • Spending trends (increasing/decreasing compared to past)
        • Unusual or large transactions that stand out
        • Days of week with highest spending
        • Recommendations for budget allocation based on actual spending
        • Savings opportunities based on categories
        • Income vs expense ratio and health score
        
        PROACTIVE SUGGESTIONS:
        • If no budget set: "💡 Tip: Setting a budget can help you stay on track. Based on your spending, I'd suggest..."
        • If spending high in category: "⚠️ Notice: Your [category] spending is higher than usual. Consider..."
        • If good financial behavior: "🎯 Great job! You're [positive behavior]. Keep it up by..."
        • If income > expenses: "✅ Positive! You saved [amount] this month. Consider setting a savings goal."
        
        IMPORTANT: Base ALL financial analysis on the user's actual transaction data and budget information provided above. Be conversational, insightful, and genuinely helpful.
        """
    }
    
    // Build summary of user's transactions for context
    private static func buildTransactionSummary(transactions: [Transaction], currency: Currency) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        // Total counts
        let totalExpenses = transactions.filter { $0.isExpense }.count
        let totalIncome = transactions.filter { !$0.isExpense }.count
        
        // This month
        let monthTransactions = transactions.filter { transaction in
            guard let date = transaction.date else { return false }
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        }
        
        let monthExpenses = monthTransactions.filter { $0.isExpense }.reduce(0.0) { $0 + $1.amount }
        let monthIncome = monthTransactions.filter { !$0.isExpense }.reduce(0.0) { $0 + $1.amount }
        
        // Today
        let todayTransactions = transactions.filter { transaction in
            guard let date = transaction.date else { return false }
            return calendar.isDateInToday(date)
        }
        let todayExpenses = todayTransactions.filter { $0.isExpense }.reduce(0.0) { $0 + $1.amount }
        
        // All time totals
        let allExpenses = transactions.filter { $0.isExpense }.reduce(0.0) { $0 + $1.amount }
        let allIncome = transactions.filter { !$0.isExpense }.reduce(0.0) { $0 + $1.amount }
        let allTimeBalance = allIncome - allExpenses
        
        // This month balance
        let monthBalance = monthIncome - monthExpenses
        
        // Largest expense
        let largestExpense = transactions.filter { $0.isExpense }.max(by: { $0.amount < $1.amount })
        let largestExpenseStr = largestExpense.map { 
            "\(currency.symbol)\($0.amount) - \($0.category?.name ?? "Uncategorized") - \($0.note ?? "No note")"
        } ?? "None"
        
        // Top categories this month
        var categoryTotals: [String: Double] = [:]
        for transaction in monthTransactions where transaction.isExpense {
            let categoryName = transaction.category?.name ?? "Uncategorized"
            categoryTotals[categoryName, default: 0] += transaction.amount
        }
        let topCategories = categoryTotals.sorted { $0.value > $1.value }.prefix(3)
            .map { "\($0.key): \(currency.symbol)\($0.value)" }
            .joined(separator: ", ")
        
        // Last month for comparison
        let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: now)!
        let lastMonthTransactions = transactions.filter { transaction in
            guard let date = transaction.date else { return false }
            return calendar.isDate(date, equalTo: lastMonthStart, toGranularity: .month)
        }
        let lastMonthExpenses = lastMonthTransactions.filter { $0.isExpense }.reduce(0.0) { $0 + $1.amount }
        _ = lastMonthTransactions.filter { !$0.isExpense }.reduce(0.0) { $0 + $1.amount }
        
        // This week
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let weekTransactions = transactions.filter { transaction in
            guard let date = transaction.date else { return false }
            return date >= weekStart && date <= now
        }
        let weekExpenses = weekTransactions.filter { $0.isExpense }.reduce(0.0) { $0 + $1.amount }
        
        // Calculate trends
        let monthTrend = lastMonthExpenses > 0 ? ((monthExpenses - lastMonthExpenses) / lastMonthExpenses * 100) : 0
        let trendIndicator = monthExpenses > lastMonthExpenses ? "📈 Up" : monthExpenses < lastMonthExpenses ? "📉 Down" : "➡️ Same"
        
        // Days in month for daily average
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let currentDay = calendar.component(.day, from: now)
        let dailyAverage = currentDay > 0 ? monthExpenses / Double(currentDay) : 0
        
        return """
        IMPORTANT: When user asks for "current balance", they mean THIS MONTH's balance, NOT all-time balance!
        
        📊 FINANCIAL OVERVIEW:
        
        Current Month Balance: \(currency.symbol)\(monthBalance) (Income \(currency.symbol)\(monthIncome) - Expenses \(currency.symbol)\(monthExpenses))
        All-Time Balance: \(currency.symbol)\(allTimeBalance)
        
        📈 SPENDING TRENDS:
        - This Month vs Last Month: \(trendIndicator) \(String(format: "%.1f", abs(monthTrend)))%
        - Last Month Expenses: \(currency.symbol)\(lastMonthExpenses)
        - Daily Average (This Month): \(currency.symbol)\(String(format: "%.2f", dailyAverage))
        - This Week Expenses: \(currency.symbol)\(weekExpenses)
        
        💰 ALL TIME SUMMARY:
        - Total Income: \(currency.symbol)\(allIncome) (\(totalIncome) transactions)
        - Total Expenses: \(currency.symbol)\(allExpenses) (\(totalExpenses) transactions)
        - Largest Ever Expense: \(largestExpenseStr)
        - Net Balance: \(currency.symbol)\(allTimeBalance)
        
        📅 THIS MONTH DETAILS:
        - Income: \(currency.symbol)\(monthIncome)
        - Expenses: \(currency.symbol)\(monthExpenses)
        - Balance: \(currency.symbol)\(monthBalance)
        - Transactions: \(monthTransactions.count)
        - Top Categories: \(topCategories.isEmpty ? "None yet" : topCategories)
        - Days Tracked: \(currentDay) of \(daysInMonth)
        
        📆 TODAY'S TRANSACTIONS (\(todayTransactions.count) total):
        \(buildTodayTransactionList(todayTransactions, currency: currency))
        - Total Expenses Today: \(currency.symbol)\(todayExpenses)
        """
    }
    
    // Build template usage insights
    private static func buildTemplateInsights(currency: Currency) -> String {
        let tm = TemplateManager.shared
        let templates = tm.templates
        let usage = tm.usageStats()
        guard !templates.isEmpty else {
            return "TEMPLATE INSIGHTS:\nNo templates created yet."
        }
        let totalTemplates = templates.count
        var totalUses = 0
        var totalExpenseAmount = 0.0
        var totalIncomeAmount = 0.0
        for (id, stat) in usage {
            _ = id // not used directly here
            totalUses += stat.useCount
            totalExpenseAmount += stat.totalExpenseAmount
            totalIncomeAmount += stat.totalIncomeAmount
        }
        let mostUsed = tm.mostUsedTemplates(limit: 3)
        let topList = mostUsed.map { "• \($0.template.name): \($0.count)x" }.joined(separator: "\n")
        let financeImpact = "Total via templates: Expenses \(currency.symbol)\(totalExpenseAmount), Income \(currency.symbol)\(totalIncomeAmount)"
        var text = "TEMPLATE INSIGHTS:\n"
        text += "- Templates: \(totalTemplates)\n"
        text += "- Uses: \(totalUses)\n"
        text += financeImpact + "\n"
        if !mostUsed.isEmpty {
            text += "Top Templates:\n" + topList + "\n"
        } else {
            text += "Top Templates:\nNone used yet\n"
        }
        return text
    }
    
    // Build today's transaction list for detailed context
    private static func buildTodayTransactionList(_ transactions: [Transaction], currency: Currency) -> String {
        guard !transactions.isEmpty else {
            return "No transactions recorded today yet"
        }
        
        var list = ""
        for (index, transaction) in transactions.enumerated() {
            let type = transaction.isExpense ? "Expense" : "Income"
            let category = transaction.category?.name ?? "Uncategorized"
            let note = transaction.note ?? "No note"
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"
            let time = timeFormatter.string(from: transaction.date ?? Date())
            
            list += "\n\(index + 1). \(type): \(currency.symbol)\(transaction.amount) - \(note) (\(category)) at \(time)"
        }
        
        return list
    }
    
    // Parse GPT response for transaction creation
    static func parseTransactionIntent(from response: String) -> TransactionIntent? {
        // Look for transaction creation format
        guard response.contains("Creating transaction:") else {
            return nil
        }
        
        // Extract the structured part: AMOUNT|TYPE|NOTE|CATEGORY
        let pattern = "Creating transaction:\\s*([0-9.]+)\\|([^|]+)\\|([^|]+)\\|([^|\\n]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)) else {
            return nil
        }
        
        guard let amountRange = Range(match.range(at: 1), in: response),
              let typeRange = Range(match.range(at: 2), in: response),
              let noteRange = Range(match.range(at: 3), in: response),
              let categoryRange = Range(match.range(at: 4), in: response) else {
            return nil
        }
        
        let amountStr = String(response[amountRange])
        let type = String(response[typeRange]).trimmingCharacters(in: .whitespaces)
        let note = String(response[noteRange]).trimmingCharacters(in: .whitespaces)
        let category = String(response[categoryRange]).trimmingCharacters(in: .whitespaces)
        
        guard let amount = Double(amountStr) else {
            return nil
        }
        
        let isExpense = type.lowercased() == "expense"
        
        return TransactionIntent(
            shouldCreate: true,
            amount: amount,
            isExpense: isExpense,
            note: note.isEmpty ? nil : note,
            category: category.isEmpty ? nil : category
        )
    }
    
    // Build budget information
    private static func buildBudgetInfo(for accountId: UUID?, transactions: [Transaction], currency: Currency) -> String {
        guard let accountId = accountId else {
            return "BUDGET INFORMATION:\nNo budget set."
        }
        
        // Get overall monthly budget from UserDefaults
        let overallBudget = UserDefaults.standard.double(forKey: "budget_limit_\(accountId.uuidString)")
        
        // Get current month expenses
        let calendar = Calendar.current
        let now = Date()
        let monthTransactions = transactions.filter { transaction in
            guard let date = transaction.date else { return false }
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        }
        let monthExpenses = monthTransactions.filter { $0.isExpense }.reduce(0.0) { $0 + $1.amount }
        
        var budgetText = "BUDGET INFORMATION:\n"
        
        if overallBudget > 0 {
            let remaining = overallBudget - monthExpenses
            let percentUsed = (monthExpenses / overallBudget) * 100
            let status = percentUsed >= 100 ? "⚠️ EXCEEDED" : percentUsed >= 80 ? "⚠️ HIGH" : "✅ ON TRACK"
            
            budgetText += """
            Overall Monthly Budget: \(currency.symbol)\(overallBudget)
            Spent This Month: \(currency.symbol)\(monthExpenses)
            Remaining: \(currency.symbol)\(remaining)
            Usage: \(String(format: "%.1f", percentUsed))% \(status)
            
            """
        } else {
            budgetText += "Overall Monthly Budget: Not set\n\n"
        }
        
        // Get category budgets
        var categoryBudgets: [(category: String, limit: Double, spent: Double)] = []
        
        // Get all unique categories from transactions
        let uniqueCategories = Set(transactions.compactMap { $0.category })
        
        for category in uniqueCategories {
            guard let categoryName = category.name else { continue }
            
            // Try ID-based key first (new format)
            var categoryLimit: Double = 0
            if let categoryId = category.id {
                let idKey = "budget_limit_cat_\(accountId.uuidString)_id_\(categoryId.uuidString)"
                categoryLimit = UserDefaults.standard.double(forKey: idKey)
            }
            
            // Fallback to name-based key (legacy format)
            if categoryLimit == 0 {
                let nameKey = "budget_limit_cat_\(accountId.uuidString)_\(categoryName)"
                categoryLimit = UserDefaults.standard.double(forKey: nameKey)
            }
            
            if categoryLimit > 0 {
                let categorySpent = monthTransactions
                    .filter { $0.isExpense && $0.category?.name == categoryName }
                    .reduce(0.0) { $0 + $1.amount }
                
                categoryBudgets.append((category: categoryName, limit: categoryLimit, spent: categorySpent))
            }
        }
        
        if !categoryBudgets.isEmpty {
            budgetText += "Category Budgets:\n"
            for budget in categoryBudgets.sorted(by: { $0.category < $1.category }) {
                _ = budget.limit - budget.spent
                let percentUsed = (budget.spent / budget.limit) * 100
                let status = percentUsed >= 100 ? "⚠️ EXCEEDED" : percentUsed >= 80 ? "⚠️ HIGH" : "✅"
                
                budgetText += """
                • \(budget.category): \(currency.symbol)\(budget.spent) / \(currency.symbol)\(budget.limit) (\(String(format: "%.0f", percentUsed))%) \(status)
                
                """
            }
        } else {
            budgetText += "Category Budgets: None set"
        }
        
        return budgetText
    }
}

