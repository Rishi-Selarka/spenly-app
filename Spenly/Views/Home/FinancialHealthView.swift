import SwiftUI
import CoreData

fileprivate enum AnalysisRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"
    var id: String { rawValue }
}

 

final class FinancialHealthAnalysisViewModel: ObservableObject {
    // Cache keyed by range identifier
    private var cacheExpenses: [String: [(Date, Double)]] = [:]
    private var cacheTotals: [String: (income: Double, expense: Double)] = [:]

    fileprivate func key(for range: AnalysisRange) -> String { range.rawValue }

    fileprivate func bucketedExpenses(for range: AnalysisRange, from transactions: [Transaction]) -> [(Date, Double)] {
        let k = key(for: range)
        if let cached = cacheExpenses[k] { return cached }
        let result = Self.computeBucketed(range: range, transactions: transactions)
        cacheExpenses[k] = result
        return result
    }

    fileprivate func totals(for range: AnalysisRange, from transactions: [Transaction]) -> (income: Double, expense: Double) {
        let k = key(for: range)
        if let cached = cacheTotals[k] { return cached }
        let filtered = Self.filter(range: range, transactions: transactions)
        let income = filtered.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount }
        let expense = filtered.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
        let result = (income, expense)
        cacheTotals[k] = result
        return result
    }

    fileprivate static func filter(range: AnalysisRange, transactions: [Transaction]) -> [Transaction] {
        let cal = Calendar.current
        let now = Date()
        let start: Date
        let end: Date
        switch range {
        case .week:
            let startOfWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            start = startOfWeek
            end = cal.date(byAdding: .day, value: 7, to: startOfWeek) ?? now
        case .month:
            let comps = cal.dateComponents([.year, .month], from: now)
            start = cal.date(from: comps) ?? now
            end = cal.date(byAdding: DateComponents(month: 1), to: start) ?? now
        case .year:
            let comps = cal.dateComponents([.year], from: now)
            start = cal.date(from: comps) ?? now
            end = cal.date(byAdding: DateComponents(year: 1), to: start) ?? now
        }
        return transactions.filter { t in
            guard let d = t.date else { return false }
            return d >= start && d < end
        }
    }

    fileprivate static func computeBucketed(range: AnalysisRange, transactions: [Transaction]) -> [(Date, Double)] {
        let filtered = filter(range: range, transactions: transactions)
        let cal = Calendar.current
        let now = Date()
        let start: Date
        let component: Calendar.Component
        let bucketCount: Int
        switch range {
        case .week:
            start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            component = .day
            bucketCount = 7
        case .month:
            start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            component = .day
            bucketCount = (cal.range(of: .day, in: .month, for: now)?.count) ?? 30
        case .year:
            start = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
            component = .month
            bucketCount = 12
        }
        var buckets: [Date: Double] = [:]
        var dates: [Date] = []
        for i in 0..<bucketCount {
            let d = cal.date(byAdding: component, value: i, to: start) ?? start
            let key = component == .day ? cal.startOfDay(for: d) : cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
            dates.append(key)
            buckets[key] = 0
        }
        for t in filtered {
            guard t.isExpense, let date = t.date else { continue }
            let key: Date
            if component == .day {
                key = cal.startOfDay(for: date)
            } else {
                key = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
            }
            if buckets[key] != nil { buckets[key]! += t.amount }
        }
        return dates.map { ($0, buckets[$0] ?? 0) }
    }

    func invalidate() {
        cacheExpenses.removeAll()
        cacheTotals.removeAll()
    }
}

struct FinancialHealthCard: View {
    let transactions: [Transaction]
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system

    private var totalIncome: Double {
        transactions.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount }
    }

    private var totalExpense: Double {
        transactions.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
    }

    private var savingsRate: Double {
        guard totalIncome > 0 else { return 0 }
        return max(0, min(1, (totalIncome - totalExpense) / totalIncome))
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(lineWidth: 7.2)
                    .opacity(0.2)
                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))

                Circle()
                    .trim(from: 0.0, to: CGFloat(savingsRate))
                    .stroke(style: StrokeStyle(lineWidth: 7.2, lineCap: .round, lineJoin: .round))
                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                    .rotationEffect(Angle(degrees: 270))

                Text("\(savingsRate * 100, specifier: "%.0f")%")
                    .font(selectedFont.font(size: 14, bold: true))
            }
            .frame(width: 80, height: 80)

            Text("Financial Health")
                .font(selectedFont.font(size: 16, bold: true))
                .lineLimit(1)
                .multilineTextAlignment(.center)
                
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            themeManager.getAccentColor(for: colorScheme).opacity(0.22),
                            themeManager.getAccentColor(for: colorScheme).opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        )
        .foregroundColor(.white)
    }
}

struct FinancialHealthDetailView: View {
    let transactions: [Transaction]
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system

    @StateObject private var vm = FinancialHealthAnalysisViewModel()

    // Fixed to monthly data only

    private var filteredTransactions: [Transaction] {
        FinancialHealthAnalysisViewModel.filter(range: .month, transactions: transactions)
    }

