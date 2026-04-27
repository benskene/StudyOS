import SwiftUI
import SwiftData
import UserNotifications

struct TodayScreen: View {
    @EnvironmentObject private var assignmentStore: AssignmentStore
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var sprintSessionManager: SprintSessionManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @Query(sort: \FocusSprint.startTime, order: .reverse) private var sprints: [FocusSprint]
    @Query(sort: \DailyPlanItem.createdAt) private var dailyPlanItems: [DailyPlanItem]
    @AppStorage("hasRequestedNotifications") private var hasRequestedNotifications = false

    @Binding var isShowingAddAssignment: Bool

    @State private var isShowingEmailSignIn = false
    @State private var isShowingStartMode = false
    @State private var isShowingSettings = false
    @State private var isSigningIn = false
    @State private var authAlertMessage: String?
    @State private var authBannerMessage: String?
    @State private var editingPlanAssignment: Assignment?
    @State private var showEmptySchoolDayUpsell = false
    @State private var showUpgradeBanner = false
    private let calendar = Calendar.autoupdatingCurrent

    // MARK: - Derived data

    private var incompleteAssignments: [Assignment] {
        assignments.filter { !$0.isCompleted }
    }

    private var completedAssignments: [Assignment] {
        assignments.filter { $0.isCompleted }.reversed()
    }

    private var nextUp: Assignment? {
        incompleteAssignments.first
    }

    private var upcomingAssignments: [Assignment] {
        guard incompleteAssignments.count > 1 else { return [] }
        return Array(incompleteAssignments.dropFirst())
    }

    private var todayPlanItemsForToday: [DailyPlanItem] {
        let dayStart = calendar.startOfDay(for: Date())
        let slots: [DailyPlanSlotType] = [.must, .should, .quickWin]
        return slots.compactMap { slot in
            dailyPlanItems.first { $0.date == dayStart && $0.slotType == slot }
        }
    }

    private var planSlots: [(slot: DailyPlanSlotType, assignment: Assignment)] {
        todayPlanItemsForToday.compactMap { item in
            guard let assignment = assignments.first(where: { $0.id == item.assignmentId }) else { return nil }
            return (item.slotType, assignment)
        }
    }

    private var isDoneForToday: Bool {
        !planSlots.isEmpty && planSlots.allSatisfy { $0.assignment.isCompleted }
    }

    private var stretchAssignment: Assignment? {
        let plannedIds = Set(planSlots.map { $0.assignment.id })
        return incompleteAssignments.first(where: { !plannedIds.contains($0.id) })
    }

    private var relativeDateFormatter: RelativeDateTimeFormatter {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }

    private var headerDateText: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private func dueText(for assignment: Assignment) -> String {
        if !assignment.isCompleted && assignment.dueDate < Date() {
            return "Overdue"
        }
        return "Due \(relativeDateFormatter.localizedString(for: assignment.dueDate, relativeTo: Date()))"
    }

