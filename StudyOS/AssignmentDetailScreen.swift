//
//  AssignmentDetailScreen.swift
//  Struc
//
//  Created by Ben Skene on 2/2/26.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct AssignmentDetailScreen: View {
    @EnvironmentObject private var assignmentStore: AssignmentStore
    @EnvironmentObject private var sprintSessionManager: SprintSessionManager
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @Query(sort: \FocusSprint.startTime, order: .reverse) private var sprints: [FocusSprint]

    @State private var selectedSprintMinutes = 10
    @State private var isShowingSprintCompletion = false
    @State private var handledCompletionId: UUID?

    let assignment: Assignment

    private let sprintOptions = [10, 20, 30]

    private var assignmentStillExists: Bool {
        assignments.contains { $0.id == assignment.id }
    }

    private var currentSession: SprintSession? {
        guard let active = sprintSessionManager.activeSession, active.assignmentId == assignment.id else {
            return nil
        }
        return active
    }

    private var sprintCount: Int {
        sprints.filter { $0.assignmentId == assignment.id }.count
    }

    private var dueDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return "Due: \(formatter.string(from: assignment.dueDate))"
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.micro) {
            Text(assignment.title)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            // Due date on its own line with clear visual weight
            Text(dueDateText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(
                    !assignment.isCompleted && assignment.dueDate < Date()
                        ? DS.Colors.destructive
                        : Color.primary.opacity(0.6)
                )

            // Secondary metadata chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.micro) {
                    if !assignment.courseName.isEmpty {
                        metaChip(assignment.courseName, icon: "books.vertical")
                    }
                    metaChip("Est. \(assignment.estMinutes) min", icon: "clock")
                    if sprintCount > 0 {
                        metaChip("\(sprintCount) sprint\(sprintCount == 1 ? "" : "s")", icon: "bolt.fill")
                    }
                    EnergyBadge(level: AssignmentEnergyLevel(rawValue: assignment.energyLevel) ?? .medium)
                }
            }
        }
        .padding(DS.Spacing.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
    }

    private func metaChip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.1), in: Capsule())
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.micro) {
            Text("Notes")
                .font(.headline)
                .foregroundStyle(.secondary)
            TextEditor(text: bindingForNotes)
                .frame(height: 110)
                .padding(DS.Spacing.micro)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .fill(DS.screenBackground)
                )
        }
        .padding(DS.Spacing.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
    }

    private var focusTimerSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.standard) {
            Text("Focus")
                .font(.title3)

            // Duration picker
            HStack(spacing: 8) {
                ForEach(sprintOptions, id: \.self) { minutes in
                    Button {
                        selectedSprintMinutes = minutes
                    } label: {
                        Text("\(minutes) min")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(selectedSprintMinutes == minutes ? .white : .primary)
                            .background(
                                selectedSprintMinutes == minutes
                                    ? Color.accentColor
                                    : DS.Colors.secondaryButtonBg,
                                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            )
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedSprintMinutes)
                }
            }

            // Timer display and inline state grouped tightly
            VStack(alignment: .leading, spacing: DS.Spacing.micro) {
                Text(timerDisplay)
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .contentTransition(.numericText())

                timerDetails
            }
            .padding(.vertical, DS.Spacing.micro)

            // Start / Stop row — Stop Sprint replaces Start when a session is active
            HStack(spacing: DS.Spacing.micro) {
                if currentSession == nil {
                    Button {
                        startManualSprint()
                    } label: {
                        Text("Start")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(DS.Colors.primaryButtonFg)
                            .background(
                                DS.Colors.primaryButtonBg,
                                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            )
                    }
                    .buttonStyle(PressScaleButtonStyle())
                } else {
                    Button {
                        sprintSessionManager.cancelActiveSession()
                        isShowingSprintCompletion = false
                    } label: {
                        Text("Stop Sprint")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(
                                Color.red,
                                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            )
                    }
                    .buttonStyle(PressScaleButtonStyle())
                }

                Button {
                    let wasCompleted = assignment.isCompleted
                    assignmentStore.toggleCompleted(assignment)
                    if !wasCompleted && assignment.isCompleted {
                        triggerCompletionHaptic()
                    }
                } label: {
                    Text(assignment.isCompleted ? "Mark Incomplete" : "Mark Complete")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.primary)
                        .background(
                            DS.Colors.secondaryButtonBg,
                            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        )
                }
                .buttonStyle(PressScaleButtonStyle())
            }
        }
        .padding(DS.Spacing.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevatedCard()
    }

    private var bindingForNotes: Binding<String> {
        Binding(
            get: { assignment.notes },
            set: { newValue in
                assignmentStore.updateNotes(assignment, notes: newValue)
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                headerSection
                focusTimerSection
                notesSection

                Button(role: .destructive) {
                    assignmentStore.deleteAssignment(assignment)
                    dismissToRoot()
                } label: {
                    Text("Delete Assignment")
                }
                .buttonStyle(.plain)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red)
                .padding(.top, DS.Spacing.micro)
            }
            .padding(.horizontal, DS.Spacing.standard)
            .padding(.vertical, DS.Spacing.standard)
        }
        .background(DS.screenBackground.ignoresSafeArea())
        .navigationTitle(assignment.courseName.isEmpty ? "Personal" : assignment.courseName)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: sprintSessionManager.lastCompletedSession?.id) { _ in
            handleCompletionStateChange()
        }
        .onChange(of: assignmentStillExists) { exists in
            if !exists {
                dismissToRoot()
            }
        }
        .onAppear {
            handleCompletionStateChange()
        }
    }

    private var timerDisplay: String {
        if let session = currentSession {
            let seconds = max(0, Int(ceil(session.endsAt.timeIntervalSince(sprintSessionManager.currentTime))))
            return String(format: "%02d:%02d", seconds / 60, seconds % 60)
        }
        let seconds = selectedSprintMinutes * 60
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func handleCompletionStateChange() {
        guard let completed = sprintSessionManager.lastCompletedSession,
              completed.assignmentId == assignment.id,
              handledCompletionId != completed.id else {
            return
        }
        handledCompletionId = completed.id
        let minutes = max(1, Int(round(completed.endsAt.timeIntervalSince(completed.startedAt) / 60)))
        if minutes == 5 {
            isShowingSprintCompletion = true
        }
    }

    private func startManualSprint() {
        guard currentSession == nil else { return }
        NotificationManager.shared.cancelUnstartedSprintReminder(for: assignment.id)
        _ = sprintSessionManager.startSession(
            assignmentId: assignment.id,
            durationMinutes: selectedSprintMinutes,
            tinyStep: assignment.lastTinyStep
        )
    }

    private func triggerCompletionHaptic() {
#if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
#endif
    }

    private var timerDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let session = currentSession {
                Text(assignment.title)
                    .font(.headline)
                Text(session.tinyStep.isEmpty ? " " : session.tinyStep)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if isShowingSprintCompletion {
                Text("Nice start. Want to keep going?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: DS.Spacing.micro) {
                    Button {
                        isShowingSprintCompletion = false
                        NotificationManager.shared.cancelUnstartedSprintReminder(for: assignment.id)
                        _ = sprintSessionManager.startSession(
                            assignmentId: assignment.id,
                            durationMinutes: 10,
                            tinyStep: assignment.lastTinyStep
                        )
                    } label: {
                        Text("Another 10 min")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(DS.Colors.primaryButtonFg)
                            .background(
                                DS.Colors.primaryButtonBg,
                                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            )
                    }
                    .buttonStyle(PressScaleButtonStyle())

                    Button {
                        isShowingSprintCompletion = false
                    } label: {
                        Text("Done for now")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(.primary)
                            .background(
                                DS.Colors.secondaryButtonBg,
                                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            )
                    }
                    .buttonStyle(PressScaleButtonStyle())
                }
            }
        }
    }

    private func dismissToRoot() {
        dismiss()
        DispatchQueue.main.async {
            dismiss()
        }
    }
}

#Preview {
    let container = ModelContainerProvider.make(inMemory: true)
    let authManager = AuthManager()
    let sprintManager = SprintSessionManager()
    let store = AssignmentStore(modelContext: container.mainContext, authManager: authManager, sprintSessionManager: sprintManager)
    let assignment = Assignment(
        id: UUID(),
        title: "Practice Quiz",
        courseName: "Biology",
        dueDate: Date(),
        estMinutes: 25,
        source: "manual",
        externalId: nil,
        isCompleted: false,
        notes: "",
        totalMinutesWorked: 0,
        lastTinyStep: "",
        lastModified: Date()
    )

    return NavigationStack {
        AssignmentDetailScreen(assignment: assignment)
            .environmentObject(store)
            .environmentObject(authManager)
            .environmentObject(sprintManager)
            .modelContainer(container)
    }
}
