//
//  AnalyticsDashboardScreen.swift
//  Struc
//
//  Created by Ben Skene on 2/2/26.
//

import SwiftUI
import SwiftData
import Charts

struct AnalyticsDashboardScreen: View {
    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @Query(sort: \FocusSprint.startTime, order: .reverse) private var sprints: [FocusSprint]
    private let weekDateProvider = WeekDateProvider()

    private var analytics: AnalyticsService {
        AnalyticsService(assignments: assignments, sprints: sprints)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                atAGlanceSection
                productivitySummarySection
                estimatedVsActualSection
                workloadThisWeekSection
                onTimeVsLateSection
                recentActivitySection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.title3)

            if recentAssignments.isEmpty {
                Text("Finish a few tasks to see activity here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(recentAssignments) { assignment in
                        NavigationLink {
                            AssignmentDetailScreen(assignment: assignment)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(assignment.isCompleted ? .secondary : .primary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(assignment.title)
                                        .font(.headline)
                                    Text(assignment.courseName)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A simple look at how you work.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var atAGlanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("At a glance")
                .font(.title3)
            if assignments.isEmpty {
                Text("Complete a few tasks to see your insights.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 16) {
                    metricCard(title: "Completed", value: "\(analytics.totalAssignmentsCompleted)")
                    metricCard(title: "Missed", value: "\(analytics.totalAssignmentsMissed)")
                    metricCard(title: "On-time %", value: onTimeText)
                }
            }
        }
    }

    private var productivitySummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sprint Summary")
                .font(.title3)

            Text("Sprints this week: \(analytics.totalSprintsThisWeek)")
                .font(.subheadline)
            Text("Focused minutes this week: \(analytics.totalFocusedMinutesThisWeek)")
                .font(.subheadline)
            Text("Most worked-on task: \(analytics.mostWorkedOnTaskThisWeek?.title ?? "—")")
                .font(.subheadline)
        }
    }

    private var estimatedVsActualSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Estimated vs Actual Time")
                .font(.title3)
            if estimatedVsActualData.count < 3 {
                Text("Complete more tasks to see this chart.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(estimatedVsActualData) { item in
                        BarMark(
                            x: .value("Assignment", item.label),
                            y: .value("Minutes", item.estimatedMinutes)
                        )
                        .foregroundStyle(Color.primary)
                        .position(by: .value("Type", "Estimated"))

                        BarMark(
                            x: .value("Assignment", item.label),
                            y: .value("Minutes", item.actualMinutes)
                        )
                        .foregroundStyle(Color.secondary)
                        .position(by: .value("Type", "Actual"))
                    }
                }
                .chartYAxisLabel("Minutes")
                .chartLegend(.hidden)
                .frame(height: 220)
            }
        }
    }

    private var workloadThisWeekSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workload This Week")
                .font(.title3)
            if weekWorkloadData.allSatisfy({ $0.totalMinutes == 0 }) {
                Text("No data yet for this week.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart(weekWorkloadData) { day in
                    BarMark(
                        x: .value("Day", day.label),
                        y: .value("Minutes", day.totalMinutes)
                    )
                    .foregroundStyle(Color.primary)
                }
                .chartYAxisLabel("Minutes")
                .frame(height: 200)
            }
        }
    }

    private var onTimeVsLateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if onTimeVsLateData.totalCompleted > 0 {
                Text("On-Time vs Late")
                    .font(.title3)
                Chart {
                    SectorMark(
                        angle: .value("On time", onTimeVsLateData.onTimeCount),
                        innerRadius: .ratio(0.6)
                    )
                    .foregroundStyle(Color.primary)

                    SectorMark(
                        angle: .value("Late", onTimeVsLateData.lateCount),
                        innerRadius: .ratio(0.6)
                    )
                    .foregroundStyle(Color.secondary)
                }
                .frame(height: 160)

                HStack(spacing: 12) {
                    legendItem(color: .primary, label: "On time")
                    legendItem(color: .secondary, label: "Late")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var onTimeText: String {
        if let percentage = analytics.percentageCompletedOnTime {
            return "\(percentage)%"
        }
        return "—"
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title2)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }

    private var estimatedVsActualData: [EstimatedActualData] {
        let completed = assignments.filter { $0.isCompleted && $0.totalMinutesWorked > 0 }
        let sorted = completed.sorted { $0.lastModified > $1.lastModified }

        return sorted.prefix(10).map { assignment in
            EstimatedActualData(
                label: shortLabel(for: assignment.title),
                estimatedMinutes: assignment.estMinutes,
                actualMinutes: assignment.totalMinutesWorked
            )
        }
    }

    private var weekWorkloadData: [WeekdayWorkload] {
        guard let weekRange = weekDateProvider.weekRange() else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        let completedWithTime = assignments.filter { $0.isCompleted && $0.totalMinutesWorked > 0 }

        return (0..<7).compactMap { offset in
            guard let date = weekDateProvider.date(byAdding: .day, value: offset, to: weekRange.lowerBound) else {
                return nil
            }
            let dayStart = weekDateProvider.startOfDay(date)
            let totalMinutes = completedWithTime
                .filter { weekDateProvider.startOfDay($0.lastModified) == dayStart }
                .reduce(0) { $0 + $1.totalMinutesWorked }

            return WeekdayWorkload(label: formatter.string(from: date), totalMinutes: totalMinutes)
        }
    }

    private var onTimeVsLateData: OnTimeLateData {
        let completed = assignments.filter { $0.isCompleted }
        let onTime = completed.filter { $0.lastModified <= $0.dueDate }.count
        let late = max(0, completed.count - onTime)
        return OnTimeLateData(onTimeCount: onTime, lateCount: late)
    }

    private func shortLabel(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 10 else { return trimmed }
        let prefix = trimmed.prefix(10)
        return "\(prefix)…"
    }

    private var recentAssignments: [Assignment] {
        let sorted = assignments.sorted { $0.lastModified > $1.lastModified }
        return Array(sorted.prefix(5))
    }
}

private struct EstimatedActualData: Identifiable {
    let id = UUID()
    let label: String
    let estimatedMinutes: Int
    let actualMinutes: Int
}

private struct WeekdayWorkload: Identifiable {
    let id = UUID()
    let label: String
    let totalMinutes: Int
}

private struct OnTimeLateData {
    let onTimeCount: Int
    let lateCount: Int

    var totalCompleted: Int {
        onTimeCount + lateCount
    }
}

#Preview {
    let container = ModelContainerProvider.make(inMemory: true)
    let authManager = AuthManager()
    let sprintManager = SprintSessionManager()
    let store = AssignmentStore(modelContext: container.mainContext, authManager: authManager, sprintSessionManager: sprintManager)

    return NavigationStack {
        AnalyticsDashboardScreen()
            .environmentObject(store)
            .environmentObject(authManager)
            .environmentObject(sprintManager)
            .modelContainer(container)
    }
}