    private var totalIncome: Double {
        vm.totals(for: .month, from: transactions).income
    }

    private var totalExpense: Double {
        vm.totals(for: .month, from: transactions).expense
    }

    private var savingsRate: Double {
        guard totalIncome > 0 else { return 0 }
        let raw = (totalIncome - totalExpense) / totalIncome
        return max(0, min(1, raw))
    }

    private var noIncome: Bool { totalIncome <= 0 }

    private var timeBucketedExpenses: [(date: Date, expense: Double)] {
        vm.bucketedExpenses(for: .month, from: transactions)
            .map { (date: $0.0, expense: $0.1) }
    }

    private var topSpendingCategories: [(name: String, amount: Double, icon: String, percent: Double)] {
        let expenseTransactions = filteredTransactions.filter { $0.isExpense }
        let categorySpending = Dictionary(grouping: expenseTransactions, by: { $0.category?.name ?? "Uncategorized" })
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        let total = max(categorySpending.values.reduce(0, +), 1)
        let sorted = categorySpending.sorted { lhs, rhs in lhs.value > rhs.value }.prefix(5)
        return sorted.map { (name, amount) in
            let icon = filteredTransactions.first(where: { $0.category?.name == name })?.category?.icon ?? "questionmark.circle"
            return (name: name, amount: amount, icon: icon, percent: amount / total)
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                

                VStack(alignment: .leading, spacing: 20) {
                    // Header with savings ring and quick stats
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        themeManager.getAccentColor(for: colorScheme).opacity(0.35),
                                        Color.black
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 6)

                        HStack(spacing: 32) {
                            ZStack {
                                Circle()
                                    .stroke(lineWidth: 8.4)
                                    .opacity(0.25)
                                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))

                                Circle()
                                    .trim(from: 0.0, to: CGFloat(min(self.savingsRate, 1.0)))
                                    .stroke(style: StrokeStyle(lineWidth: 8.4, lineCap: .round, lineJoin: .round))
                                    .foregroundColor(savingsRate >= 0.2 ? .green : (savingsRate >= 0.1 ? .orange : .red))
                                    .rotationEffect(Angle(degrees: 270.0))
                                    .animation(.easeInOut(duration: 0.3), value: savingsRate)

                                VStack(spacing: 2) {
                                    Text("\(savingsRate * 100, specifier: "%.0f")%")
                                        .font(selectedFont.font(size: 20, bold: true))
                                    Text("Saved")
                                        .font(selectedFont.font(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(width: 110, height: 110)

                            VStack(alignment: .leading, spacing: 12) {
                            if noIncome {
                                Text("No income this month")
                                        .font(selectedFont.font(size: 13))
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Income: \(CurrencyFormatter.format(totalIncome, currency: selectedCurrency))")
                                        .font(selectedFont.font(size: 13))
                                        .foregroundColor(.secondary)
                                    Text("Expenses: \(CurrencyFormatter.format(totalExpense, currency: selectedCurrency))")
                                        .font(selectedFont.font(size: 13))
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .padding()
                    }

                    // Current Month Expense Curve Chart
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Expenses This Month")
                            .font(selectedFont.font(size: 16, bold: true))
                        SmoothExpenseCurve(points: timeBucketedExpenses, accent: themeManager.getAccentColor(for: colorScheme), currency: selectedCurrency)
                            .frame(height: 240)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .transition(.opacity.combined(with: .scale))
                            .animation(.easeInOut(duration: 0.25), value: timeBucketedExpenses.count)
                    }

                    // Enhanced Top Spending
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Top Spending Categories")
                            .font(selectedFont.font(size: 16, bold: true))

                        if topSpendingCategories.isEmpty {
                            Text("No expenses recorded yet.")
                                .font(selectedFont.font(size: 14))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(topSpendingCategories, id: \.name) { category in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        ZStack {
                                            Circle()
                                                .fill(Color.black)
                                                .frame(width: 28, height: 28)
                                            Image(systemName: category.icon)
                                                .font(.system(size: 13))
                                                .foregroundColor(.white)
                                        }

                                        Text(category.name)
                                            .font(selectedFont.font(size: 14))
                                        Spacer()
                                        Text("\(Int(category.percent * 100))%")
                                            .font(selectedFont.font(size: 12, bold: true))
                                            .foregroundColor(.secondary)
                                        Text(CurrencyFormatter.format(category.amount, currency: selectedCurrency))
                                            .font(selectedFont.font(size: 14, bold: true))
                                    }

                                    FinancialThemedGradientBar(progress: category.percent, accent: themeManager.getAccentColor(for: colorScheme))
                                        .frame(height: 10)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.06))
                                )
                                .contentShape(Rectangle())
                            }
                        }
                    }
                }
                .padding()
                .foregroundColor(.white)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Financial Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onChange(of: transactions.count) { _ in vm.invalidate() }
        }
    }
}

// MARK: - Helper Views

