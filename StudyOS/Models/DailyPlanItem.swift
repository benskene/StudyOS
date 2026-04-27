import Foundation
import SwiftData

enum DailyPlanSlotType: String, Codable, CaseIterable {
    case must
    case should
    case quickWin
}

@Model
final class DailyPlanItem: Identifiable {
    var id: UUID
    var date: Date
    var assignmentId: UUID
    var slotTypeRaw: String
    var createdAt: Date
    var completed: Bool

    init(
        id: UUID = UUID(),
        date: Date,
        assignmentId: UUID,
        slotType: DailyPlanSlotType,
        createdAt: Date = Date(),
        completed: Bool = false
    ) {
        self.id = id
        self.date = date
        self.assignmentId = assignmentId
        self.slotTypeRaw = slotType.rawValue
        self.createdAt = createdAt
        self.completed = completed
    }

    var slotType: DailyPlanSlotType {
        get { DailyPlanSlotType(rawValue: slotTypeRaw) ?? .should }
        set { slotTypeRaw = newValue.rawValue }
    }
}
