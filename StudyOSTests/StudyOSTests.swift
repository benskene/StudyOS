//
//  StudyOSTests.swift
//  StudyOSTests
//
//  Created by Ben Skene on 2/2/26.
//

import Testing
@testable import StudyOS

struct StudyOSTests {

    @Test func dailyPlanPrioritizesOverdue() async throws {
        let now = Date()
        let overdue = Assignment(id: UUID(), title: "Overdue", className: "Math", dueDate: now.addingTimeInterval(-3600), estMinutes: 40)
        let future = Assignment(id: UUID(), title: "Future", className: "Science", dueDate: now.addingTimeInterval(72 * 3600), estMinutes: 40)
        let service = DailyPlanService()

        let plan = service.buildPlan(assignments: [future, overdue], today: now, repeatingMustAssignmentId: nil)
        #expect(plan.first?.assignmentId == overdue.id)
    }

    @Test func dailyPlanIncludesQuickWinSlot() async throws {
        let now = Date()
        let quick = Assignment(id: UUID(), title: "Quick", className: "English", dueDate: now.addingTimeInterval(20 * 3600), estMinutes: 10)
        let medium = Assignment(id: UUID(), title: "Medium", className: "Math", dueDate: now.addingTimeInterval(10 * 3600), estMinutes: 50)
        let long = Assignment(id: UUID(), title: "Long", className: "Chem", dueDate: now.addingTimeInterval(15 * 3600), estMinutes: 120)
        let service = DailyPlanService()

        let plan = service.buildPlan(assignments: [quick, medium, long], today: now, repeatingMustAssignmentId: nil)
        let quickWin = plan.first(where: { $0.slot == .quickWin })
        #expect(quickWin?.assignmentId == quick.id)
    }

    @Test func consistencyDailyStreakCountsConsecutiveDays() async throws {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) ?? today
        let snapshots = [
            ConsistencySnapshot(date: today, didCompleteSprint: true, minutesFocused: 20, tasksCompleted: 1),
            ConsistencySnapshot(date: yesterday, didCompleteSprint: true, minutesFocused: 15, tasksCompleted: 0),
            ConsistencySnapshot(date: twoDaysAgo, didCompleteSprint: false, minutesFocused: 0, tasksCompleted: 0)
        ]
        let service = ConsistencyService()

        let streak = service.calculateDailyStreak(from: snapshots, today: today)
        #expect(streak == 2)
    }

}
