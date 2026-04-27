import Foundation
import SwiftData

@Model
final class ConsistencySnapshot: Identifiable {
    var id: UUID
    var date: Date
    var didCompleteSprint: Bool
    var minutesFocused: Int
    var tasksCompleted: Int

    init(
        id: UUID = UUID(),
        date: Date,
        didCompleteSprint: Bool,
        minutesFocused: Int,
        tasksCompleted: Int
    ) {
        self.id = id
        self.date = date
        self.didCompleteSprint = didCompleteSprint
        self.minutesFocused = max(0, minutesFocused)
        self.tasksCompleted = max(0, tasksCompleted)
    }
}
