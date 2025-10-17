import SwiftUI
import CoreData

struct SavingsDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @AppStorage("isDemoEnabled") private var isDemoEnabled = false
    @State private var selectedTimeframe: TimeFrame = .month
    
    enum TimeFrame: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    Picker("Timeframe", selection: $selectedTimeframe) {
                        ForEach(TimeFrame.allCases, id: \.self) { timeframe in
                            Text(timeframe.rawValue).tag(timeframe)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    VStack(spacing: 16) {
                        Text("Current Savings Rate")
                            .font(selectedFont.font(size: 14))
                            .foregroundColor(.secondary)
                        
                        Text("\(calculateSavingsRate(), specifier: "%.1f")%")
                            .font(selectedFont.font(size: 40, bold: true))
                            .foregroundColor(.green)

                        if let trend = calculateTrend() {
                            HStack {
                                Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                                Text("\(abs(trend), specifier: "%.1f")% from previous \(selectedTimeframe.rawValue.lowercased())")
                            }
                            .font(selectedFont.font(size: 14))
                            .foregroundColor(trend >= 0 ? .green : .red)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(trend >= 0 ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            )
                        }
                    }
                    .padding(24)
                    .background(Color.black)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.05), radius: 10)
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Savings Trend")
                            .font(selectedFont.font(size: 18, bold: true))
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        SavingsGraphView(
                            timeframe: selectedTimeframe,
                            transactions: fetchTransactions(),
                            isDemoEnabled: isDemoEnabled
                        )
                        .frame(height: 200)
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                    .background(Color.black)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.05), radius: 10)
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Insights")
                            .font(selectedFont.font(size: 18, bold: true))
                            .foregroundColor(.white)
                        
                        ForEach(getSavingsInsights(), id: \.self) { insight in
                            HStack(spacing: 12) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.yellow)
                                Text(insight)
                                    .font(selectedFont.font(size: 14))
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(Color.black)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.05), radius: 10)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color.black)
            .navigationTitle("Savings Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .foregroundColor(.white)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func calculateSavingsRate() -> Double {
        let income = totalIncome()
        guard income > 0 else { return 0 }
        return ((income - totalExpenses()) / income) * 100
    }
    
    private func totalIncome() -> Double {
        let transactions = fetchTransactions()
        return transactions.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount }
    }
    
    private func totalExpenses() -> Double {
        let transactions = fetchTransactions()
        return transactions.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
    }
    
    private func fetchTransactions() -> [Transaction] {
        let request = Transaction.fetchRequest()
        let calendar = Calendar.current
        
        let startDate: Date
        switch selectedTimeframe {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        case .year:
            startDate = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        }
        
        // Create a compound predicate to filter by both date and account
        let datePredicate = NSPredicate(format: "date >= %@", startDate as NSDate)
        let accountPredicate = NSPredicate(format: "account == %@", AccountManager.shared.currentAccount ?? NSNull())
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, accountPredicate])
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: true)]
        
        let allTransactions = (try? viewContext.fetch(request)) ?? []
        
        // Filter demo transactions based on demo mode setting
        return allTransactions.filter { transaction in
            return isDemoEnabled || !transaction.isDemo
        }
    }
    
    private func getSavingsInsights() -> [String] {
        let savingsRate = calculateSavingsRate()
        var insights: [String] = []
        
        if savingsRate > 20 {
            insights.append("Great job! You're saving more than 20% of your income.")
        } else if savingsRate > 0 {
            insights.append("You're on the right track with positive savings.")
        } else {
            insights.append("Consider reducing expenses to improve savings.")
        }
        
        if let topExpense = getTopExpenseCategory() {
            insights.append("Your highest spending category is \(topExpense).")
        }
        
        return insights
    }
    
    private func getTopExpenseCategory() -> String? {
        let transactions = fetchTransactions().filter { $0.isExpense }
        let categorySum = Dictionary(grouping: transactions) { $0.category?.name ?? "Uncategorized" }
            .mapValues { transactions in
                transactions.reduce(0) { $0 + $1.amount }
            }
        return categorySum.max(by: { $0.value < $1.value })?.key
    }
    
    private func calculateTrend() -> Double? {
        let currentRate = calculateSavingsRate()
        let previousTransactions = fetchPreviousPeriodTransactions()
        let previousIncome = previousTransactions.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount }
        let previousExpenses = previousTransactions.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
        
        guard previousIncome > 0 else { return nil }
        let previousRate = ((previousIncome - previousExpenses) / previousIncome) * 100
        return currentRate - previousRate
    }
    
    private func fetchPreviousPeriodTransactions() -> [Transaction] {
        let request = Transaction.fetchRequest()
        let calendar = Calendar.current
        
        let endDate: Date
        let startDate: Date
        
        switch selectedTimeframe {
        case .week:
            endDate = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            startDate = calendar.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        case .month:
            endDate = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            startDate = calendar.date(byAdding: .month, value: -2, to: Date()) ?? Date()
        case .year:
            endDate = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
            startDate = calendar.date(byAdding: .year, value: -2, to: Date()) ?? Date()
        }
        
        // Create a compound predicate to filter by both date range and account
        let datePredicate = NSPredicate(format: "date >= %@ AND date < %@", startDate as NSDate, endDate as NSDate)
        let accountPredicate = NSPredicate(format: "account == %@", AccountManager.shared.currentAccount ?? NSNull())
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, accountPredicate])
        
        let allTransactions = (try? viewContext.fetch(request)) ?? []
        
        // Filter demo transactions based on demo mode setting
        return allTransactions.filter { transaction in
            return isDemoEnabled || !transaction.isDemo
        }
    }
}