private struct SmoothExpenseCurve: View {
    let points: [(date: Date, expense: Double)]
    let accent: Color
    let currency: Currency

    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.locale = Locale.current
        return df
    }

    private func label(for date: Date, count: Int) -> String {
        // Heuristic: if we have 12 points, assume months; if 28-31, days; if 7, weekdays
        switch count {
        case 12:
            let df = dateFormatter
            df.setLocalizedDateFormatFromTemplate("MMM")
            return df.string(from: date)
        case 7:
            let df = dateFormatter
            df.setLocalizedDateFormatFromTemplate("E")
            return df.string(from: date)
        default:
            let df = dateFormatter
            df.setLocalizedDateFormatFromTemplate("d")
            return df.string(from: date)
        }
    }

    private func controlPoints(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint) -> (cp1: CGPoint, cp2: CGPoint) {
        let smoothing: CGFloat = 0.12
        let d01 = hypot(p1.x - p0.x, p1.y - p0.y)
        let d12 = hypot(p2.x - p1.x, p2.y - p1.y)
        let denom = max(d01 + d12, 0.0001)
        let fa = smoothing * d01 / denom
        let fb = smoothing * d12 / denom
        let cp1 = CGPoint(x: p1.x - fa * (p2.x - p0.x), y: p1.y - fa * (p2.y - p0.y))
        let cp2 = CGPoint(x: p1.x + fb * (p2.x - p0.x), y: p1.y + fb * (p2.y - p0.y))
        return (cp1, cp2)
    }

    private func movingAverage(_ values: [Double], window: Int) -> [Double] {
        let window = min(window, max(2, values.count / 6))
        guard window > 1, values.count > 1 else { return values }
        var result: [Double] = []
        var sum: Double = 0
        for i in 0..<values.count {
            sum += values[i]
            if i >= window { sum -= values[i - window] }
            let count = min(i + 1, window)
            result.append(sum / Double(count))
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let maValues = movingAverage(points.map { $0.expense }, window: 5)
            let maxVal = max(maValues.max() ?? 1, 1)
            let minVal: Double = 0
            let stepX = width / CGFloat(max(points.count - 1, 1))
            let normalized = maValues.map { CGFloat(($0 - minVal) / (maxVal - minVal)) }
            let yPoints = normalized.map { height - ($0 * (height - 40)) - 20 }

            let pts: [CGPoint] = yPoints.enumerated().map { i, y in CGPoint(x: CGFloat(i) * stepX, y: y) }

            let dates = points.map { $0.date }
            let labelEvery = max(1, dates.count / 6)

            // Gridlines
            let gridCount = 3
            let gridYs: [CGFloat] = (0...gridCount).map { i in
                let frac = CGFloat(i) / CGFloat(gridCount)
                return height - frac * (height - 40) - 20
            }

            ZStack {
                ForEach(gridYs, id: \.self) { y in
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: width, y: y))
                    }
                    .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                }

                Path { axis in
                    axis.move(to: CGPoint(x: 0, y: height - 20))
                    axis.addLine(to: CGPoint(x: width, y: height - 20))
                }
                .stroke(Color.white.opacity(0.15), lineWidth: 1)

                // X-axis ticks & labels
                ForEach(Array(pts.enumerated()), id: \.offset) { idx, point in
                    if idx % labelEvery == 0 {
                        Path { p in
                            p.move(to: CGPoint(x: point.x, y: height - 20))
                            p.addLine(to: CGPoint(x: point.x, y: height - 16))
                        }
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        let text = label(for: dates[idx], count: dates.count)
                        Text(text)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .position(x: point.x, y: height - 6)
                    }
                }

                // Area fill
                if pts.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: height - 20))
                        if pts.count >= 3 {
                            path.addLine(to: pts[0])
                            for i in 1..<pts.count-1 {
                                let (cp1, cp2) = controlPoints(pts[i-1], pts[i], pts[i+1])
                                path.addCurve(to: pts[i+1], control1: cp1, control2: cp2)
                            }
                        } else {
                            for i in 0..<pts.count { path.addLine(to: pts[i]) }
                        }
                        path.addLine(to: CGPoint(x: width, y: height - 20))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [accent.opacity(0.25), Color.clear], startPoint: .top, endPoint: .bottom))
                }

                // Curve line
                Path { path in
                    if let first = pts.first { path.move(to: first) }
                    if pts.count >= 3 {
                        for i in 1..<pts.count-1 {
                            let (cp1, cp2) = controlPoints(pts[i-1], pts[i], pts[i+1])
                            path.addCurve(to: pts[i+1], control1: cp1, control2: cp2)
                        }
                    } else {
                        for p in pts.dropFirst() { path.addLine(to: p) }
                    }
                }
                .stroke(LinearGradient(colors: [accent, accent.opacity(0.6)], startPoint: .leading, endPoint: .trailing), lineWidth: 2)

                // Point marker: show only last point to declutter
                if let last = pts.last {
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                        .position(last)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .drawingGroup()
    }
}

fileprivate struct FinancialThemedGradientBar: View {
    let progress: Double
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let filled = max(0, min(1, progress)) * width

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.5)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: filled)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: filled)
            }
        }
    }
}
