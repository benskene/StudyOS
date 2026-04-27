//
//  AnalyticsService.swift
//  Struc
//
//  Created by Ben Skene on 2/2/26.
//

import Foundation

struct AnalyticsService {
    let assignments: [Assignment]
    let sprints: [FocusSprint]
    private let weekDateProvider = WeekDateProvider()

    var totalAssignmentsCompleted: Int {
        assignments.filter { $0.isCompleted }.count
    }

    var totalAssignmentsMissed: Int {
        let today = Date()
        return assignments.filter { !$0.isCompleted && $0.dueDate < today }.count
    }

    var completedAssignments: [Assignment] {
        assignments.filter { $0.isCompleted }
    }

    var completedAssignmentsWithTime: [Assignment] {
        completedAssignments.filter { $0.totalMinutesWorked > 0 }
    }

    var avgEstimatedMinutes: Int? {
        guard !completedAssignmentsWithTime.isEmpty else { return nil }
        let total = completedAssignmentsWithTime.reduce(0) { $0 + $1.estMinutes }
        return total / completedAssignmentsWithTime.count
    }

    var avgActualMinutes: Int? {
        guard !completedAssignmentsWithTime.isEmpty else { return nil }
        let total = completedAssignmentsWithTime.reduce(0) { $0 + $1.totalMinutesWorked }
        return total / completedAssignmentsWithTime.count
    }

    var estimationRatio: Double? {
        guard let avgEstimatedMinutes, let avgActualMinutes else { return nil }
        let safeEstimated = max(1, avgEstimatedMinutes)
        return Double(avgActualMinutes) / Double(safeEstimated)
    }

    var estimationInsightText: String? {
        guard let estimationRatio else { return nil }
        if estimationRatio > 1.3 {
            return "You usually underestimate time."
        } else if estimationRatio < 0.7 {
            return "You usually overestimate time."
        }
        return "Your estimates are fairly accurate."
    }

    var workBestInsightText: String? {
        let hours = completedAssignments.compactMap { assignment -> Int? in
            Calendar.current.dateComponents([.hour], from: assignment.lastModified).hour
        }
        guard !hours.isEmpty else { return nil }

        let counts = Dictionary(grouping: hours, by: { $0 }).mapValues { $0.count }
        guard let maxHour = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return workInsightLabel(for: maxHour)
    }

    var percentageCompletedOnTime: Int? {
        let completedOnTime = completedAssignments.filter { $0.lastModified <= $0.dueDate }.count
        let totalCompleted = completedAssignments.count
        guard totalCompleted > 0 else { return nil }
        return Int((Double(completedOnTime) / Double(totalCompleted)) * 100)
    }

    var recentCompletedAssignments: [Assignment] {
        completedAssignments.sorted(by: { $0.lastModified > $1.lastModified })
    }

    var sprintsThisWeek: [FocusSprint] {
        guard let range = weekDateProvider.weekRange() else { return [] }
        return sprints.filter { $0.startTime >= range.lowerBound && $0.startTime < range.upperBound }
    }

    var totalSprintsThisWeek: Int {
        sprintsThisWeek.count
    }

    var totalFocusedMinutesThisWeek: Int {
        let seconds = sprintsThisWeek.reduce(0) { $0 + $1.durationSeconds }
        return max(0, Int(round(Double(seconds) / 60.0)))
    }

    var mostWorkedOnTaskThisWeek: Assignment? {
        let grouped = Dictionary(grouping: sprintsThisWeek.compactMap(\.assignmentId), by: { $0 })
        guard let best = grouped.max(by: { $0.value.count < $1.value.count }) else { return nil }
        return assignments.first(where: { $0.id == best.key })
    }

    private func workInsightLabel(for hour: Int) -> String {
        switch hour {
        case 12..<18:
            return "afternoon"
        case 18..<24:
            return "evening"
        case 0..<5:
            return "late night"
        default:
            return "morning"
        }
    }
}

struct ConsistencyService {
    private let weekDateProvider = WeekDateProvider()

    struct WeekTrend {
        let currentMinutes: Int
        let previousMinutes: Int

        var direction: String {
            if currentMinutes > previousMinutes + 10 {
                return "Up"
            }
            if previousMinutes > currentMinutes + 10 {
                return "Down"
            }
            return "Flat"
        }
    }

    func calculateDailyStreak(from snapshots: [ConsistencySnapshot], today: Date = Date()) -> Int {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(uniqueKeysWithValues: snapshots.map { (calendar.startOfDay(for: $0.date), $0.didCompleteSprint) })
        var streak = 0
        var cursor = calendar.startOfDay(for: today)

        while grouped[cursor] == true {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }

    func calculateWeeklyStreak(from snapshots: [ConsistencySnapshot], today: Date = Date()) -> Int {
        let calendar = Calendar.autoupdatingCurrent
        var streakWeeks = 0
        var referenceDate = today

        while let weekRange = weekDateProvider.weekRange(containing: referenceDate) {
            let weekDays = snapshots.filter { $0.date >= weekRange.lowerBound && $0.date < weekRange.upperBound }
            let sprintDays = Set(weekDays.filter { $0.didCompleteSprint }.map { calendar.startOfDay(for: $0.date) }).count
            guard sprintDays >= 5 else { break }
            streakWeeks += 1
            guard let previousWeekDate = calendar.date(byAdding: .day, value: -7, to: referenceDate) else { break }
            referenceDate = previousWeekDate
        }

        return streakWeeks
    }

    func weekTrend(sprints: [FocusSprint], today: Date = Date()) -> WeekTrend {
        guard let currentRange = weekDateProvider.weekRange(containing: today),
              let previousAnchor = weekDateProvider.date(byAdding: .day, value: -7, to: currentRange.lowerBound),
              let previousRange = weekDateProvider.weekRange(containing: previousAnchor) else {
            return WeekTrend(currentMinutes: 0, previousMinutes: 0)
        }

        let currentMinutes = sprints
            .filter { $0.startTime >= currentRange.lowerBound && $0.startTime < currentRange.upperBound }
            .reduce(0) { $0 + Int(round(Double($1.durationSeconds) / 60.0)) }

        let previousMinutes = sprints
            .filter { $0.startTime >= previousRange.lowerBound && $0.startTime < previousRange.upperBound }
            .reduce(0) { $0 + Int(round(Double($1.durationSeconds) / 60.0)) }

        return WeekTrend(currentMinutes: currentMinutes, previousMinutes: previousMinutes)
    }

    func behaviorInsight(
        analytics: AnalyticsService,
        trend: WeekTrend,
        dailyStreak: Int
    ) -> (headline: String, action: String) {
        if analytics.totalAssignmentsMissed > 0 {
            return (
                "You have overdue work competing for attention.",
                "Start a 5-minute sprint on your earliest overdue assignment."
            )
        }

        if trend.direction == "Down" {
            return (
                "Your focused minutes dipped this week.",
                "Schedule one 10-minute sprint before 8 PM today."
            )
        }

        if dailyStreak >= 3 {
            return (
                "Your consistency is building.",
                "Protect your streak with one quick-win sprint today."
            )
        }

        return (
            "Momentum is available right now.",
            "Open Start Mode and finish a 5-minute sprint."
        )
    }
}
