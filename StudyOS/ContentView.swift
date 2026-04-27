import SwiftUI
import Combine
import SwiftData
import UserNotifications

struct ContentView: View {
    private enum Tab: Hashable {
        case today
        case week
        case classes
        case insights
    }

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("preferredStudyTime") private var preferredStudyTimeRaw = "evening"
    @EnvironmentObject private var assignmentStore: AssignmentStore
    @EnvironmentObject private var sprintSessionManager: SprintSessionManager
    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @State private var selectedTab: Tab = .today
    @State private var isShowingOnboarding = false
    @State private var hasShownOnboardingThisSession = false
    @State private var isShowingAddAssignment = false
    @State private var pendingAddAssignment = false
    @State private var confirmationBannerText: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayScreen(isShowingAddAssignment: $isShowingAddAssignment)
            }
            .tabItem {
                Label("Today", systemImage: "checkmark.circle")
            }
            .tag(Tab.today)

            NavigationStack {
                WeekViewScreen()
            }
            .tabItem {
                Label("Week", systemImage: "calendar")
            }
            .tag(Tab.week)

            NavigationStack {
                ClassesTabView()
            }
            .tabItem {
                Label("Classes", systemImage: "list.bullet.clipboard")
            }
            .tag(Tab.classes)

            NavigationStack {
                InsightsRootScreen()
            }
            .tabItem {
                Label("Insights", systemImage: "chart.bar")
            }
            .tag(Tab.insights)
        }
        .fullScreenCover(isPresented: $isShowingOnboarding, onDismiss: handleOnboardingDismissed) {
            OnboardingView(
                onSkip: { preference in completeOnboarding(launchAddAssignment: false, preference: preference, addSampleAssignment: false) },
                onAddFirstAssignment: { preference in completeOnboarding(launchAddAssignment: true, preference: preference, addSampleAssignment: false) },
                onExplore: { preference in completeOnboarding(launchAddAssignment: false, preference: preference, addSampleAssignment: false) }
            )
        }
        .onAppear {
            updateOnboardingPresentation()
            if let message = sprintSessionManager.recoveryMessage {
                showRecoveryBanner(message)
            }
        }
        .onReceive(sprintSessionManager.$recoveryMessage.compactMap { $0 }) { message in
            showRecoveryBanner(message)
        }
        .onChange(of: assignments.count) { _ in
            updateOnboardingPresentation()
        }
        .overlay(alignment: .top) {
            if let confirmationBannerText {
                Text(confirmationBannerText)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: confirmationBannerText)
    }

    private func updateOnboardingPresentation() {
        guard !hasShownOnboardingThisSession else { return }
        let shouldShow = !hasCompletedOnboarding
        if shouldShow {
            isShowingOnboarding = true
            hasShownOnboardingThisSession = true
        }
    }

    private func completeOnboarding(
        launchAddAssignment: Bool,
        preference: StudyTimePreference,
        addSampleAssignment: Bool
    ) {
        hasCompletedOnboarding = true
        preferredStudyTimeRaw = preference.rawValue
        pendingAddAssignment = launchAddAssignment
        selectedTab = .today
        if addSampleAssignment {
            addSampleAssignmentIfNeeded()
        }
        isShowingOnboarding = false
    }

    private func handleOnboardingDismissed() {
        guard pendingAddAssignment else { return }
        pendingAddAssignment = false
        isShowingAddAssignment = true
    }

    private func showRecoveryBanner(_ message: String) {
        showBanner(message) {
            sprintSessionManager.clearRecoveryMessage()
        }
    }

    private func showBanner(_ text: String, onDismiss: (() -> Void)? = nil) {
        confirmationBannerText = text
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            await MainActor.run {
                if confirmationBannerText == text {
                    confirmationBannerText = nil
                }
                onDismiss?()
            }
        }
    }

    private func addSampleAssignmentIfNeeded() {
        guard assignments.isEmpty else { return }
        let dueDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let sample = Assignment(
            id: UUID(),
            title: "Sample: Read chapter and write 3 bullet notes",
            courseName: "General",
            dueDate: dueDate,
            estMinutes: 20,
            isFlexibleDueDate: true,
            energyLevel: .medium
        )
        _ = assignmentStore.addAssignment(sample)
    }
}


#Preview {
    let container = ModelContainerProvider.make(inMemory: true)
    let authManager = AuthManager()
    let sprintManager = SprintSessionManager()
    let store = AssignmentStore(modelContext: container.mainContext, authManager: authManager, sprintSessionManager: sprintManager)

    return ContentView()
        .environmentObject(store)
        .environmentObject(authManager)
        .environmentObject(sprintManager)
        .modelContainer(container)
}