struct SavingsGraphView: View {
    let timeframe: SavingsDetailView.TimeFrame
    let transactions: [Transaction]
    let isDemoEnabled: Bool
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    
    private var dataPoints: [(Date, Double)] {
        let calendar = Calendar.current
        
        // Filter out demo transactions if demo mode is disabled
        let filteredTransactions = transactions.filter { transaction in
            isDemoEnabled || (!(transaction.note ?? "").contains("[DEMO]") && !transaction.isDemo)
        }
        
        let grouped = Dictionary(grouping: filteredTransactions) { transaction in
            switch timeframe {
            case .week:
                return calendar.startOfDay(for: transaction.date ?? Date())
            case .month:
                return calendar.date(from: calendar.dateComponents([.year, .month, .day], from: transaction.date ?? Date())) ?? Date()
            case .year:
                return calendar.date(from: calendar.dateComponents([.year, .month], from: transaction.date ?? Date())) ?? Date()
            }
        }
        
        let sortedDates = grouped.keys.sorted()
        var runningBalance: Double = 0
        
        return sortedDates.map { date in
            let dailyTransactions = grouped[date] ?? []
            let income = dailyTransactions.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount }
            let expenses = dailyTransactions.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
            runningBalance += (income - expenses)
            return (date, runningBalance)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            GeometryReader { geometry in
                ZStack {
                    VStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { i in
                            Divider()
                                .background(Color.gray.opacity(0.2))
                            if i < 4 {
                                Spacer()
                            }
                        }
                    }
                    
                    if !dataPoints.isEmpty {
                        Path { path in
                            let maxBalance = dataPoints.map { $0.1 }.max() ?? 0
                            let minBalance = dataPoints.map { $0.1 }.min() ?? 0
                            let range = max(abs(maxBalance - minBalance), 1)
                            
                            let xStep = geometry.size.width / CGFloat(max(dataPoints.count - 1, 1))
                            let yScale = geometry.size.height / CGFloat(range)
                            
                            path.move(to: CGPoint(
                                x: 0,
                                y: geometry.size.height - CGFloat(dataPoints[0].1 - minBalance) * yScale
                            ))
                            
                            for i in 1..<dataPoints.count {
                                path.addLine(to: CGPoint(
                                    x: CGFloat(i) * xStep,
                                    y: geometry.size.height - CGFloat(dataPoints[i].1 - minBalance) * yScale
                                ))
                            }
                        }
                        .stroke(
                            LinearGradient(
                                colors: [.green.opacity(0.8), .blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                        
                        ForEach(dataPoints.indices, id: \.self) { i in
                            let maxBalance = dataPoints.map { $0.1 }.max() ?? 0
                            let minBalance = dataPoints.map { $0.1 }.min() ?? 0
                            let range = max(abs(maxBalance - minBalance), 1)
                            let xStep = geometry.size.width / CGFloat(max(dataPoints.count - 1, 1))
                            let yScale = geometry.size.height / CGFloat(range)
                            
                            Circle()
                                .fill(Color.white)
                                .frame(width: 8, height: 8)
                                .overlay(
                                    Circle()
                                        .stroke(Color.green, lineWidth: 2)
                                )
                                .position(
                                    x: CGFloat(i) * xStep,
                                    y: geometry.size.height - CGFloat(dataPoints[i].1 - minBalance) * yScale
                                )
                                .overlay(
                                    VStack {
                                        if i == dataPoints.count - 1 || i == 0 || i == dataPoints.count/2 {
                                            Text(CurrencyFormatter.format(dataPoints[i].1, currency: selectedCurrency))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .padding(4)
                                                .background(Color(.systemBackground))
                                                .cornerRadius(4)
                                        }
                                    }
                                    .offset(y: -20)
                                )
                        }
                    }
                }
            }
            
            HStack {
                ForEach(Array(dataPoints.enumerated()), id: \.offset) { index, point in
                    if index == 0 || index == dataPoints.count - 1 || index == dataPoints.count/2 {
                        Text(formatDate(point.0))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if index < dataPoints.count - 1 {
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch timeframe {
        case .week:
            formatter.dateFormat = "EEE"
        case .month:
            formatter.dateFormat = "d MMM"
        case .year:
            formatter.dateFormat = "MMM"
        }
        return formatter.string(from: date)
    }
}
