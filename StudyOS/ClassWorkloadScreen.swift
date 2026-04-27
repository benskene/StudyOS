//
//  ClassWorkloadScreen.swift
//  Struc
//
//  Created by Ben Skene on 2/3/26.
//

import SwiftUI
import SwiftData

struct ClassWorkloadScreen: View {
    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]

    private let weekDateProvider = WeekDateProvider()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection

                if classNames.isEmpty {
                    emptyClassesState
                } else if assignmentsThisWeek.isEmpty {
                    emptyAssignmentsState
                } else {
                    insightSection
                    workloadList
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .navigationTitle("Class Workload")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Class Workload")
                .font(.largeTitle)
            Text("This week")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var insightSection: some View {
        Text(insightText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var workloadList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(classSummaries) { summary in
                workloadCard(summary: summary)
            }
        }
    }

    private func workloadCard(summary: ClassWorkloadSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary.className)
                .font(.title3)

            Text("\(summary.assignmentCount) assignments this week")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\(summary.totalEstimatedMinutes) min estimated")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\(summary.completedCount) of \(summary.assignmentCount) completed")
                .font(.caption)
                .foregroundStyle(.secondary)

            if summary.assignmentCount > 0 {
                ProgressView(value: Double(summary.completedCount), total: Double(summary.assignmentCount))
                    .tint(.primary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyClassesState: some View {
        Text("No classes yet. Add one to get started.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 240)
            .multilineTextAlignment(.center)
    }

    private var emptyAssignmentsState: some View {
        Text("This week looks light.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 240)
            .multilineTextAlignment(.center)
    }

    private var assignmentsThisWeek: [Assignment] {
        let range = weekDateRange
        return assignments.filter { assignment in
            assignment.dueDate >= range.start && assignment.dueDate < range.end
        }
    }

    private var classNames: [String] {
        let names = Set(assignments.map { $0.courseName.trimmingCharacters(in: .whitespacesAndNewlines) })
        return names.filter { !$0.isEmpty }.sorted()
    }

    private var classSummaries: [ClassWorkloadSummary] {
        classNames
            .map { className in
                ClassWorkloadSummary(
                    className: className,
                    assignmentCount: assignmentCountForClassThisWeek(className),
                    totalEstimatedMinutes: estimatedMinutesForClassThisWeek(className),
                    completedCount: completedCountForClassThisWeek(className)
                )
            }
            .sorted { $0.totalEstimatedMinutes > $1.totalEstimatedMinutes }
    }

    private var insightText: String {
        guard let heaviest = classSummaries.first else {
            return "Your workload is evenly spread this week."
        }

        let highestMinutes = heaviest.totalEstimatedMinutes
        let contenders = classSummaries.filter { $0.totalEstimatedMinutes == highestMinutes }

        if contenders.count == 1 {
            return "\(heaviest.className) is your heaviest class this week."
        }

        return "Your workload is evenly spread this week."
    }

    private func assignmentsForClassThisWeek(_ className: String) -> [Assignment] {
        assignmentsThisWeek.filter { $0.courseName == className }
    }

    private func assignmentCountForClassThisWeek(_ className: String) -> Int {
        assignmentsForClassThisWeek(className).count
    }

    private func estimatedMinutesForClassThisWeek(_ className: String) -> Int {
        assignmentsForClassThisWeek(className).reduce(0) { $0 + $1.estMinutes }
    }

    private func completedCountForClassThisWeek(_ className: String) -> Int {
        assignmentsForClassThisWeek(className).filter { $0.isCompleted }.count
    }

    private var weekDateRange: (start: Date, end: Date) {
        guard let range = weekDateProvider.weekRange() else {
            let now = Date()
            return (now, now)
        }
        return (range.lowerBound, range.upperBound)
    }
}

private struct ClassWorkloadSummary: Identifiable {
    let id = UUID()
    let className: String
    let assignmentCount: Int
    let totalEstimatedMinutes: Int
    let completedCount: Int
}

#Preview {
    let container = ModelContainerProvider.make(inMemory: true)
    let authManager = AuthManager()
    let sprintManager = SprintSessionManager()
    let store = AssignmentStore(modelContext: container.mainContext, authManager: authManager, sprintSessionManager: sprintManager)

    return NavigationStack {
        ClassWorkloadScreen()
            .environmentObject(store)
            .environmentObject(authManager)
            .environmentObject(sprintManager)
            .modelContainer(container)
    }
}
