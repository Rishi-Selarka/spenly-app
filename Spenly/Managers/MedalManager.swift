import Foundation
import SwiftUI

final class MedalManager: ObservableObject {
    static let shared = MedalManager()

    @Published private(set) var currentIconName: String? = nil
    @Published private(set) var currentIconColor: Color = .clear
    @Published private(set) var currentCycleProgress: Int = 0 // 0-100+

    private init() {}

    // MARK: - Keys
    private func overallKey(_ accountId: UUID?) -> String { "budget_overall_completion_count_\(accountId?.uuidString ?? "")" }
    private func categoryKey(_ accountId: UUID?) -> String { "budget_category_completion_count_\(accountId?.uuidString ?? "")" }
    private func cycleStartKey(_ accountId: UUID?) -> String { "medal_cycle_start_total_\(accountId?.uuidString ?? "")" }

    // MARK: - Public API
    func refresh(for accountId: UUID?) {
        let total = UserDefaults.standard.integer(forKey: overallKey(accountId)) + UserDefaults.standard.integer(forKey: categoryKey(accountId))
        let start = UserDefaults.standard.integer(forKey: cycleStartKey(accountId))
        let progress = max(0, total - start)
        currentCycleProgress = progress

        let (name, color) = Self.icon(for: progress)
        currentIconName = name
        currentIconColor = color
        DispatchQueue.main.async {
            self.objectWillChange.send()
            NotificationCenter.default.post(name: NSNotification.Name("MedalProgressUpdated"), object: nil)
        }
    }

    func currentMedal(for accountId: UUID?) -> (name: String, color: Color)? {
        let total = UserDefaults.standard.integer(forKey: overallKey(accountId)) + UserDefaults.standard.integer(forKey: categoryKey(accountId))
        let start = UserDefaults.standard.integer(forKey: cycleStartKey(accountId))
        let progress = max(0, total - start)
        let (name, color) = Self.icon(for: progress)
        return name == nil ? nil : (name!, color)
    }

    func cycleProgress(for accountId: UUID?) -> Int {
        let total = UserDefaults.standard.integer(forKey: overallKey(accountId)) + UserDefaults.standard.integer(forKey: categoryKey(accountId))
        let start = UserDefaults.standard.integer(forKey: cycleStartKey(accountId))
        return max(0, total - start)
    }

    func restartCycle(for accountId: UUID?) {
        let total = UserDefaults.standard.integer(forKey: overallKey(accountId)) + UserDefaults.standard.integer(forKey: categoryKey(accountId))
        UserDefaults.standard.set(total, forKey: cycleStartKey(accountId))
        refresh(for: accountId)
    }

    // MARK: - Helpers
    private static func icon(for progress: Int) -> (String?, Color) {
        if progress >= 100 { return ("sparkles", Color.purple) }
        if progress >= 50 { return ("crown.fill", Color(red: 1.0, green: 0.84, blue: 0.0)) }
        if progress >= 5 { return ("medal.fill", Color(red: 0.75, green: 0.75, blue: 0.78)) }
        if progress >= 1 { return ("medal.fill", Color(red: 0.8, green: 0.5, blue: 0.2)) }
        return (nil, .clear)
    }
}


