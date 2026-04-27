import Foundation

struct DailyPlanService {
    struct PlanSelection {
        let slot: DailyPlanSlotType
        let assignmentId: UUID
        let score: Double
    }

    func buildPlan(
        assignments: [Assignment],
        today: Date,
        repeatingMustAssignmentId: UUID?
    ) -> [PlanSelection] {
        let now = today
        let openAssignments = assignments.filter { !$0.isCompleted }
        guard !openAssignments.isEmpty else { return [] }

        var selections: [PlanSelection] = []
        var usedIds = Set<UUID>()
        var usedClasses = Set<String>()

        if let must = pickMustDo(
            from: openAssignments,
            now: now,
            repeatingMustAssignmentId: repeatingMustAssignmentId
        ) {
            selections.append(must)
            usedIds.insert(must.assignmentId)
            if let assignment = openAssignments.first(where: { $0.id == must.assignmentId }) {
                usedClasses.insert(assignment.courseName)
            }
        }

        if let should = pickShouldDo(from: openAssignments, now: now, excluding: usedIds, preferredClasses: usedClasses) {
            selections.append(should)
            usedIds.insert(should.assignmentId)
            if let assignment = openAssignments.first(where: { $0.id == should.assignmentId }) {
                usedClasses.insert(assignment.courseName)
            }
        }

        if let quickWin = pickQuickWin(from: openAssignments, now: now, excluding: usedIds, preferredClasses: usedClasses) {
            selections.append(quickWin)
        }

        return selections
    }

    private func pickMustDo(from assignments: [Assignment], now: Date, repeatingMustAssignmentId: UUID?) -> PlanSelection? {
        let sorted = assignments
            .map { assignment in
                PlanSelection(slot: .must, assignmentId: assignment.id, score: mustDoScore(for: assignment, now: now))
            }
            .sorted { $0.score > $1.score }

        guard let first = sorted.first else { return nil }

        if let repeatingMustAssignmentId,
           first.assignmentId == repeatingMustAssignmentId,
           !isOverdue(assignments, assignmentId: repeatingMustAssignmentId, now: now),
           sorted.count > 1 {
            return sorted[1]
        }

        return first
    }

    private func pickShouldDo(
        from assignments: [Assignment],
        now: Date,
        excluding usedIds: Set<UUID>,
        preferredClasses: Set<String>
    ) -> PlanSelection? {
        assignments
            .filter { !usedIds.contains($0.id) }
            .map { assignment in
                let classPenalty = preferredClasses.contains(assignment.courseName) ? -3.5 : 0.0
                let score = shouldDoScore(for: assignment, now: now) + classPenalty
                return PlanSelection(slot: .should, assignmentId: assignment.id, score: score)
            }
            .sorted { $0.score > $1.score }
            .first
    }

    private func pickQuickWin(
        from assignments: [Assignment],
        now: Date,
        excluding usedIds: Set<UUID>,
        preferredClasses: Set<String>
    ) -> PlanSelection? {
        let remaining = assignments.filter { !usedIds.contains($0.id) }
        guard !remaining.isEmpty else { return nil }

        let quickPool = remaining.filter { $0.estMinutes <= 15 }
        let candidates = quickPool.isEmpty ? remaining : quickPool

        return candidates
            .map { assignment in
                let classPenalty = preferredClasses.contains(assignment.courseName) ? -2.0 : 0.0
                let score = quickWinScore(for: assignment, now: now) + classPenalty
                return PlanSelection(slot: .quickWin, assignmentId: assignment.id, score: score)
            }
            .sorted { $0.score > $1.score }
            .first
    }

    private func mustDoScore(for assignment: Assignment, now: Date) -> Double {
        urgencyScore(for: assignment, now: now)
        + latenessPenalty(for: assignment, now: now)
        + effortFitScore(minutes: assignment.estMinutes, preferredRange: 20...75)
    }

    private func shouldDoScore(for assignment: Assignment, now: Date) -> Double {
        urgencyScore(for: assignment, now: now)
        + (latenessPenalty(for: assignment, now: now) * 0.8)
        + effortFitScore(minutes: assignment.estMinutes, preferredRange: 30...120)
    }

    private func quickWinScore(for assignment: Assignment, now: Date) -> Double {
        urgencyScore(for: assignment, now: now)
        + (latenessPenalty(for: assignment, now: now) * 0.4)
        + effortFitScore(minutes: assignment.estMinutes, preferredRange: 1...20)
    }

    private func urgencyScore(for assignment: Assignment, now: Date) -> Double {
        let hoursToDue = assignment.dueDate.timeIntervalSince(now) / 3600
        if hoursToDue <= 0 { return 80 }
        return max(0, 72 - min(72, hoursToDue))
    }

    private func latenessPenalty(for assignment: Assignment, now: Date) -> Double {
        guard assignment.dueDate < now else { return 0 }
        let hoursLate = now.timeIntervalSince(assignment.dueDate) / 3600
        return 90 + min(72, hoursLate)
    }

    private func effortFitScore(minutes: Int, preferredRange: ClosedRange<Int>) -> Double {
        if preferredRange.contains(minutes) { return 12 }
        let distance: Int
        if minutes < preferredRange.lowerBound {
            distance = preferredRange.lowerBound - minutes
        } else {
            distance = minutes - preferredRange.upperBound
        }
        return max(-15, 12 - Double(distance) * 0.2)
    }

    private func isOverdue(_ assignments: [Assignment], assignmentId: UUID, now: Date) -> Bool {
        guard let assignment = assignments.first(where: { $0.id == assignmentId }) else { return false }
        return assignment.dueDate < now
    }
}
