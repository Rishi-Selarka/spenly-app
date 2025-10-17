import Foundation

struct DraftTransaction: Codable, Identifiable, Equatable {
    let id: UUID
    var amount: Double
    var isExpense: Bool
    var note: String?
    var category: String?
    var date: Date?

    init(
        id: UUID = UUID(),
        amount: Double,
        isExpense: Bool,
        note: String? = nil,
        category: String? = nil,
        date: Date? = nil
    ) {
        self.id = id
        self.amount = amount
        self.isExpense = isExpense
        self.note = note
        self.category = category
        self.date = date
    }
}


