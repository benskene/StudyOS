//
//  WeekViewScreen.swift
//  Struc
//
//  Created by Ben Skene on 2/2/26.
//

import SwiftUI
import SwiftData

struct WeekViewScreen: View {
    @EnvironmentObject private var assignmentStore: AssignmentStore
    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @State private var spreadProposal: [WorkloadMove] = []
    @State private var isShowingSpreadConfirm = false
    @State private var isShowingAddAssignment = false
    @State private var selectedDayForDetail: SelectedDay?

    private struct SelectedDay: Identifiable {
        let id = UUID()
        let date: Date
    }

    private let weekDateProvider = WeekDateProvider()
    private let overloadThreshold = 180
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
    private static let rangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private var incompleteAssignments: [Assignment] {
        assignments.filter { !$0.isCompleted }
    }

    private var weekDates: [Date] {
        weekDateProvider.weekDates()
    }

    private var assignmentsByDay: [Date: [Assignment]] {
        groupAssignmentsByDay(incompleteAssignments)
    }

    private var weekAssignments: [Assignment] {
        guard let range = weekDateProvider.weekRange() else { return [] }
        return incompleteAssignments.filter { $0.dueDate >= range.lowerBound && $0.dueDate < range.upperBound }
    }

    private var weekRangeLabel: String {
        guard let first = weekDates.first, let last = weekDates.last else { return "" }
        let start = Self.rangeFormatter.string(from: first)
        let end = Self.rangeFormatter.string(from: last)
        return "\(start) – \(end)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.standard) {
                // Date range subtitle
                Text(weekRangeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                if weekAssignments.isEmpty {
                    emptyWeekState
                } else {
                    overloadBanner
                    weekColumns
                }
            }
            .padding(.horizontal, DS.Spacing.standard)
            .padding(.top, DS.Spacing.micro)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.screenBackground.ignoresSafeArea())
        .navigationTitle("This Week")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAddAssignment = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $isShowingAddAssignment) {
            NavigationStack {
                AddAssignmentScreen()
                    .environmentObject(assignmentStore)
            }
        }
        .confirmationDialog("Apply suggested workload moves?", isPresented: $isShowingSpreadConfirm) {
            Button("Apply Suggestions") {
                applySpreadProposal()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(spreadProposalSummary)
        }
        .sheet(item: $selectedDayForDetail) { selected in
            DayDetailView(
                date: selected.date,
                assignments: assignmentsByDay[weekDateProvider.startOfDay(selected.date)] ?? []
            )
            .environmentObject(assignmentStore)
        }
    }

    // MARK: - Overload Banner

    private var overloadBanner: some View {
        Group {
            if !overloadedDays.isEmpty {
                HStack(alignment: .top, spacing: DS.Spacing.micro) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: DS.Spacing.micro) {
                        Text("Overload on \(overloadedDays.joined(separator: ", ")) — exceeds \(overloadThreshold) min")
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        Button {
                            spreadProposal = buildSpreadProposal()
                            if !spreadProposal.isEmpty {
                                isShowingSpreadConfirm = true
                            }
                        } label: {
                            Text("Spread Workload")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(.orange)
                                .background(
                                    Color.orange.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                )
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .disabled(buildSpreadProposal().isEmpty)
                    }
                }
                .padding(DS.Spacing.standard)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(Color.orange.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Week Columns

    private var weekColumns: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.Spacing.standard) {
                ForEach(weekDates, id: \.self) { date in
                    dayColumn(for: date)
                        .frame(width: 200)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Day Column

    private func isToday(_ date: Date) -> Bool {
        Calendar.autoupdatingCurrent.isDateInToday(date)
    }

    private func dayColumn(for date: Date) -> some View {
        let dayAssignments = assignmentsByDay[weekDateProvider.startOfDay(date)] ?? []
        let today = isToday(date)
        let loadMinutes = estimatedMinutes(for: date)
        let loadFraction = min(1.0, Double(loadMinutes) / Double(overloadThreshold))
        let isOverloaded = loadMinutes > overloadThreshold

        return VStack(alignment: .leading, spacing: DS.Spacing.standard) {
            // Day header — tappable to show Day Detail
            Button {
                selectedDayForDetail = SelectedDay(date: date)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayLabel(for: date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(today ? .white : .secondary)

                    ZStack {
                        Circle()
                            .fill(today ? Color.accentColor : Color.clear)
                            .frame(width: 32, height: 32)
                        Text(dateLabel(for: date))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(today ? .white : .primary)
                    }

                    // Workload bar
                    VStack(alignment: .leading, spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.12))
                                Capsule()
                                    .fill(isOverloaded ? Color.orange : Color.accentColor)
                                    .frame(width: geo.size.width * loadFraction)
                            }
                        }
                        .frame(height: 5)

                        Text("\(loadMinutes) min")
                            .font(.caption2)
                            .foregroundStyle(isOverloaded ? .orange : .secondary)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .opacity(0.5)

            // Assignments or empty state
            if dayAssignments.isEmpty {
                emptyDayState
            } else {
                VStack(alignment: .leading, spacing: DS.Spacing.micro) {
                    ForEach(dayAssignments) { assignment in
                        NavigationLink {
                            AssignmentDetailScreen(assignment: assignment)
                        } label: {
                            assignmentCard(assignment)
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .draggable(assignment.id.uuidString)
                    }
                }
            }
        }
        .padding(DS.Spacing.standard)
        .frame(minHeight: 260, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(
                    today ? Color.accentColor.opacity(0.45) : DS.Border.color,
                    lineWidth: today ? 1.5 : DS.Border.width
                )
        )
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items, targetDate: date)
        }
    }

    // MARK: - Assignment Card

    private func assignmentCard(_ assignment: Assignment) -> some View {
        let energy = AssignmentEnergyLevel(rawValue: assignment.energyLevel) ?? .medium
        let accentColor = energyColor(energy)

        return HStack(spacing: 0) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accentColor)
                .frame(width: 3)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(assignment.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(assignment.estMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !assignment.courseName.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(assignment.courseName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .fill(accentColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .stroke(DS.Border.color, lineWidth: DS.Border.width)
        )
    }

    private func energyColor(_ level: AssignmentEnergyLevel) -> Color {
        switch level {
        case .low:    return .green
        case .medium: return .blue
        case .high:   return .purple
        }
    }

    // MARK: - Empty States

    private var emptyDayState: some View {
        VStack {
            Image(systemName: "tray")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("Free")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }

    private var emptyWeekState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(DS.Colors.tertiaryText)
            Text("No tasks scheduled this week")
                .font(.subheadline)
                .foregroundStyle(DS.Colors.secondaryText)
            Button("Add a task") {
                isShowingAddAssignment = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DS.Colors.accent)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .multilineTextAlignment(.center)
        .padding(.top, 60)
    }

    // MARK: - Helpers

    private func dayLabel(for date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }

    private func dateLabel(for date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private func estimatedMinutes(for date: Date) -> Int {
        let day = weekDateProvider.startOfDay(date)
        let dayAssignments = assignmentsByDay[day] ?? []
        return dayAssignments.reduce(0) { $0 + $1.estMinutes }
    }

    private var overloadedDays: [String] {
        weekDates.compactMap { date in
            estimatedMinutes(for: date) > overloadThreshold ? dayLabel(for: date) : nil
        }
    }

    private func handleDrop(_ items: [String], targetDate: Date) -> Bool {
        guard let idString = items.first,
              let id = UUID(uuidString: idString),
              let assignment = assignments.first(where: { $0.id == id }) else {
            return false
        }

        let targetDay = weekDateProvider.startOfDay(targetDate)
        let currentDay = weekDateProvider.startOfDay(assignment.dueDate)
        guard targetDay != currentDay else { return false }

        guard let newDate = updatedDueDate(for: assignment, targetDay: targetDay) else {
            return false
        }

        assignmentStore.updateDueDate(assignment, to: newDate)
        return true
    }

    private func updatedDueDate(for assignment: Assignment, targetDay: Date) -> Date? {
        var dayComponents = weekDateProvider.dateComponents([.year, .month, .day], from: targetDay)
        let timeComponents = weekDateProvider.dateComponents([.hour, .minute, .second, .nanosecond], from: assignment.dueDate)

        dayComponents.hour = timeComponents.hour
        dayComponents.minute = timeComponents.minute
        dayComponents.second = timeComponents.second
        dayComponents.nanosecond = timeComponents.nanosecond

        return weekDateProvider.date(from: dayComponents)
    }

    func groupAssignmentsByDay(_ assignments: [Assignment]) -> [Date: [Assignment]] {
        let grouped = Dictionary(grouping: assignments) { assignment in
            weekDateProvider.startOfDay(assignment.dueDate)
        }

        return grouped.mapValues { dayAssignments in
            dayAssignments.sorted {
                if $0.dueDate == $1.dueDate {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.dueDate < $1.dueDate
            }
        }
    }

    private func buildSpreadProposal() -> [WorkloadMove] {
        var proposal: [WorkloadMove] = []
        var estimatesByDay = Dictionary(uniqueKeysWithValues: weekDates.map { (weekDateProvider.startOfDay($0), estimatedMinutes(for: $0)) })
        let dayAssignments = groupAssignmentsByDay(incompleteAssignments)
        let sortedHeavyDays = weekDates
            .map { weekDateProvider.startOfDay($0) }
            .sorted { (estimatesByDay[$0] ?? 0) > (estimatesByDay[$1] ?? 0) }

        for heavyDay in sortedHeavyDays where (estimatesByDay[heavyDay] ?? 0) > overloadThreshold {
            let flexible = (dayAssignments[heavyDay] ?? []).filter { $0.isFlexibleDueDate }.sorted { $0.estMinutes > $1.estMinutes }
            for assignment in flexible where (estimatesByDay[heavyDay] ?? 0) > overloadThreshold {
                guard let target = weekDates
                    .map({ weekDateProvider.startOfDay($0) })
                    .filter({ $0 != heavyDay })
                    .sorted(by: { (estimatesByDay[$0] ?? 0) < (estimatesByDay[$1] ?? 0) })
                    .first(where: { (estimatesByDay[$0] ?? 0) + assignment.estMinutes <= overloadThreshold }) else {
                    continue
                }

                proposal.append(WorkloadMove(assignment: assignment, fromDay: heavyDay, toDay: target))
                estimatesByDay[heavyDay, default: 0] -= assignment.estMinutes
                estimatesByDay[target, default: 0] += assignment.estMinutes
            }
        }

        return proposal
    }

    private var spreadProposalSummary: String {
        guard !spreadProposal.isEmpty else { return "No flexible tasks available to spread." }
        return spreadProposal.map { move in
            "\(move.assignment.title): \(dayLabel(for: move.fromDay)) to \(dayLabel(for: move.toDay))"
        }.joined(separator: "\n")
    }

    private func applySpreadProposal() {
        for move in spreadProposal {
            guard let newDate = updatedDueDate(for: move.assignment, targetDay: move.toDay) else { continue }
            assignmentStore.updateDueDate(move.assignment, to: newDate)
        }
        spreadProposal = []
    }
}

private struct WorkloadMove {
    let assignment: Assignment
    let fromDay: Date
    let toDay: Date
}

// MARK: - Day Detail View

private struct DayDetailView: View {
    let date: Date
    let assignments: [Assignment]
    @EnvironmentObject private var assignmentStore: AssignmentStore
    @Environment(\.dismiss) private var dismiss

    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if assignments.isEmpty {
                    VStack(spacing: DS.Spacing.standard) {
                        Spacer()
                        Image(systemName: "tray")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text("No assignments due")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(assignments) { assignment in
                            HStack(spacing: DS.Spacing.standard) {
                                Button {
                                    assignmentStore.toggleCompleted(assignment)
                                } label: {
                                    Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(assignment.isCompleted ? .secondary : Color.accentColor)
                                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: assignment.isCompleted)
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(assignment.title)
                                        .font(.body)
                                        .foregroundStyle(assignment.isCompleted ? .secondary : .primary)
                                        .strikethrough(assignment.isCompleted, color: .secondary)

                                    HStack(spacing: 4) {
                                        if !assignment.courseName.isEmpty {
                                            Text(assignment.courseName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("·")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                        let energy = AssignmentEnergyLevel(rawValue: assignment.energyLevel) ?? .medium
                                        Text(energy.rawValue.capitalized)
                                            .font(.caption)
                                            .foregroundStyle(energyColor(energy))
                                        Text("·")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                        Text("\(assignment.estMinutes) min")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .opacity(assignment.isCompleted ? 0.55 : 1)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(DS.screenBackground.ignoresSafeArea())
            .navigationTitle(Self.headerFormatter.string(from: date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func energyColor(_ level: AssignmentEnergyLevel) -> Color {
        switch level {
        case .low:    return .green
        case .medium: return .blue
        case .high:   return .purple
        }
    }
}

#Preview {
    let container = ModelContainerProvider.make(inMemory: true)
    let authManager = AuthManager()
    let sprintManager = SprintSessionManager()
    let store = AssignmentStore(modelContext: container.mainContext, authManager: authManager, sprintSessionManager: sprintManager)

    return NavigationStack {
        WeekViewScreen()
            .environmentObject(store)
            .environmentObject(authManager)
            .environmentObject(sprintManager)
            .modelContainer(container)
    }
}