    private func isOverdue(_ assignment: Assignment) -> Bool {
        !assignment.isCompleted && assignment.dueDate < Date()
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                heroSection
                    .transition(.opacity)
                if showUpgradeBanner {
                    ProUpgradeBanner {
                        UpsellTriggerManager.shared.suppressBannerForTwoWeeks()
                        showUpgradeBanner = false
                    }
                    .transition(.opacity)
                }
                nextActionCard
                    .transition(.opacity)
                todayPlanSection
                    .transition(.opacity)
                priorityViewSection
                    .transition(.opacity)
                newUpcomingSection
                    .transition(.opacity)
                doneSection
                    .transition(.opacity)
                syncSection
                    .transition(.opacity)
            }
            .padding(.horizontal, DS.Spacing.standard)
            .padding(.top, DS.Spacing.standard)
            .padding(.bottom, DS.Spacing.largeSection)
        }
        .background(DS.screenBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                }
            }
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
        .sheet(isPresented: $isShowingStartMode) {
            StartModeEntryScreen()
                .environmentObject(assignmentStore)
                .environmentObject(sprintSessionManager)
        }
        .sheet(isPresented: $isShowingEmailSignIn) {
            EmailSignInSheet()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                SettingsScreen()
                    .environmentObject(authManager)
                    .environmentObject(assignmentStore)
                    .environmentObject(subscriptionManager)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingPlanAssignment != nil },
            set: { if !$0 { editingPlanAssignment = nil } }
        )) {
            if let assignment = editingPlanAssignment {
                NavigationStack {
                    AssignmentDetailScreen(assignment: assignment)
                        .environmentObject(assignmentStore)
                        .environmentObject(sprintSessionManager)
                }
            }
        }
        .onAppear {
            requestNotificationPermissionIfNeeded()
            assignmentStore.rebuildDailyPlan()
            assignmentStore.refreshTomorrowPreviewIfNeeded()
            checkEmptySchoolDayUpsell()
            checkBannerVisibility()
        }
        .sheet(isPresented: $showEmptySchoolDayUpsell) {
            ProPaywallView(trigger: .emptyAppOnSchoolDay) {
                showEmptySchoolDayUpsell = false
            }
        }
        .onChange(of: assignments.count) { _ in
            assignmentStore.rebuildDailyPlan()
        }
        .onChange(of: authManager.lastAuthEvent) { event in
            guard let event else { return }
            switch event {
            case .success(let provider):
                authBannerMessage = "\(providerTitle(provider)) sign-in succeeded. Sync enabled."
                clearAuthBannerAfterDelay()
            case .failure(_, let message):
                authAlertMessage = message
            case .canceled(let provider):
                authAlertMessage = "\(providerTitle(provider)) sign-in was canceled."
            }
            authManager.clearLastAuthEvent()
        }
        .alert("Sign-in status", isPresented: Binding(
            get: { authAlertMessage != nil },
            set: { if !$0 { authAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authAlertMessage ?? "")
        }
        .overlay(alignment: .top) {
            if let authBannerMessage {
                Text(authBannerMessage)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authBannerMessage)
        .animation(.easeInOut(duration: 0.22), value: assignments.count)
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: sprintSessionManager.activeSession != nil)
    }

    // MARK: - Hero


    private var heroSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Today")
                .font(.largeTitle.weight(.bold))
            Text(headerDateText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !incompleteAssignments.isEmpty {
                Text("\(incompleteAssignments.count) task\(incompleteAssignments.count == 1 ? "" : "s") remaining")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Next Action Card

    private var nextActionCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.standard) {
            Text("Next up")
                .font(.title3.weight(.semibold))

            if let session = sprintSessionManager.activeSession {
                VStack(alignment: .leading, spacing: 6) {
                    Text(activeSprintTitle(for: session))
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    HStack(spacing: DS.Spacing.micro) {
                        Text(activeSprintTimerText(for: session))
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("remaining")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    ProgressView(value: activeSprintProgress(for: session))
                        .tint(Color.accentColor)
                }

                Button {
                    isShowingStartMode = true
                } label: {
                    Text("View Sprint")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.primary)
                        .background(DS.Colors.secondaryButtonBg, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                }
                .buttonStyle(PressScaleButtonStyle())

            } else if let nextUp {
                VStack(alignment: .leading, spacing: 4) {
                    Text(nextUp.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Text("\(dueText(for: nextUp))  ·  Est. \(nextUp.estMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    startVisibleAssignment(nextUp)
                } label: {
                    Text("Start sprint")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(DS.Colors.primaryButtonFg)
                        .background(DS.Colors.primaryButtonBg, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                }
                .buttonStyle(PressScaleButtonStyle())
                .lockedIfNotPro(isPro: subscriptionManager.isPremium, trigger: .focusSprints, cornerRadius: DS.Radius.control)

            } else {
                Text("No open tasks. Add one to build your plan.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Button {
                    isShowingAddAssignment = true
                } label: {
                    Label("Add assignment", systemImage: "plus")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(DS.Colors.primaryButtonFg)
                        .background(DS.Colors.primaryButtonBg, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                }
                .buttonStyle(PressScaleButtonStyle())
            }
        }
        .padding(DS.Spacing.standard)
        .elevatedCard()
    }

    // MARK: - Today Plan

    private var todayPlanSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.standard) {
            SectionHeader("Today's plan", actionLabel: "Rebuild") {
                assignmentStore.rebuildDailyPlan()
            }

            if isDoneForToday {
                VStack(alignment: .leading, spacing: DS.Spacing.micro) {
                    Text("You're done for today 🎉")
                        .font(.body.weight(.semibold))
                    if let stretchAssignment {
                        Text("Optional stretch: \(stretchAssignment.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if planSlots.isEmpty {
                Text("No plan yet. Add an assignment or tap Rebuild.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(planSlots.enumerated()), id: \.element.assignment.id) { index, slot in
                        planRow(slot: slot.slot, assignment: slot.assignment)
                        if index < planSlots.count - 1 {
                            Divider().overlay(DS.Border.color)
                        }
                    }
                }
            }
        }
        .padding(DS.Spacing.standard)
        .elevatedCard()
    }

    private func planRow(slot: DailyPlanSlotType, assignment: Assignment) -> some View {
        let overdue = isOverdue(assignment)
        return HStack(alignment: .top, spacing: DS.Spacing.standard) {
            SlotBadge(slot: slot)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(assignment.title)
                    .font(.body)
                    .strikethrough(assignment.isCompleted, color: .secondary)
                Text(overdue ? "Overdue" : "\(dueText(for: assignment)) · Est. \(assignment.estMinutes) min")
                    .font(.caption.weight(overdue ? .semibold : .regular))
                    .foregroundStyle(overdue ? DS.Colors.destructive : Color.secondary)
            }
            Spacer()
            if !assignment.isCompleted {
                HStack(spacing: DS.Spacing.xs) {
                    // Quick-complete inline button
                    Button {
                        assignmentStore.toggleCompleted(assignment)
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.title3)
                            .foregroundStyle(DS.Colors.secondaryText)
                    }
                    .buttonStyle(.plain)

                    Button("Start") {
                        startVisibleAssignment(assignment)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(DS.Colors.accent)
                    .cornerRadius(20)
                    .lockedIfNotPro(isPro: subscriptionManager.isPremium, trigger: .focusSprints, cornerRadius: 20)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .opacity(assignment.isCompleted ? 0.55 : 1)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                assignmentStore.deleteAssignment(assignment)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                editingPlanAssignment = assignment
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    // MARK: - Priority View

    private var priorityViewSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.standard) {
            Text("Priority View")
                .font(.title3.weight(.semibold))

            let topPriority = Array(
                incompleteAssignments
                    .sorted { $0.priorityScore > $1.priorityScore }
                    .prefix(3)
            )

            if topPriority.isEmpty {
                Text("Add assignments to see urgency ranking.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(topPriority.enumerated()), id: \.element.id) { index, assignment in
                        HStack(spacing: DS.Spacing.standard) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(DS.Colors.secondaryText)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(assignment.title)
                                    .font(.body)
                                    .lineLimit(1)
                                Text(dueText(for: assignment))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        if index < topPriority.count - 1 {
                            Divider().overlay(DS.Border.color)
                        }
                    }
                }
            }
        }
        .padding(DS.Spacing.standard)
        .elevatedCard()
    }

    // MARK: - Upcoming

    private var newUpcomingSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.standard) {
            SectionHeader("Upcoming", actionLabel: "Add") {
                isShowingAddAssignment = true
            }

            let tasksToShow = nextUp == nil ? incompleteAssignments : upcomingAssignments

            if tasksToShow.isEmpty {
                Text(assignments.isEmpty
                    ? "No assignments yet. Add one to get started."
                    : "Nothing else in the queue."
                )
                .font(.body)
                .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(tasksToShow.enumerated()), id: \.element.id) { index, assignment in
                        taskRow(assignment: assignment)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    assignmentStore.deleteAssignment(assignment)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        if index < tasksToShow.count - 1 {
                            Divider().overlay(DS.Border.color)
                        }
                    }
                }
            }
        }
        .padding(DS.Spacing.standard)
        .elevatedCard()
    }

    // MARK: - Done

    private var doneSection: some View {
        Group {
            if !completedAssignments.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.standard) {
                    SectionHeader("Completed")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(completedAssignments.enumerated()), id: \.element.id) { index, assignment in
                            taskRow(assignment: assignment, isDoneSection: true)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        assignmentStore.deleteAssignment(assignment)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            if index < completedAssignments.count - 1 {
                                Divider().overlay(DS.Border.color)
                            }
                        }
                    }
                }
                .padding(DS.Spacing.standard)
                .elevatedCard()
                .opacity(0.75)
            }
        }
    }

    // MARK: - Task Row

    private func taskRow(assignment: Assignment, isDoneSection: Bool = false) -> some View {
        NavigationLink {
            AssignmentDetailScreen(assignment: assignment)
        } label: {
            HStack(alignment: .top, spacing: DS.Spacing.standard) {
                Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(assignment.isCompleted ? .secondary : .primary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(assignment.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .strikethrough(assignment.isCompleted, color: .secondary)
                    HStack(spacing: DS.Spacing.xs) {
                        let overdue = isOverdue(assignment)
                        Text(dueText(for: assignment))
                            .font(.caption.weight(overdue ? .semibold : .regular))
                            .foregroundStyle(overdue ? DS.Colors.destructive : Color.secondary)
                        if !overdue {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text("\(assignment.estMinutes) min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(assignment.isCompleted ? 0.5 : 1)
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Sync Section (subtle footer)

    private var syncSection: some View {
        HStack(spacing: 6) {
            if assignmentStore.isSyncing {
                ProgressView().scaleEffect(0.55)
                Text("Syncing…")
                    .font(.caption2)
                    .foregroundStyle(DS.Colors.secondaryText)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                switch authManager.authState {
                case .signedIn:
                    Text("Sync enabled")
                        .font(.caption2)
                case .resolving:
                    Text("Checking sync…")
                        .font(.caption2)
                case .signedOut, .error:
                    Button {
                        isShowingSettings = true
                    } label: {
                        Text("Sign in to enable sync")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DS.Colors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .foregroundStyle(DS.Colors.secondaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - Upsell

    private func checkBannerVisibility() {
        showUpgradeBanner = UpsellTriggerManager.shared.shouldShowBanner(isPro: subscriptionManager.isPremium)
    }

    private func checkEmptySchoolDayUpsell() {
        let weekday = calendar.component(.weekday, from: Date())
        let isSchoolDay = weekday >= 2 && weekday <= 6
        guard isSchoolDay else { return }
        guard incompleteAssignments.isEmpty else { return }
        let trigger = UpsellTrigger.emptyAppOnSchoolDay
        if UpsellTriggerManager.shared.shouldShowUpsell(
            for: trigger,
            isPro: subscriptionManager.isPremium,
            isSprintActive: sprintSessionManager.activeSession != nil
        ) {
            UpsellTriggerManager.shared.markShown(trigger: trigger)
            showEmptySchoolDayUpsell = true
        }
    }

    // MARK: - Notification

    private func requestNotificationPermissionIfNeeded() {
        guard !hasRequestedNotifications else { return }
        NotificationManager.shared.requestPermission { granted in
            hasRequestedNotifications = true
            guard granted else { return }
            assignmentStore.handleNotificationPermissionGranted()
        }
    }

    // MARK: - Sprint helpers

    private func activeSprintTitle(for session: SprintSession) -> String {
        guard let assignmentId = session.assignmentId,
              let assignment = assignments.first(where: { $0.id == assignmentId }) else {
            return "No assignment linked"
        }
        return assignment.title
    }

    private func activeSprintTimerText(for session: SprintSession) -> String {
        let remaining = max(0, Int(ceil(session.endsAt.timeIntervalSince(sprintSessionManager.currentTime))))
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    private func activeSprintProgress(for session: SprintSession) -> Double {
        let total = session.endsAt.timeIntervalSince(session.startedAt)
        guard total > 0 else { return 1 }
        let elapsed = sprintSessionManager.currentTime.timeIntervalSince(session.startedAt)
        return min(1, max(0, elapsed / total))
    }

    private func startVisibleAssignment(_ assignment: Assignment?) {
        guard let assignment else {
            isShowingStartMode = true
            return
        }
        NotificationManager.shared.cancelUnstartedSprintReminder(for: assignment.id)
        _ = sprintSessionManager.startSession(
            assignmentId: assignment.id,
            durationMinutes: 5,
            tinyStep: assignment.lastTinyStep
        )
    }

    // MARK: - Auth helpers

    private func performAppleSignIn() async {
        guard authManager.isAppleSignInAvailable else {
            authAlertMessage = authManager.unavailableProviderReason(for: .apple)
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }
        _ = await authManager.signInWithApple()
    }

    private func performGoogleSignIn() async {
        guard authManager.isGoogleSignInAvailable else {
            authAlertMessage = authManager.unavailableProviderReason(for: .google)
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }
        _ = await authManager.signInWithGoogle()
    }

    private func clearAuthBannerAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { authBannerMessage = nil }
        }
    }

    private func providerTitle(_ provider: AuthManager.AuthProvider) -> String {
        switch provider {
        case .apple: return "Apple"
        case .google: return "Google"
        case .email: return "Email"
        }
    }
}
