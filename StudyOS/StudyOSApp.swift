//
//  StrucApp.swift
//  Struc
//
//  Created by Ben Skene on 2/2/26.
//

import SwiftUI
import SwiftData
#if canImport(FirebaseCore)
import FirebaseCore
#endif

@main
struct StrucApp: App {
    let container: ModelContainer
    @StateObject private var authManager: AuthManager
    @StateObject private var sprintSessionManager: SprintSessionManager
    @StateObject private var assignmentStore: AssignmentStore
    @StateObject private var subscriptionManager = SubscriptionManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = ModelContainerProvider.make()
        self.container = container
        let auth = AuthManager()
        let sprint = SprintSessionManager()
        _authManager = StateObject(wrappedValue: auth)
        _sprintSessionManager = StateObject(wrappedValue: sprint)
        _assignmentStore = StateObject(
            wrappedValue: AssignmentStore(
                modelContext: container.mainContext,
                authManager: auth,
                sprintSessionManager: sprint
            )
        )
    }

    @AppStorage("studyos.auth.skipped") private var hasSkippedAuth = false

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.authState == .resolving {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Resolving account…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if case .signedIn = authManager.authState {
                    ContentView()
                        .environmentObject(authManager)
                        .environmentObject(assignmentStore)
                        .environmentObject(sprintSessionManager)
                        .environmentObject(subscriptionManager)
                } else if !hasSkippedAuth {
                    AuthScreen()
                        .environmentObject(authManager)
                } else {
                    ContentView()
                        .environmentObject(authManager)
                        .environmentObject(assignmentStore)
                        .environmentObject(sprintSessionManager)
                        .environmentObject(subscriptionManager)
                }
            }
            .onAppear {
                assignmentStore.processCompletedSprintIfNeeded()
            }
        }
        .onChange(of: scenePhase) { phase in
            sprintSessionManager.handleScenePhaseChange(phase)
            if phase == .active {
                UpsellTriggerManager.shared.resetSessionFlag()
                assignmentStore.processCompletedSprintIfNeeded()
                Task { await assignmentStore.backgroundSyncGoogleClassroom() }
                Task { await assignmentStore.backgroundSyncCanvas() }
            }
        }
        .modelContainer(container)
    }
}
