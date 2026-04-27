import SwiftUI
import SwiftData

struct AddAssignmentScreen: View {
    @EnvironmentObject private var assignmentStore: AssignmentStore
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var sprintSessionManager: SprintSessionManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var classesVM = ClassesViewModel()
    @Query(sort: \Assignment.dueDate) private var allAssignments: [Assignment]

    @State private var title = ""
    @State private var className = ""
    @State private var dueDate = Date(timeIntervalSinceNow: 86400)
    @State private var estMinutes = 30
    @State private var isFlexibleDueDate = false
    @State private var energyLevel: AssignmentEnergyLevel = .medium
    @State private var saveError: String?
    @State private var showUpsell = false
    @State private var pendingUpsellTrigger: UpsellTrigger?

    private let estimatedMinuteOptions = [30, 60, 120, 180, 240]
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.largeSection) {
                Text("Add Assignment")
                    .font(.largeTitle)

                VStack(alignment: .leading, spacing: DS.Spacing.standard) {
                    Text("Title")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("Enter assignment title", text: $title)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(DS.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(DS.Border.color, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: DS.Spacing.standard) {
                    Text("Class (optional)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    Menu {
                        Button("Personal") { className = "" }
                        if !classesVM.courses.isEmpty {
                            Divider()
                            ForEach(classesVM.courses) { course in
                                Button(course.name) {
                                    className = course.name
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(className.isEmpty ? "Personal" : className)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(DS.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(DS.Border.color, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.standard) {
                    Text("Due date")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }

                VStack(alignment: .leading, spacing: DS.Spacing.standard) {
                    Text("Estimated time")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    Picker("Estimated Minutes", selection: $estMinutes) {
                        ForEach(estimatedMinuteOptions, id: \.self) { minutes in
                            Text("\(minutes)m").tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.standard) {
                    Text("Schedule")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    Toggle("Flexible due date (can auto-spread)", isOn: $isFlexibleDueDate)
                        .font(.body)
                        .tint(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.standard) {
                    Text("Energy level")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    Picker("Energy", selection: $energyLevel) {
                        ForEach(AssignmentEnergyLevel.allCases, id: \.rawValue) { option in
                            Text(option.rawValue.capitalized).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(spacing: 10) {
                    Button(action: saveAssignment) {
                        Text("Save")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .foregroundStyle(DS.Colors.primaryButtonFg)
                            .background(DS.Colors.primaryButtonBg, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)

                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, DS.Spacing.standard)
            .padding(.vertical, DS.Spacing.standard)
        }
        .background(DS.screenBackground)
        .navigationTitle("New Assignment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .animation(.easeInOut(duration: 0.2), value: estMinutes)
        .animation(.easeInOut(duration: 0.2), value: energyLevel)
        .sheet(isPresented: $showUpsell) {
            ProPaywallView(trigger: pendingUpsellTrigger) {
                showUpsell = false
            }
        }
    }

    private func saveAssignment() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedClass = className.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else { return }

        let newAssignment = Assignment(
            id: UUID(),
            title: trimmedTitle,
            courseName: trimmedClass,
            dueDate: dueDate,
            estMinutes: estMinutes,
            isFlexibleDueDate: isFlexibleDueDate,
            energyLevel: energyLevel
        )

        if assignmentStore.addAssignment(newAssignment) {
            let newCount = allAssignments.count + 1
            let trigger = UpsellTrigger.manualAssignmentEntry(count: newCount)
            if UpsellTriggerManager.shared.shouldShowUpsell(
                for: trigger,
                isPro: subscriptionManager.isPremium,
                isSprintActive: sprintSessionManager.activeSession != nil
            ) {
                UpsellTriggerManager.shared.markShown(trigger: trigger)
                pendingUpsellTrigger = trigger
                showUpsell = true
            } else {
                dismiss()
            }
        } else {
            saveError = "The assignment title may be too long or already exists. Try a shorter title."
        }
    }
}

struct EmailSignInSheet: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var authAlertMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Email") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }
                Section("Password") {
                    SecureField("Password", text: $password)
                }

                Button("Sign In") {
                    Task {
                        isSubmitting = true
                        defer { isSubmitting = false }
                        let result = await authManager.signInWithEmail(email: email, password: password)
                        if case .success = result {
                            dismiss()
                        } else {
                            authAlertMessage = authManager.lastAuthErrorMessage ?? "Sign-in failed."
                        }
                    }
                }
                .disabled(isSubmitting)

                Button("Create Account") {
                    Task {
                        isSubmitting = true
                        defer { isSubmitting = false }
                        let result = await authManager.signUpWithEmail(email: email, password: password)
                        if case .success = result {
                            dismiss()
                        } else {
                            authAlertMessage = authManager.lastAuthErrorMessage ?? "Account creation failed."
                        }
                    }
                }
                .disabled(isSubmitting)
            }
            .navigationTitle("Email Sign In")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Email sign-in", isPresented: Binding(
                get: { authAlertMessage != nil },
                set: { if !$0 { authAlertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(authAlertMessage ?? "")
            }
        }
    }
}

struct StartModeEntryScreen: View {
    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @EnvironmentObject private var assignmentStore: AssignmentStore
    @EnvironmentObject private var sprintSessionManager: SprintSessionManager
    @Environment(\.dismiss) private var dismiss

    private var nextAssignment: Assignment? {
        assignments.first(where: { !$0.isCompleted })
    }

    private var assignmentForStartMode: Assignment? {
        if let activeAssignmentId = sprintSessionManager.activeSession?.assignmentId,
           let activeAssignment = assignments.first(where: { $0.id == activeAssignmentId }) {
            return activeAssignment
        }
        return nextAssignment
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let assignment = assignmentForStartMode {
                    StartModeScreen(assignment: assignment) {
                        dismiss()
                    }
                    .environmentObject(assignmentStore)
                    .environmentObject(sprintSessionManager)
                } else {
                    Text("You're all caught up.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .navigationTitle("Start Mode")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
