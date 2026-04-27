import SwiftUI
import SwiftData

// MARK: - Main Tab View

struct ClassesTabView: View {
    @StateObject private var viewModel = ClassesViewModel()
    @EnvironmentObject private var assignmentStore: AssignmentStore
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Query(sort: \Assignment.dueDate) private var allAssignments: [Assignment]

    @State private var showAddCourse = false
    @State private var editingCourse: Course?
    @State private var addAssignmentForCourse: Course?
    @State private var expandedCourseIds: Set<UUID> = []
    @State private var courseToDelete: Course?
    @State private var showGoogleClassroomImport = false
    @State private var showCanvasImport = false
    @State private var showPaywall = false
    @State private var showAddPersonalAssignment = false
    @State private var isPersonalSectionExpanded = true

    private var personalAssignments: [Assignment] {
        viewModel.personalAssignments(from: allAssignments)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.standard) {
                filterChipBar
                    .padding(.bottom, DS.Spacing.xs)

                importButtonsRow

                if viewModel.courses.isEmpty && personalAssignments.isEmpty {
                    emptyStateView
                } else {
                    if !viewModel.courses.isEmpty {
                        courseSections
                    }
                    if !personalAssignments.isEmpty && viewModel.selectedCourseId == nil {
                        personalSection
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.standard)
            .padding(.vertical, DS.Spacing.standard)
        }
        .background(DS.screenBackground)
        .navigationTitle("Classes")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddCourse = true
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showAddCourse) {
            AddCourseSheet(viewModel: viewModel)
        }
        .sheet(item: $editingCourse) { course in
            AddCourseSheet(viewModel: viewModel, editingCourse: course)
        }
        .sheet(item: $addAssignmentForCourse) { course in
            AddAssignmentToCourseSheet(course: course, assignmentStore: assignmentStore)
        }
        .sheet(isPresented: $showAddPersonalAssignment) {
            NavigationStack {
                AddAssignmentScreen()
                    .environmentObject(assignmentStore)
            }
        }
        .sheet(isPresented: $showGoogleClassroomImport) {
            NavigationStack {
                LMSImportFlowScreen(provider: GoogleClassroomProvider()) { _ in
                    showGoogleClassroomImport = false
                    let names = Array(Set(allAssignments.compactMap {
                        $0.isDeleted || $0.courseName.isEmpty ? nil : $0.courseName
                    }))
                    viewModel.syncFromExistingClassNames(names)
                }
                .environmentObject(authManager)
                .environmentObject(assignmentStore)
            }
        }
        .sheet(isPresented: $showCanvasImport) {
            CanvasImportFlowScreen { _ in
                showCanvasImport = false
                let names = Array(Set(allAssignments.compactMap {
                    $0.isDeleted || $0.courseName.isEmpty ? nil : $0.courseName
                }))
                viewModel.syncFromExistingClassNames(names)
            }
            .environmentObject(authManager)
            .environmentObject(assignmentStore)
        }
        .sheet(isPresented: $showPaywall) {
            ProPaywallView()
                .environmentObject(subscriptionManager)
        }
        .onAppear {
            let existingNames = Array(Set(allAssignments.compactMap {
                $0.isDeleted ? nil : $0.courseName
            })).sorted()
            viewModel.syncFromExistingClassNames(existingNames)

            // Expand all on first appearance
            if expandedCourseIds.isEmpty {
                expandedCourseIds = Set(viewModel.courses.map(\.id))
            }
        }
        .onChange(of: viewModel.courses.count) { _ in
            // Expand any newly added courses
            for course in viewModel.courses {
                expandedCourseIds.insert(course.id)
            }
        }
        .alert("Delete \"\(courseToDelete?.name ?? "")\"?", isPresented: Binding(
            get: { courseToDelete != nil },
            set: { if !$0 { courseToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let course = courseToDelete {
                    withAnimation { viewModel.deleteCourse(course) }
                }
                courseToDelete = nil
            }
            Button("Cancel", role: .cancel) { courseToDelete = nil }
        } message: {
            Text("This will remove the class. Assignments will not be deleted.")
        }
    }

    // MARK: - Subviews

    private var importButtonsRow: some View {
        HStack(spacing: DS.Spacing.micro) {
            Button {
                if subscriptionManager.isPremium {
                    showGoogleClassroomImport = true
                } else {
                    showPaywall = true
                }
            } label: {
                HStack(spacing: DS.Spacing.micro) {
                    Image(systemName: "graduationcap.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Google Classroom")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Import")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !subscriptionManager.isPremium {
                        ProBadge(size: .small)
                    }
                }
                .padding(DS.Spacing.micro)
                .elevatedCard()
            }
            .buttonStyle(PressScaleButtonStyle())

            Button {
                if subscriptionManager.isPremium {
                    showCanvasImport = true
                } else {
                    showPaywall = true
                }
            } label: {
                HStack(spacing: DS.Spacing.micro) {
                    Image(systemName: "square.and.pencil")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Canvas")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Import")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !subscriptionManager.isPremium {
                        ProBadge(size: .small)
                    }
                }
                .padding(DS.Spacing.micro)
                .elevatedCard()
            }
            .buttonStyle(PressScaleButtonStyle())
        }
    }

    private var personalSection: some View {
        PersonalSectionView(
            assignments: personalAssignments,
            isExpanded: isPersonalSectionExpanded,
            onToggleExpand: {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isPersonalSectionExpanded.toggle()
                }
            },
            onAddAssignment: {
                showAddPersonalAssignment = true
            },
            onToggleComplete: { assignment in
                assignmentStore.toggleCompleted(assignment)
            },
            onDeleteAssignment: { assignment in
                assignmentStore.deleteAssignment(assignment)
            }
        )
    }

    private var filterChipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.micro) {
                FilterChip(
                    label: "All",
                    color: DS.Colors.accent,
                    isSelected: viewModel.selectedCourseId == nil
                ) {
                    viewModel.selectedCourseId = nil
                }

                ForEach(viewModel.courses) { course in
                    FilterChip(
                        label: course.name,
                        color: viewModel.color(for: course),
                        isSelected: viewModel.selectedCourseId == course.id
                    ) {
                        viewModel.selectedCourseId = course.id
                    }
                    .contextMenu {
                        Button {
                            editingCourse = course
                        } label: {
                            Label("Edit Class", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            courseToDelete = course
                        } label: {
                            Label("Delete Class", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var courseSections: some View {
        VStack(spacing: DS.Spacing.micro) {
            ForEach(viewModel.filteredCourses(allAssignments: allAssignments)) { course in
                CourseSectionView(
                    course: course,
                    assignments: viewModel.assignments(for: course, from: allAssignments),
                    accentColor: viewModel.color(for: course),
                    isExpanded: expandedCourseIds.contains(course.id),
                    onToggleExpand: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            if expandedCourseIds.contains(course.id) {
                                expandedCourseIds.remove(course.id)
                            } else {
                                expandedCourseIds.insert(course.id)
                            }
                        }
                    },
                    onAddAssignment: {
                        addAssignmentForCourse = course
                    },
                    onEditCourse: {
                        editingCourse = course
                    },
                    onDeleteCourse: {
                        courseToDelete = course
                    },
                    onToggleComplete: { assignment in
                        assignmentStore.toggleCompleted(assignment)
                    },
                    onDeleteAssignment: { assignment in
                        assignmentStore.deleteAssignment(assignment)
                    }
                )
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: DS.Spacing.standard) {
            Spacer(minLength: 64)

            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(DS.Colors.secondaryText)

            VStack(spacing: DS.Spacing.xs) {
                Text("No classes yet")
                    .font(.title3.weight(.semibold))
                Text("Add your classes to organize\nassignments by subject.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showAddCourse = true
            } label: {
                Text("Add your first class")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, DS.Spacing.section)
                    .padding(.vertical, 13)
                    .foregroundStyle(DS.Colors.primaryButtonFg)
                    .background(
                        DS.Colors.primaryButtonBg,
                        in: Capsule()
                    )
            }
            .buttonStyle(PressScaleButtonStyle())
            .padding(.top, DS.Spacing.xs)

            Spacer(minLength: 64)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Spacing.section)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, DS.Spacing.standard)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? .white : color)
                .background {
                    if isSelected {
                        Capsule().fill(color)
                    } else {
                        Capsule()
                            .stroke(color, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(PressScaleButtonStyle())
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Course Section

private struct CourseSectionView: View {
    let course: Course
    let assignments: [Assignment]
    let accentColor: Color
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onAddAssignment: () -> Void
    let onEditCourse: () -> Void
    let onDeleteCourse: () -> Void
    let onToggleComplete: (Assignment) -> Void
    let onDeleteAssignment: (Assignment) -> Void

    private var completedCount: Int { assignments.filter(\.isCompleted).count }

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            HStack(spacing: 0) {
                Button(action: onToggleExpand) {
                    HStack(spacing: DS.Spacing.micro) {
                        // Color accent bar
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(accentColor)
                            .frame(width: 4, height: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if !course.teacher.isEmpty {
                                Text(course.teacher)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text("\(completedCount)/\(assignments.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.22), value: isExpanded)
                    }
                    .padding(.leading, DS.Spacing.standard)
                    .padding(.trailing, DS.Spacing.xs)
                    .padding(.vertical, DS.Spacing.micro)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        onEditCourse()
                    } label: {
                        Label("Edit Class", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDeleteCourse()
                    } label: {
                        Label("Delete Class", systemImage: "trash")
                    }
                }

                Menu {
                    Button {
                        onEditCourse()
                    } label: {
                        Label("Edit Class", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDeleteCourse()
                    } label: {
                        Label("Delete Class", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
            }

            // Assignments list (collapsible)
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.leading, DS.Spacing.standard)

                    if assignments.isEmpty {
                        HStack {
                            Text("No assignments")
                                .font(.subheadline)
                                .foregroundStyle(DS.Colors.secondaryText)
                            Spacer()
                        }
                        .padding(.horizontal, DS.Spacing.standard)
                        .padding(.vertical, DS.Spacing.micro)
                    } else {
                        ForEach(assignments) { assignment in
                            AssignmentRow(
                                assignment: assignment,
                                accentColor: accentColor,
                                onToggleComplete: { onToggleComplete(assignment) },
                                onDelete: { onDeleteAssignment(assignment) }
                            )

                            if assignment.id != assignments.last?.id {
                                Divider()
                                    .padding(.leading, 52)
                            }
                        }
                    }

                    Divider()
                        .padding(.leading, DS.Spacing.standard)

                    // Add assignment button
                    Button(action: onAddAssignment) {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "plus.circle")
                                .font(.subheadline)
                                .foregroundStyle(accentColor)
                            Text("Add assignment")
                                .font(.subheadline)
                                .foregroundStyle(accentColor)
                            Spacer()
                        }
                        .padding(.horizontal, DS.Spacing.standard)
                        .padding(.vertical, DS.Spacing.micro)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .elevatedCard()
    }
}

// MARK: - Assignment Row

private struct AssignmentRow: View {
    let assignment: Assignment
    let accentColor: Color
    let onToggleComplete: () -> Void
    let onDelete: () -> Void

    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var isPastDue: Bool {
        !assignment.isCompleted && assignment.dueDate < Date()
    }

    var body: some View {
        HStack(spacing: DS.Spacing.micro) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accentColor.opacity(assignment.isCompleted ? 0.3 : 0.8))
                .frame(width: 3)
                .padding(.vertical, 8)

            // Completion toggle
            Button(action: onToggleComplete) {
                Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(assignment.isCompleted ? accentColor : DS.Colors.secondaryText)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: assignment.isCompleted)
            }
            .buttonStyle(.plain)

            // Title and due date
            VStack(alignment: .leading, spacing: 2) {
                Text(assignment.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(assignment.isCompleted ? .secondary : .primary)
                    .strikethrough(assignment.isCompleted, color: .secondary)
                    .lineLimit(2)

                Text(Self.dueDateFormatter.string(from: assignment.dueDate))
                    .font(.caption)
                    .foregroundStyle(isPastDue ? DS.Colors.destructive : DS.Colors.secondaryText)
            }

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.standard)
        .padding(.vertical, DS.Spacing.micro)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Personal Section

private struct PersonalSectionView: View {
    let assignments: [Assignment]
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onAddAssignment: () -> Void
    let onToggleComplete: (Assignment) -> Void
    let onDeleteAssignment: (Assignment) -> Void

    private var completedCount: Int { assignments.filter(\.isCompleted).count }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggleExpand) {
                HStack(spacing: DS.Spacing.micro) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 4, height: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Personal")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Text("\(completedCount)/\(assignments.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.22), value: isExpanded)
                }
                .padding(.leading, DS.Spacing.standard)
                .padding(.trailing, DS.Spacing.xs)
                .padding(.vertical, DS.Spacing.micro)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.leading, DS.Spacing.standard)

                    ForEach(assignments) { assignment in
                        AssignmentRow(
                            assignment: assignment,
                            accentColor: .secondary,
                            onToggleComplete: { onToggleComplete(assignment) },
                            onDelete: { onDeleteAssignment(assignment) }
                        )
                        if assignment.id != assignments.last?.id {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }

                    Divider()
                        .padding(.leading, DS.Spacing.standard)

                    Button(action: onAddAssignment) {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "plus.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Add personal assignment")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, DS.Spacing.standard)
                        .padding(.vertical, DS.Spacing.micro)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .elevatedCard()
    }
}

// MARK: - Add Assignment To Course Sheet

struct AddAssignmentToCourseSheet: View {
    @Environment(\.dismiss) private var dismiss
    let course: Course
    let assignmentStore: AssignmentStore

    @State private var title = ""
    @State private var dueDate = Date(timeIntervalSinceNow: 86400)
    @State private var estMinutes = 60
    @State private var isFlexibleDueDate = false
    @State private var energyLevel: AssignmentEnergyLevel = .medium
    @State private var saveError: String?

    private let estimatedMinuteOptions = [30, 60, 120, 180, 240]

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.largeSection) {
                    Text("Add Assignment")
                        .font(.largeTitle)

                    // Course pill (read-only)
                    HStack(spacing: DS.Spacing.xs) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(hex: course.colorHex))
                            .frame(width: 6, height: 16)
                        Text(course.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, DS.Spacing.standard)
                    .padding(.vertical, DS.Spacing.micro)
                    .background(
                        Color(hex: course.colorHex).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    )

                    // Title
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
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

                    // Due date
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("Due date")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                        DatePicker("", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }

                    // Estimated time
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
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

                    // Schedule
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("Schedule")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                        Toggle("Flexible due date (can auto-spread)", isOn: $isFlexibleDueDate)
                            .font(.body)
                            .tint(Color(hex: course.colorHex))
                    }

                    // Energy level
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
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

                    // Save
                    Button(action: save) {
                        Text("Save")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .foregroundStyle(DS.Colors.primaryButtonFg)
                            .background(
                                DS.Colors.primaryButtonBg,
                                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            )
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)
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
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let newAssignment = Assignment(
            id: UUID(),
            title: trimmedTitle,
            courseName: course.name,
            dueDate: dueDate,
            estMinutes: estMinutes,
            isFlexibleDueDate: isFlexibleDueDate,
            energyLevel: energyLevel
        )

        if assignmentStore.addAssignment(newAssignment) {
            dismiss()
        } else {
            saveError = "The assignment title may be too long or already exists."
        }
    }
}
