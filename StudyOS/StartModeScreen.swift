//
//  StartModeScreen.swift
//  Struc
//
//  Created by Ben Skene on 2/2/26.
//

import SwiftUI
import SwiftData

struct StartModeScreen: View {
    @EnvironmentObject private var assignmentStore: AssignmentStore
    @EnvironmentObject private var sprintSessionManager: SprintSessionManager
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @Query(sort: \FocusSprint.startTime, order: .reverse) private var sprints: [FocusSprint]

    @State private var tinyStep = ""
    @State private var selectedDuration = 5
    @State private var showCompletionDecision = false
    @State private var handledCompletionId: UUID?

    private let suggestedTinySteps = [
        "Open assignment instructions",
        "Create outline with 3 bullets",
        "Answer first question"
    ]
    private let durationOptions = [5, 10, 20]

    let assignment: Assignment
    let onStart: () -> Void

    private var assignmentStillExists: Bool {
        assignments.contains { $0.id == assignment.id }
    }

    private var activeSession: SprintSession? {
        sprintSessionManager.activeSession
    }

    private var hasSprintToday: Bool {
        let start = Calendar.autoupdatingCurrent.startOfDay(for: Date())
        guard let end = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: start) else { return false }
        return sprints.contains { $0.startTime >= start && $0.startTime < end }
    }

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                if let session = activeSession {
                    activeSprintPanel(session: session)
                } else if showCompletionDecision {
                    completionDecisionPanel
                } else {
                    setupPanel
                }
            }
            .padding(DS.Spacing.section)
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.standard)
        .onChange(of: assignmentStillExists) { exists in
            if !exists {
                NotificationManager.shared.cancelUnstartedSprintReminder(for: assignment.id)
                dismiss()
            }
        }
        .onAppear {
            selectedDuration = hasSprintToday ? 10 : 5
            if tinyStep.isEmpty {
                tinyStep = assignment.lastTinyStep.isEmpty ? suggestedTinySteps[0] : assignment.lastTinyStep
            }
            if sprintSessionManager.activeSession == nil {
                NotificationManager.shared.scheduleUnstartedSprintReminder(for: assignment.id)
            }
            handleCompletionStateChange()
        }
        .onChange(of: activeSession?.id) { sessionId in
            if sessionId == nil {
                NotificationManager.shared.scheduleUnstartedSprintReminder(for: assignment.id)
            } else {
                NotificationManager.shared.cancelUnstartedSprintReminder(for: assignment.id)
            }
        }
        .onChange(of: sprintSessionManager.lastCompletedSession?.id) { _ in
            handleCompletionStateChange()
        }
    }

    // MARK: - Setup Panel

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.section) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Get Started")
                    .font(.title2.weight(.semibold))
                Text("What's the smallest thing you can do right now?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.micro) {
                Text("My first tiny step is…")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Open the document", text: $tinyStep)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(DS.cardBackground, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .stroke(DS.Border.color, lineWidth: DS.Border.width)
                    )

                // Suggestion chips — horizontal scroll
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.micro) {
                        ForEach(suggestedTinySteps, id: \.self) { suggestion in
                            Button {
                                tinyStep = suggestion
                            } label: {
                                Text(suggestion)
                                    .font(.subheadline)
                                    .foregroundStyle(tinyStep == suggestion ? .primary : .secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        tinyStep == suggestion
                                            ? Color.accentColor.opacity(0.12)
                                            : DS.Colors.secondaryButtonBg,
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(
                                                tinyStep == suggestion ? Color.accentColor.opacity(0.35) : Color.clear,
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(PressScaleButtonStyle())
                        }
                    }
                }
            }

            // Duration picker
            HStack(spacing: 8) {
                ForEach(durationOptions, id: \.self) { minutes in
                    Button {
                        selectedDuration = minutes
                    } label: {
                        Text("\(minutes) min")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(selectedDuration == minutes ? .white : .primary)
                            .background(
                                selectedDuration == minutes
                                    ? Color.accentColor
                                    : DS.Colors.secondaryButtonBg,
                                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            )
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedDuration)
                }
            }

            // Primary CTA
            let stepIsEmpty = tinyStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button {
                let trimmedStep = tinyStep.trimmingCharacters(in: .whitespacesAndNewlines)
                assignmentStore.updateTinyStep(assignment, tinyStep: trimmedStep)
                NotificationManager.shared.cancelUnstartedSprintReminder(for: assignment.id)
                _ = sprintSessionManager.startSession(
                    assignmentId: assignment.id,
                    durationMinutes: selectedDuration,
                    tinyStep: trimmedStep
                )
            } label: {
                Text("Start \(selectedDuration)-minute sprint")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(DS.Colors.primaryButtonFg)
                    .background(
                        DS.Colors.primaryButtonBg.opacity(stepIsEmpty ? 0.3 : 1),
                        in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    )
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(stepIsEmpty)

            Button("Cancel") { dismiss() }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Completion Decision Panel

    private var completionDecisionPanel: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.standard) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sprint complete")
                    .font(.title2.weight(.semibold))
                Text("Choose one next step.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                showCompletionDecision = false
                NotificationManager.shared.cancelUnstartedSprintReminder(for: assignment.id)
                _ = sprintSessionManager.startSession(
                    assignmentId: assignment.id,
                    durationMinutes: 10,
                    tinyStep: assignment.lastTinyStep
                )
            } label: {
                Text("Continue 10 min")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(DS.Colors.primaryButtonFg)
                    .background(DS.Colors.primaryButtonBg, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            }
            .buttonStyle(PressScaleButtonStyle())

            Button {
                showCompletionDecision = false
                dismiss()
            } label: {
                Text("Mark progress + stop")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.primary)
                    .background(DS.Colors.secondaryButtonBg, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            }
            .buttonStyle(PressScaleButtonStyle())
        }
    }

    // MARK: - Active Sprint Panel

    @ViewBuilder
    private func activeSprintPanel(session: SprintSession) -> some View {
        VStack(spacing: DS.Spacing.standard) {
            // Header
            VStack(spacing: 4) {
                Text("Sprint Active")
                    .font(.title2.weight(.semibold))
                Text(activeAssignmentTitle(for: session))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)

            // Large centered timer
            Text(remainingTimeText(for: session))
                .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .center)
                .contentTransition(.numericText())

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DS.Colors.progressTrack)
                        .frame(height: 6)
                    Capsule()
                        .fill(DS.Colors.accent)
                        .frame(width: geo.size.width * progress(for: session), height: 6)
                }
            }
            .frame(height: 6)
            .animation(.linear(duration: 1), value: progress(for: session))

            if !session.tinyStep.isEmpty {
                Text(session.tinyStep)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            VStack(spacing: DS.Spacing.micro) {
                Button {
                    onStart()
                } label: {
                    Text("Minimize")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(DS.Colors.primaryButtonFg)
                        .background(DS.Colors.primaryButtonBg, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                }
                .buttonStyle(PressScaleButtonStyle())

                Button {
                    sprintSessionManager.cancelActiveSession()
                } label: {
                    Text("Stop Sprint")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Colors.destructive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(DS.Colors.destructiveBg, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                }
                .buttonStyle(PressScaleButtonStyle())
            }
        }
    }

    // MARK: - Helpers

    private func activeAssignmentTitle(for session: SprintSession) -> String {
        guard let assignmentId = session.assignmentId,
              let matching = assignments.first(where: { $0.id == assignmentId }) else {
            return assignment.title
        }
        return matching.title
    }

    private func remainingTimeText(for session: SprintSession) -> String {
        let remainingSeconds = max(0, Int(ceil(session.endsAt.timeIntervalSince(sprintSessionManager.currentTime))))
        return String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    private func progress(for session: SprintSession) -> Double {
        let total = session.endsAt.timeIntervalSince(session.startedAt)
        guard total > 0 else { return 1 }
        let elapsed = sprintSessionManager.currentTime.timeIntervalSince(session.startedAt)
        return min(1, max(0, elapsed / total))
    }

    private func handleCompletionStateChange() {
        guard let completed = sprintSessionManager.lastCompletedSession,
              completed.assignmentId == assignment.id,
              handledCompletionId != completed.id else {
            return
        }
        handledCompletionId = completed.id
        showCompletionDecision = true
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

    return StartModeScreen(assignment: assignment, onStart: {})
        .environmentObject(store)
        .environmentObject(authManager)
        .environmentObject(sprintManager)
        .modelContainer(container)
}
