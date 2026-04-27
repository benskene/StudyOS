import SwiftUI
import SwiftData
import UserNotifications

struct SettingsScreen: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var assignmentStore: AssignmentStore
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @AppStorage("dailySprintNudgeEnabled") private var dailySprintNudgeEnabled = false
    @State private var isShowingEmailSignIn = false
    @State private var isSigningIn = false
    @State private var authAlertMessage: String?
    @State private var showGoogleClassroomImport = false
    @State private var showProPaywall = false
    @State private var proPaywallTrigger: UpsellTrigger? = nil
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteErrorMessage: String?
    @State private var showReauthForDeletion = false

    var body: some View {
        List {
            Section("Plan") {
                ProSettingsRow(isPro: subscriptionManager.isPremium) {
                    proPaywallTrigger = nil
                    showProPaywall = true
                }
            }

            Section("Account & Sync") {
                switch authManager.authState {
                case .signedIn:
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Sign Out") {
                        _ = authManager.signOut()
                    }
                    if isDeletingAccount {
                        HStack(spacing: DS.Spacing.xs) {
                            ProgressView()
                            Text("Deleting account…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Delete Account", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    }
                case .signedOut:
                    Text("Signed out")
                    Button("Sign in with Apple") {
                        Task { await performAppleSignIn() }
                    }
                    .disabled(isSigningIn || !authManager.isAppleSignInAvailable)
                    Button("Sign in with Google") {
                        Task { await performGoogleSignIn() }
                    }
                    .disabled(isSigningIn || !authManager.isGoogleSignInAvailable)
                    Button("Sign in with Email") {
                        isShowingEmailSignIn = true
                    }
                    .disabled(isSigningIn || authManager.unavailableProviderReason(for: .email) != nil)
                case .resolving:
                    Text("Resolving session…")
                case .error(let message):
                    Text("Auth error: \(message)")
                }

                if let googleReason = authManager.unavailableProviderReason(for: .google) {
                    Text(googleReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let appleReason = authManager.unavailableProviderReason(for: .apple) {
                    Text(appleReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Pending writes", value: "\(assignmentStore.pendingWritesCount)")
                if let lastSyncDate = assignmentStore.lastSyncDate {
                    LabeledContent("Last sync", value: lastSyncDate.formatted(date: .abbreviated, time: .shortened))
                } else {
                    LabeledContent("Last sync", value: "Never")
                }
                LabeledContent("Sync mode", value: syncPhaseText)
                Button("Sync Now") {
                    Task { await assignmentStore.performManualSync() }
                }
                .disabled(authManager.currentUserId == nil)
                if authManager.currentUserId == nil {
                    Text("Sign in to enable cloud sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Notifications") {
                NavigationLink("Notification Preferences") {
                    NotificationPreferencesScreen()
                        .environmentObject(assignmentStore)
                }
                Text(permissionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Integrations") {
                Button {
                    let trigger = UpsellTrigger.integrationSettingsTap
                    if UpsellTriggerManager.shared.shouldShowUpsell(
                        for: trigger,
                        isPro: subscriptionManager.isPremium,
                        isSprintActive: false
                    ) {
                        UpsellTriggerManager.shared.markShown(trigger: trigger)
                        proPaywallTrigger = trigger
                        showProPaywall = true
                    } else {
                        showGoogleClassroomImport = true
                    }
                } label: {
                    Label("Import from Google Classroom", systemImage: "graduationcap")
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                Text("Struc helps students track assignments, plan their day, and stay consistent with sprint-based focus sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingEmailSignIn) {
            EmailSignInSheet()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showGoogleClassroomImport) {
            NavigationStack {
                LMSImportFlowScreen(provider: GoogleClassroomProvider(), onImported: { _ in
                    showGoogleClassroomImport = false
                })
                .environmentObject(authManager)
                .environmentObject(assignmentStore)
            }
        }
        .sheet(isPresented: $showProPaywall) {
            ProPaywallView(trigger: proPaywallTrigger) {
                showProPaywall = false
            }
        }
        .confirmationDialog(
            "Delete Account",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await deleteAccountFlow() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account and all your data. This action cannot be undone.")
        }
        .sheet(isPresented: $showReauthForDeletion) {
            ReauthForDeletionSheet { email, password in
                Task {
                    let reauth = await authManager.signInWithEmail(email: email, password: password)
                    if case .success = reauth {
                        showReauthForDeletion = false
                        await deleteAccountFlow()
                    } else if case .failure(let err) = reauth {
                        deleteErrorMessage = err.localizedDescription
                        showReauthForDeletion = false
                    }
                }
            }
            .environmentObject(authManager)
        }
        .alert("Deletion Failed", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .task {
            await refreshNotificationStatus()
            applySprintNudgeSetting()
        }
        .onChange(of: dailySprintNudgeEnabled) { _ in
            applySprintNudgeSetting()
        }
        .onChange(of: authManager.lastAuthEvent) { event in
            guard let event else { return }
            switch event {
            case .success(let provider):
                authAlertMessage = "\(providerTitle(provider)) sign-in succeeded."
            case .failure(_, let message):
                authAlertMessage = message
            case .canceled(let provider):
                authAlertMessage = "\(providerTitle(provider)) sign-in was canceled."
            }
            authManager.clearLastAuthEvent()
        }
        .alert("Account status", isPresented: Binding(
            get: { authAlertMessage != nil },
            set: { if !$0 { authAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authAlertMessage ?? "")
        }
    }

    private var syncPhaseText: String {
        switch assignmentStore.syncPhase {
        case .idle: return "Idle"
        case .syncing: return "Syncing"
        case .conflict: return "Conflict detected"
        case .error(let message): return "Error: \(message)"
        }
    }

    private var notificationsAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }

    private var permissionText: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "Notifications enabled"
        case .denied: return "Notifications denied in system settings"
        case .notDetermined: return "Notifications not requested yet"
        @unknown default: return "Unknown notification state"
        }
    }

    private func refreshNotificationStatus() async {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                Task { @MainActor in
                    authorizationStatus = settings.authorizationStatus
                    continuation.resume()
                }
            }
        }
    }

    private func applySprintNudgeSetting() {
        guard notificationsAuthorized else {
            NotificationManager.shared.cancelDailySprintNudge()
            return
        }

        if dailySprintNudgeEnabled {
            let time = NotificationManager.shared.defaultSprintNudgeTime(
                for: UserDefaults.standard.string(forKey: "preferredStudyTime")
            )
            NotificationManager.shared.scheduleDailySprintNudge(hour: time.hour, minute: time.minute)
        } else {
            NotificationManager.shared.cancelDailySprintNudge()
        }
    }

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

    private func providerTitle(_ provider: AuthManager.AuthProvider) -> String {
        switch provider {
        case .apple: return "Apple"
        case .google: return "Google"
        case .email: return "Email"
        }
    }

    private func deleteAccountFlow() async {
        isDeletingAccount = true
        let result = await authManager.deleteAccount()
        isDeletingAccount = false
        switch result {
        case .success:
            break // authManager.signOut() was called inside deleteAccount; state updates automatically
        case .failure(let error):
            if case .requiresRecentLogin = error {
                showReauthForDeletion = true
            } else {
                deleteErrorMessage = error.localizedDescription
            }
        }
    }
}

struct SyncAccountScreen: View {
    @EnvironmentObject private var assignmentStore: AssignmentStore
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        List {
            Section("Account") {
                switch authManager.authState {
                case .signedIn(let userId):
                    Text("Signed in as \(userId)")
                case .signedOut:
                    Text("Signed out")
                case .resolving:
                    Text("Resolving session…")
                case .error(let message):
                    Text("Auth error: \(message)")
                }
            }

            Section("Sync Status") {
                LabeledContent("Pending writes", value: "\(assignmentStore.pendingWritesCount)")
                if let lastSyncDate = assignmentStore.lastSyncDate {
                    LabeledContent("Last sync", value: lastSyncDate.formatted(date: .abbreviated, time: .shortened))
                } else {
                    LabeledContent("Last sync", value: "Never")
                }
                LabeledContent("Mode", value: syncPhaseText)

                if let conflict = assignmentStore.lastConflictSummary {
                    Text("Conflict: \(conflict)")
                    Button("Clear Conflict Warning") {
                        assignmentStore.clearConflictWarning()
                    }
                }

                Button("Sync Now") {
                    Task { await assignmentStore.performManualSync() }
                }
            }

            Section("Data Ownership") {
                Text("Local: onboarding flags, sprint session, and preferences.")
                Text("Remote: assignment and sprint records for authenticated account.")
            }
        }
        .navigationTitle("Sync / Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var syncPhaseText: String {
        switch assignmentStore.syncPhase {
        case .idle: return "Idle"
        case .syncing: return "Syncing"
        case .conflict: return "Conflict detected"
        case .error(let message): return "Error: \(message)"
        }
    }
}

struct NotificationPreferencesScreen: View {
    @EnvironmentObject private var assignmentStore: AssignmentStore
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // Sprint nudge
    @AppStorage("dailySprintNudgeEnabled") private var dailySprintNudgeEnabled = false
    @AppStorage("sprintNudgeTimeOffset") private var sprintNudgeTimeOffset: Double = 17 * 3600 + 30 * 60

    // Daily check-in reminder
    @AppStorage("dailyReminderEnabled") private var dailyReminderEnabled = false
    @AppStorage("dailyReminderTimeOffset") private var dailyReminderTimeOffset: Double = 16 * 3600

    private var notificationsAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }

    var body: some View {
        List {
            Section {
                Text(permissionStatusText)
                if authorizationStatus == .notDetermined {
                    Button("Enable Notifications") {
                        NotificationManager.shared.requestPermission { granted in
                            if granted { assignmentStore.handleNotificationPermissionGranted() }
                            Task { await refreshStatus() }
                        }
                    }
                } else if authorizationStatus == .denied {
                    Button("Open System Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("Permission")
            } footer: {
                Text("Notifications help you stay on track without checking the app constantly.")
            }

            Section {
                Toggle("Focus sprint nudge", isOn: $dailySprintNudgeEnabled)
                    .disabled(!notificationsAuthorized)
                if dailySprintNudgeEnabled && notificationsAuthorized {
                    DatePicker(
                        "Nudge time",
                        selection: nudgeTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                }
            } header: {
                Text("Daily Sprint Nudge")
            } footer: {
                Text("A short reminder to start one sprint. Fires daily at the time you pick.")
            }

            Section {
                Toggle("Daily check-in reminder", isOn: $dailyReminderEnabled)
                    .disabled(!notificationsAuthorized)
                if dailyReminderEnabled && notificationsAuthorized {
                    DatePicker(
                        "Reminder time",
                        selection: reminderTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                }
            } header: {
                Text("Assignment Check-in")
            } footer: {
                Text("Reminds you to review open assignments due today.")
            }

            Section {
                Button("Reschedule All Notifications") {
                    assignmentStore.refreshTomorrowPreviewIfNeeded()
                    assignmentStore.handleNotificationPermissionGranted()
                    applyAllSettings()
                }
                .disabled(!notificationsAuthorized)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshStatus()
        }
        .onChange(of: dailySprintNudgeEnabled) { _ in applyAllSettings() }
        .onChange(of: sprintNudgeTimeOffset) { _ in applyAllSettings() }
        .onChange(of: dailyReminderEnabled) { _ in applyAllSettings() }
        .onChange(of: dailyReminderTimeOffset) { _ in applyAllSettings() }
    }

    // MARK: - Time bindings

    private var nudgeTimeBinding: Binding<Date> {
        Binding(
            get: { Calendar.autoupdatingCurrent.startOfDay(for: Date()).addingTimeInterval(sprintNudgeTimeOffset) },
            set: { date in
                let c = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
                sprintNudgeTimeOffset = Double((c.hour ?? 17) * 3600 + (c.minute ?? 30) * 60)
            }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: { Calendar.autoupdatingCurrent.startOfDay(for: Date()).addingTimeInterval(dailyReminderTimeOffset) },
            set: { date in
                let c = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
                dailyReminderTimeOffset = Double((c.hour ?? 16) * 3600 + (c.minute ?? 0) * 60)
            }
        )
    }

    // MARK: - Helpers

    private var permissionStatusText: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "Notifications are enabled"
        case .denied: return "Notifications are blocked — open Settings to allow them"
        case .notDetermined: return "Notifications haven't been enabled yet"
        @unknown default: return "Unknown notification state"
        }
    }

    private func refreshStatus() async {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                Task { @MainActor in
                    self.authorizationStatus = settings.authorizationStatus
                    continuation.resume()
                }
            }
        }
    }

    private func applyAllSettings() {
        guard notificationsAuthorized else {
            NotificationManager.shared.cancelDailySprintNudge()
            return
        }

        if dailySprintNudgeEnabled {
            let hour = Int(sprintNudgeTimeOffset) / 3600
            let minute = (Int(sprintNudgeTimeOffset) % 3600) / 60
            NotificationManager.shared.scheduleDailySprintNudge(hour: hour, minute: minute)
        } else {
            NotificationManager.shared.cancelDailySprintNudge()
        }

        if dailyReminderEnabled {
            let hour = Int(dailyReminderTimeOffset) / 3600
            let minute = (Int(dailyReminderTimeOffset) % 3600) / 60
            NotificationManager.shared.scheduleDailyReminder(hour: hour, minute: minute)
        }
    }
}

// MARK: - Re-auth sheet used before account deletion

struct ReauthForDeletionSheet: View {
    @EnvironmentObject private var authManager: AuthManager
    let onReauth: (String, String) -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.standard) {
                Text("Confirm your identity to permanently delete your account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, DS.Spacing.standard)

                VStack(spacing: DS.Spacing.micro) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            DS.cardBackground,
                            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                .stroke(DS.Border.color, lineWidth: DS.Border.width)
                        )

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            DS.cardBackground,
                            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                .stroke(DS.Border.color, lineWidth: DS.Border.width)
                        )
                }
                .padding(DS.Spacing.standard)
                .elevatedCard()

                Button(role: .destructive) {
                    isLoading = true
                    onReauth(email, password)
                } label: {
                    Group {
                        if isLoading {
                            ProgressView()
                                .tint(DS.Colors.primaryButtonFg)
                        } else {
                            Text("Sign In & Delete Account")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(DS.Colors.primaryButtonFg)
                    .background(
                        (email.isEmpty || password.isEmpty)
                            ? DS.Colors.destructive.opacity(0.4)
                            : DS.Colors.destructive,
                        in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    )
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(email.isEmpty || password.isEmpty || isLoading)
                .padding(.horizontal, DS.Spacing.standard)

                Spacer()
            }
            .padding(.horizontal, DS.Spacing.standard)
            .navigationTitle("Verify Identity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
