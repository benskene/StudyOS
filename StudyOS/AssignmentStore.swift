import SwiftUI
import Combine
import SwiftData
import UserNotifications

@MainActor
final class AssignmentStore: ObservableObject {
    enum SyncPhase: Equatable {
        case idle
        case syncing
        case error(message: String)
        case conflict
    }

    private let modelContext: ModelContext
    private let smartNotificationManager: SmartNotificationManager
    private let cloudSyncManager: CloudSyncManager
    private let authCoordinator: AuthCoordinator
    private let assignmentRepository: AssignmentRepository
    private let sprintRepository: SprintRepository
    private let authManager: AuthManager
    private let sprintSessionManager: SprintSessionManager
    private let deviceId = SyncDevice.id
    private let dailyPlanService = DailyPlanService()
    private let calendar = Calendar.autoupdatingCurrent
    private var cancellables = Set<AnyCancellable>()

    @Published var isSyncing = false
    @Published private(set) var syncPhase: SyncPhase = .idle
    @Published private(set) var lastConflictSummary: String?
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var pendingWritesCount: Int = 0

    private static let bannedPlaceholderTitles = Set([
        "AP Stats Homework",
        "AP Stats HW",
        "Business Law Notes",
        "Chemistry Lab"
    ])

    init(modelContext: ModelContext, authManager: AuthManager, sprintSessionManager: SprintSessionManager) {
        self.modelContext = modelContext
        self.smartNotificationManager = SmartNotificationManager(modelContext: modelContext)
        self.cloudSyncManager = CloudSyncManager(deviceId: deviceId)
        self.authCoordinator = AuthCoordinator(authManager: authManager)
        self.assignmentRepository = AssignmentRepository(modelContext: modelContext, syncEngine: cloudSyncManager, deviceId: deviceId)
        self.sprintRepository = SprintRepository(modelContext: modelContext, syncEngine: cloudSyncManager, deviceId: deviceId)
        self.authManager = authManager
        self.sprintSessionManager = sprintSessionManager
        backfillSyncMetadataIfNeeded()
        purgePlaceholderAssignments()
        rebuildDailyPlan()
        upsertConsistencySnapshot(for: Date())

        cloudSyncManager.$isSyncing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] syncing in
                self?.isSyncing = syncing
                if syncing {
                    self?.syncPhase = .syncing
                } else if case .syncing = self?.syncPhase {
                    self?.syncPhase = .idle
                }
            }
            .store(in: &cancellables)

        cloudSyncManager.$lastConflictSummary
            .receive(on: DispatchQueue.main)
            .sink { [weak self] summary in
                self?.lastConflictSummary = summary
                if summary != nil {
                    self?.syncPhase = .conflict
                }
            }
            .store(in: &cancellables)

        cloudSyncManager.$lastSyncDate
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastSyncDate)

        Publishers.CombineLatest(cloudSyncManager.$pendingUploadCount, cloudSyncManager.$pendingDeletionCount)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] uploads, deletions in
                self?.pendingWritesCount = uploads + deletions
            }
            .store(in: &cancellables)

        cloudSyncManager.$lastSyncErrorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self, let message else { return }
                self.syncPhase = .error(message: message)
            }
            .store(in: &cancellables)

        sprintSessionManager.$lastCompletedSession
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                guard let self, session != nil else { return }
                self.processCompletedSprintIfNeeded()
            }
            .store(in: &cancellables)

        cloudSyncManager.onRemoteChange = { [weak self] updates, deletions in
            Task { @MainActor in
                self?.applyRemoteChanges(updates: updates, deletions: deletions)
            }
        }
        cloudSyncManager.onRemoteSprintChange = { [weak self] updates, deletions in
            Task { @MainActor in
                self?.applyRemoteSprintChanges(updates: updates, deletions: deletions)
            }
        }
        cloudSyncManager.onMutationAcknowledged = { [weak self] entityType, entityId, syncedAt in
            Task { @MainActor in
                self?.handleMutationAcknowledged(entityType: entityType, entityId: entityId, syncedAt: syncedAt)
            }
        }

        authCoordinator.$authState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authState in
                guard let self else { return }
                if case .signedIn = authState {
                    Task { await self.performInitialSync() }
                    self.cloudSyncManager.observeRemoteChanges()
                    self.cloudSyncManager.resumePendingWrites()
                    self.smartNotificationManager.rescheduleAllNotifications()
                } else {
                    self.cloudSyncManager.stopObserving()
                    self.syncPhase = .idle
                }
            }
            .store(in: &cancellables)
    }

    func addAssignment(_ assignment: Assignment) -> Bool {
        guard canPersistAssignmentTitle(assignment.title) else { return false }
        assignmentRepository.insert(assignment)
        appendSyncEvent(
            entityType: .assignment,
            entityId: assignment.id,
            eventType: .localMutation,
            summary: "Local assignment created and queued for sync."
        )
        smartNotificationManager.rescheduleAllNotifications()
        rebuildDailyPlan()
        return true
    }

    func importAssignments(_ normalizedAssignments: [ImportedAssignment]) -> Int {
        guard !normalizedAssignments.isEmpty else { return 0 }

        let fetchImported = FetchDescriptor<Assignment>(
            predicate: #Predicate { $0.externalId != nil }
        )

        let existing = (try? modelContext.fetch(fetchImported)) ?? []
        var knownExternalIds = Set(existing.compactMap(\.externalId))
        var importedAssignments: [Assignment] = []

        for normalized in normalizedAssignments {
            if knownExternalIds.contains(normalized.externalId) {
                continue
            }

            guard let dueDate = normalized.dueDateValue else {
                continue
            }
            guard canPersistAssignmentTitle(normalized.title) else {
                continue
            }

            let assignment = Assignment(
                id: UUID(),
                title: normalized.title,
                courseName: normalized.className,
                dueDate: dueDate,
                estMinutes: 30,
                source: normalized.source,
                externalId: normalized.externalId,
                notes: normalized.notes
            )

            assignmentRepository.insert(assignment)
            importedAssignments.append(assignment)
            knownExternalIds.insert(normalized.externalId)
        }

        guard !importedAssignments.isEmpty else { return 0 }

        smartNotificationManager.rescheduleAllNotifications()
        rebuildDailyPlan()
        return importedAssignments.count
    }

    func backgroundSyncGoogleClassroom() async {
        // Debounce: skip if synced within last 15 minutes
        let lastSyncKey = "studyos.googleClassroom.lastSyncAt"
        let minInterval: TimeInterval = 15 * 60
        if let lastSync = UserDefaults.standard.object(forKey: lastSyncKey) as? Date,
           Date().timeIntervalSince(lastSync) < minInterval {
            return
        }

        guard let authToken = await authManager.fetchBackendAuthToken() else { return }

        let fetchDescriptor = FetchDescriptor<Assignment>(
            predicate: #Predicate { $0.source == "google_classroom" && !$0.isDeleted }
        )
        let existingIds = ((try? modelContext.fetch(fetchDescriptor)) ?? [])
            .compactMap(\.externalId)

        let provider = GoogleClassroomProvider()
        guard let newAssignments = await provider.silentFetchIfConnected(
            existingExternalIds: existingIds,
            authToken: authToken
        ) else { return }

        UserDefaults.standard.set(Date(), forKey: lastSyncKey)

        guard !newAssignments.isEmpty else { return }
        _ = importAssignments(newAssignments)
    }

    func backgroundSyncCanvas() async {
        let lastSyncKey = "studyos.canvas.lastSyncAt"
        let minInterval: TimeInterval = 15 * 60
        if let lastSync = UserDefaults.standard.object(forKey: lastSyncKey) as? Date,
           Date().timeIntervalSince(lastSync) < minInterval {
            return
        }

        guard let authToken = await authManager.fetchBackendAuthToken() else { return }

        let fetchDescriptor = FetchDescriptor<Assignment>(
            predicate: #Predicate { $0.source == "canvas" && !$0.isDeleted }
        )
        let existingIds = ((try? modelContext.fetch(fetchDescriptor)) ?? [])
            .compactMap(\.externalId)

        let service = CanvasImportService()
        guard let newAssignments = await service.silentFetchIfConnected(
            existingExternalIds: existingIds,
            authToken: authToken
        ) else { return }

        UserDefaults.standard.set(Date(), forKey: lastSyncKey)

        guard !newAssignments.isEmpty else { return }
        _ = importAssignments(newAssignments)
    }

    func deleteAssignment(_ assignment: Assignment) {
        assignmentRepository.softDeleteAndRemoveLocal(assignment)
        appendSyncEvent(
            entityType: .assignment,
            entityId: assignment.id,
            eventType: .localMutation,
            summary: "Assignment deleted locally and tombstone queued."
        )
        smartNotificationManager.rescheduleAllNotifications()
        rebuildDailyPlan()
    }

    func toggleCompleted(_ assignment: Assignment) {
        updateAssignment(assignment) {
            assignment.isCompleted.toggle()
        }
        upsertConsistencySnapshot(for: Date())
        smartNotificationManager.rescheduleAllNotifications()
    }

    func updateDueDate(_ assignment: Assignment, to newDate: Date) {
        updateAssignment(assignment) {
            assignment.dueDate = newDate
        }
        smartNotificationManager.rescheduleAllNotifications()
    }

    func updateNotes(_ assignment: Assignment, notes: String) {
        // Notes don't affect scheduling, so skip the plan rebuild
        updateAssignment(assignment, rebuildPlan: false) {
            assignment.notes = notes
        }
    }

    func addMinutes(_ assignment: Assignment, minutes: Int) {
        updateAssignment(assignment) {
            assignment.totalMinutesWorked += minutes
        }
    }

    func updateTinyStep(_ assignment: Assignment, tinyStep: String) {
        // Tiny step doesn't affect scheduling, so skip the plan rebuild
        updateAssignment(assignment, rebuildPlan: false) {
            assignment.lastTinyStep = tinyStep
        }
    }

    // Fix #4: use a predicate instead of fetching all assignments
    func assignment(with id: UUID) -> Assignment? {
        let predicate = #Predicate<Assignment> { $0.id == id && !$0.isDeleted }
        let fetch = FetchDescriptor<Assignment>(predicate: predicate)
        return (try? modelContext.fetch(fetch))?.first
    }

    func sprintCount(for assignment: Assignment) -> Int {
        let assignmentId = assignment.id
        let predicate = #Predicate<FocusSprint> { sprint in
            sprint.assignmentId == assignmentId
        }
        let fetch = FetchDescriptor<FocusSprint>(predicate: predicate)
        return (try? modelContext.fetchCount(fetch)) ?? 0
    }

    func updateSprintReflection(sprintId: UUID, note: String?, focusRating: Int?) {
        guard let sprint = sprint(with: sprintId) else { return }
        sprintRepository.mutate(sprint) {
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            sprint.reflectionNote = trimmed?.isEmpty == true ? nil : trimmed
            if let focusRating {
                sprint.focusRating = min(5, max(1, focusRating))
            } else {
                sprint.focusRating = nil
            }
        }
    }

    func processCompletedSprintIfNeeded() {
        guard let completed = sprintSessionManager.lastCompletedSession,
              completed.state == .completed else { return }

        if sprint(with: completed.id) != nil {
            _ = sprintSessionManager.consumeCompletedSession()
            return
        }

        let seconds = max(1, Int(round(completed.endsAt.timeIntervalSince(completed.startedAt))))
        let sprint = FocusSprint(
            id: completed.id,
            startTime: completed.startedAt,
            endTime: completed.endsAt,
            durationSeconds: seconds,
            assignmentId: completed.assignmentId
        )
        sprintRepository.insert(sprint)

        if let assignmentId = completed.assignmentId,
           let assignment = assignment(with: assignmentId) {
            let minutes = max(1, Int(round(Double(seconds) / 60.0)))
            assignmentRepository.mutate(assignment) {
                assignment.totalMinutesWorked += minutes
            }
        }

        upsertConsistencySnapshot(for: completed.endsAt)
        rebuildDailyPlan(for: completed.endsAt)
        NotificationManager.shared.scheduleRecoveryNudgeIfNeeded(
            assignments: allAssignments(),
            sprints: allSprints()
        )
        _ = sprintSessionManager.consumeCompletedSession()
    }

    func performManualSync() async {
        await performInitialSync()
        cloudSyncManager.resumePendingWrites()
    }

    func clearConflictWarning() {
        cloudSyncManager.clearConflictSummary()
        if case .conflict = syncPhase {
            syncPhase = .idle
        }
    }

    func resetAllData() async {
        let localAssignments = (try? modelContext.fetch(FetchDescriptor<Assignment>())) ?? []
        for assignment in localAssignments {
            modelContext.delete(assignment)
        }
        let localSprints = (try? modelContext.fetch(FetchDescriptor<FocusSprint>())) ?? []
        for sprint in localSprints {
            modelContext.delete(sprint)
        }
        let localPlanItems = (try? modelContext.fetch(FetchDescriptor<DailyPlanItem>())) ?? []
        for item in localPlanItems {
            modelContext.delete(item)
        }
        let localSnapshots = (try? modelContext.fetch(FetchDescriptor<ConsistencySnapshot>())) ?? []
        for snapshot in localSnapshots {
            modelContext.delete(snapshot)
        }
        let localSyncEvents = (try? modelContext.fetch(FetchDescriptor<SyncEvent>())) ?? []
        for event in localSyncEvents {
            modelContext.delete(event)
        }
        saveChanges()
        await cloudSyncManager.deleteAllRemoteAssignments()
        smartNotificationManager.cancelAllManagedNotifications()
        sprintSessionManager.resetPersistence()
        syncPhase = .idle
    }

    private func handleMutationAcknowledged(entityType: SyncEntityType, entityId: UUID, syncedAt: Date) {
        switch entityType {
        case .assignment:
            assignmentRepository.markSyncSucceeded(for: entityId, at: syncedAt)
        case .sprint:
            sprintRepository.markSyncSucceeded(for: entityId, at: syncedAt)
        }
        appendSyncEvent(
            entityType: entityType,
            entityId: entityId,
            eventType: .syncSucceeded,
            summary: "Mutation acknowledged by cloud."
        )
        // appendSyncEvent doesn't save; save here to persist the log entry
        saveChanges()
    }

    private func backfillSyncMetadataIfNeeded() {
        let assignments = allAssignments()
        let sprints = allSprints()
        var changed = false

        for assignment in assignments {
            if assignment.updatedByDeviceId.isEmpty {
                assignment.updatedByDeviceId = deviceId
                changed = true
            }
            if assignment.syncVersion < 0 {
                assignment.syncVersion = 0
                changed = true
            }
            if assignment.clientUpdatedAt.timeIntervalSince1970 <= 0 {
                assignment.clientUpdatedAt = assignment.lastModified
                changed = true
            }
        }

        for sprint in sprints {
            if sprint.updatedByDeviceId.isEmpty {
                sprint.updatedByDeviceId = deviceId
                changed = true
            }
            if sprint.syncVersion < 0 {
                sprint.syncVersion = 0
                changed = true
            }
            if sprint.clientUpdatedAt.timeIntervalSince1970 <= 0 {
                sprint.clientUpdatedAt = sprint.lastModified
                changed = true
            }
        }

        if changed {
            saveChanges()
        }
    }

    // Fix #2: removed saveChanges() — callers already save via the repository
    // or explicitly after this call (e.g. handleMutationAcknowledged)
    private func appendSyncEvent(
        entityType: SyncEntityType,
        entityId: UUID,
        eventType: SyncEventType,
        summary: String
    ) {
        modelContext.insert(
            SyncEvent(
                entityType: entityType,
                entityId: entityId,
                eventType: eventType,
                deviceId: deviceId,
                summary: summary
            )
        )
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save assignments: \(error)")
        }
    }

    private func isRemoteAssignmentNewer(remote: Assignment, local: Assignment) -> Bool {
        SyncVersionComparator.isRemoteNewer(
            remoteUpdatedAt: remote.clientUpdatedAt,
            remoteVersion: remote.syncVersion,
            remoteDeviceId: remote.updatedByDeviceId,
            localUpdatedAt: local.clientUpdatedAt,
            localVersion: local.syncVersion,
            localDeviceId: local.updatedByDeviceId
        )
    }

    // Arguments are intentionally swapped: we ask "is local newer than remote?"
    // by passing local as the "remote" side of the comparator.
    private func isLocalAssignmentNewer(local: Assignment, remote: Assignment) -> Bool {
        SyncVersionComparator.isRemoteNewer(
            remoteUpdatedAt: local.clientUpdatedAt,
            remoteVersion: local.syncVersion,
            remoteDeviceId: local.updatedByDeviceId,
            localUpdatedAt: remote.clientUpdatedAt,
            localVersion: remote.syncVersion,
            localDeviceId: remote.updatedByDeviceId
        )
    }

    private func updateAssignment(_ assignment: Assignment, rebuildPlan: Bool = true, apply: () -> Void) {
        assignmentRepository.mutate(assignment, apply: apply)
        appendSyncEvent(
            entityType: .assignment,
            entityId: assignment.id,
            eventType: .localMutation,
            summary: "Assignment updated locally and queued for sync."
        )
        if rebuildPlan {
            rebuildDailyPlan()
        }
    }

    private func performInitialSync() async {
        syncPhase = .syncing
        let remoteAssignments = await cloudSyncManager.downloadAssignments()
        let remoteSprints = await cloudSyncManager.downloadSprints()
        let localAssignments = allAssignments()
        let localSprints = allSprints()

        let localById: [UUID: Assignment] = Dictionary(uniqueKeysWithValues: localAssignments.map { ($0.id, $0) })
        let remoteById: [UUID: Assignment] = Dictionary(uniqueKeysWithValues: remoteAssignments.filter { !$0.isDeleted }.map { ($0.id, $0) })
        var assignmentsToUpload: [Assignment] = []

        for remote in remoteAssignments {
            if !canPersistAssignmentTitle(remote.title) {
                continue
            }
            if remote.isDeleted {
                if let local = localById[remote.id] {
                    modelContext.delete(local)
                }
                continue
            }
            if let local = localById[remote.id] {
                if isRemoteAssignmentNewer(remote: remote, local: local) {
                    applyRemote(remote, to: local)
                } else if isLocalAssignmentNewer(local: local, remote: remote) {
                    assignmentsToUpload.append(local)
                    let conflict = "Conflict on \(local.title) (\(local.id.uuidString.prefix(6))) - local won"
                    cloudSyncManager.recordConflict(conflict)
                    appendSyncEvent(
                        entityType: .assignment,
                        entityId: local.id,
                        eventType: .conflictResolved,
                        summary: conflict
                    )
                }
            } else {
                modelContext.insert(remote)
            }
        }

        for local in localAssignments where remoteById[local.id] == nil {
            assignmentsToUpload.append(local)
        }

        let localSprintsById: [UUID: FocusSprint] = Dictionary(uniqueKeysWithValues: localSprints.map { ($0.id, $0) })
        let remoteSprintsById: [UUID: FocusSprint] = Dictionary(uniqueKeysWithValues: remoteSprints.filter { !$0.isDeleted }.map { ($0.id, $0) })
        var sprintsToUpload: [FocusSprint] = []

        for remote in remoteSprints {
            if remote.isDeleted {
                if let local = localSprintsById[remote.id] {
                    modelContext.delete(local)
                }
                continue
            }
            if let local = localSprintsById[remote.id] {
                if isRemoteSprintNewer(remote: remote, local: local) {
                    applyRemote(remote, to: local)
                } else if isLocalSprintNewer(local: local, remote: remote) {
                    sprintsToUpload.append(local)
                }
            } else {
                modelContext.insert(remote)
            }
        }

        for local in localSprints where remoteSprintsById[local.id] == nil {
            sprintsToUpload.append(local)
        }

        saveChanges()
        purgePlaceholderAssignments()
        cloudSyncManager.uploadAssignments(assignmentsToUpload)
        cloudSyncManager.uploadSprints(sprintsToUpload)
        syncPhase = lastConflictSummary == nil ? .idle : .conflict
    }

    private func applyRemote(_ remote: Assignment, to local: Assignment) {
        local.title = remote.title
        local.courseName = remote.courseName
        local.dueDate = remote.dueDate
        local.estMinutes = remote.estMinutes
        local.source = remote.source
        local.externalId = remote.externalId
        local.isCompleted = remote.isCompleted
        local.notes = remote.notes
        local.totalMinutesWorked = remote.totalMinutesWorked
        local.lastTinyStep = remote.lastTinyStep
        local.lastModified = remote.lastModified
        local.priorityScore = remote.priorityScore
        local.isFlexibleDueDate = remote.isFlexibleDueDate
        local.energyLevel = remote.energyLevel
        local.syncVersion = remote.syncVersion
        local.clientUpdatedAt = remote.clientUpdatedAt
        local.updatedByDeviceId = remote.updatedByDeviceId
        local.isDeleted = remote.isDeleted
        local.markSynced()
    }

    private func applyRemote(_ remote: FocusSprint, to local: FocusSprint) {
        local.startTime = remote.startTime
        local.endTime = remote.endTime
        local.durationSeconds = remote.durationSeconds
        local.assignmentId = remote.assignmentId
        local.reflectionNote = remote.reflectionNote
        local.focusRating = remote.focusRating
        local.createdAt = remote.createdAt
        local.lastModified = remote.lastModified
        local.syncVersion = remote.syncVersion
        local.clientUpdatedAt = remote.clientUpdatedAt
        local.updatedByDeviceId = remote.updatedByDeviceId
        local.isDeleted = remote.isDeleted
        local.markSynced()
    }

    private func applyRemoteChanges(updates: [CloudAssignmentPayload], deletions: [UUID]) {
        guard !updates.isEmpty || !deletions.isEmpty else { return }

        let localAssignments = allAssignments()
        let localById: [UUID: Assignment] = Dictionary(uniqueKeysWithValues: localAssignments.map { ($0.id, $0) })

        for payload in updates {
            if !canPersistAssignmentTitle(payload.title) {
                continue
            }
            if payload.isDeleted {
                if let local = localById[payload.id] {
                    modelContext.delete(local)
                    appendSyncEvent(
                        entityType: .assignment,
                        entityId: payload.id,
                        eventType: .remoteApplied,
                        summary: "Remote tombstone removed local assignment."
                    )
                }
                continue
            }
            if let local = localById[payload.id] {
                // Ignore local echo when same device+version are already applied.
                if payload.updatedByDeviceId == deviceId && payload.syncVersion <= local.syncVersion {
                    continue
                }
                if SyncVersionComparator.isRemoteNewer(
                    remoteUpdatedAt: payload.clientUpdatedAt,
                    remoteVersion: payload.syncVersion,
                    remoteDeviceId: payload.updatedByDeviceId,
                    localUpdatedAt: local.clientUpdatedAt,
                    localVersion: local.syncVersion,
                    localDeviceId: local.updatedByDeviceId
                ) {
                    payload.apply(to: local)
                    appendSyncEvent(
                        entityType: .assignment,
                        entityId: payload.id,
                        eventType: .remoteApplied,
                        summary: "Remote update applied."
                    )
                } else if SyncVersionComparator.isRemoteNewer(
                    remoteUpdatedAt: local.clientUpdatedAt,
                    remoteVersion: local.syncVersion,
                    remoteDeviceId: local.updatedByDeviceId,
                    localUpdatedAt: payload.clientUpdatedAt,
                    localVersion: payload.syncVersion,
                    localDeviceId: payload.updatedByDeviceId
                ) {
                    let summary = "Conflict on \(local.title) (\(local.id.uuidString.prefix(6))) - local won"
                    cloudSyncManager.recordConflict(summary)
                    appendSyncEvent(
                        entityType: .assignment,
                        entityId: payload.id,
                        eventType: .conflictResolved,
                        summary: summary
                    )
                }
            } else {
                if !payload.isDeleted {
                    modelContext.insert(payload.toAssignment())
                    appendSyncEvent(
                        entityType: .assignment,
                        entityId: payload.id,
                        eventType: .remoteApplied,
                        summary: "Remote assignment inserted."
                    )
                }
            }
        }

        for id in deletions {
            if let local = localById[id] {
                modelContext.delete(local)
            }
        }

        saveChanges()
        purgePlaceholderAssignments()
        rebuildDailyPlan()
        upsertConsistencySnapshot(for: Date())
        smartNotificationManager.rescheduleAllNotifications()
    }

    private func applyRemoteSprintChanges(updates: [CloudSprintPayload], deletions: [UUID]) {
        guard !updates.isEmpty || !deletions.isEmpty else { return }

        let localSprints = allSprints()
        let localById: [UUID: FocusSprint] = Dictionary(uniqueKeysWithValues: localSprints.map { ($0.id, $0) })

        for payload in updates {
            if payload.isDeleted {
                if let local = localById[payload.id] {
                    modelContext.delete(local)
                    appendSyncEvent(
                        entityType: .sprint,
                        entityId: payload.id,
                        eventType: .remoteApplied,
                        summary: "Remote tombstone removed local sprint."
                    )
                }
                continue
            }
            if let local = localById[payload.id] {
                if payload.updatedByDeviceId == deviceId && payload.syncVersion <= local.syncVersion {
                    continue
                }
                if SyncVersionComparator.isRemoteNewer(
                    remoteUpdatedAt: payload.clientUpdatedAt,
                    remoteVersion: payload.syncVersion,
                    remoteDeviceId: payload.updatedByDeviceId,
                    localUpdatedAt: local.clientUpdatedAt,
                    localVersion: local.syncVersion,
                    localDeviceId: local.updatedByDeviceId
                ) {
                    payload.apply(to: local)
                }
            } else {
                if !payload.isDeleted {
                    modelContext.insert(payload.toSprint())
                    appendSyncEvent(
                        entityType: .sprint,
                        entityId: payload.id,
                        eventType: .remoteApplied,
                        summary: "Remote sprint inserted."
                    )
                }
            }
        }

        for id in deletions {
            if let local = localById[id] {
                modelContext.delete(local)
            }
        }

        saveChanges()
        upsertConsistencySnapshot(for: Date())
    }

    func handleNotificationPermissionGranted() {
        smartNotificationManager.rescheduleAllNotifications()
        if UserDefaults.standard.object(forKey: "dailySprintNudgeEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "dailySprintNudgeEnabled")
        }
        if UserDefaults.standard.bool(forKey: "dailySprintNudgeEnabled") {
            let preference = UserDefaults.standard.string(forKey: "preferredStudyTime")
            let time = NotificationManager.shared.defaultSprintNudgeTime(for: preference)
            NotificationManager.shared.scheduleDailySprintNudge(hour: time.hour, minute: time.minute)
        }
        NotificationManager.shared.scheduleDueSoonDigest(assignments: allAssignments(), sprints: allSprints())
        NotificationManager.shared.scheduleRecoveryNudgeIfNeeded(assignments: allAssignments(), sprints: allSprints())
    }

    func refreshTomorrowPreviewIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            Task { @MainActor in
                self.smartNotificationManager.rescheduleAllNotifications()
                NotificationManager.shared.scheduleDueSoonDigest(assignments: self.allAssignments(), sprints: self.allSprints())
                NotificationManager.shared.scheduleRecoveryNudgeIfNeeded(assignments: self.allAssignments(), sprints: self.allSprints())
            }
        }
    }

    func rebuildDailyPlan(for date: Date = Date()) {
        let dayStart = calendar.startOfDay(for: date)
        let assignments = allAssignments()
        let repeatingMust = repeatedMustCandidate(for: dayStart)
        let selections = dailyPlanService.buildPlan(
            assignments: assignments,
            today: date,
            repeatingMustAssignmentId: repeatingMust
        )

        // Always update priority scores since they may have changed even if plan slots haven't
        for selection in selections {
            if let assignment = assignments.first(where: { $0.id == selection.assignmentId }) {
                assignment.priorityScore = selection.score
            }
        }

        let existingFetch = FetchDescriptor<DailyPlanItem>(
            predicate: #Predicate { item in item.date == dayStart },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let existingItems = (try? modelContext.fetch(existingFetch)) ?? []

        // Skip the delete-reinsert if the plan hasn't changed
        let planUnchanged = existingItems.count == selections.count &&
            zip(existingItems, selections).allSatisfy { item, selection in
                item.assignmentId == selection.assignmentId && item.slotTypeRaw == selection.slot.rawValue
            }
        if planUnchanged {
            saveChanges()
            return
        }

        for item in existingItems {
            modelContext.delete(item)
        }
        for selection in selections {
            let matchedAssignment = assignments.first(where: { $0.id == selection.assignmentId })
            modelContext.insert(DailyPlanItem(
                date: dayStart,
                assignmentId: selection.assignmentId,
                slotType: selection.slot,
                completed: matchedAssignment?.isCompleted ?? false
            ))
        }

        saveChanges()
    }

    private func repeatedMustCandidate(for dayStart: Date) -> UUID? {
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: dayStart),
              let twoDaysBack = calendar.date(byAdding: .day, value: -2, to: dayStart) else {
            return nil
        }

        let previous = mustAssignmentId(for: previousDay)
        let twoBack = mustAssignmentId(for: twoDaysBack)
        guard let previous, previous == twoBack else { return nil }
        return previous
    }

    private func mustAssignmentId(for day: Date) -> UUID? {
        let mustRaw = DailyPlanSlotType.must.rawValue
        let fetch = FetchDescriptor<DailyPlanItem>(
            predicate: #Predicate { item in
                item.date == day && item.slotTypeRaw == mustRaw
            }
        )
        return (try? modelContext.fetch(fetch))?.first?.assignmentId
    }

    private func upsertConsistencySnapshot(for date: Date) {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }

        let sprints = allSprints().filter { $0.startTime >= dayStart && $0.startTime < dayEnd }
        let didCompleteSprint = !sprints.isEmpty
        let minutesFocused = sprints.reduce(0) { $0 + Int(round(Double($1.durationSeconds) / 60.0)) }
        let tasksCompleted = allAssignments().filter {
            $0.isCompleted && $0.lastModified >= dayStart && $0.lastModified < dayEnd
        }.count

        let fetch = FetchDescriptor<ConsistencySnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.date == dayStart
            }
        )

        if let existing = (try? modelContext.fetch(fetch))?.first {
            existing.didCompleteSprint = didCompleteSprint
            existing.minutesFocused = minutesFocused
            existing.tasksCompleted = tasksCompleted
        } else {
            modelContext.insert(
                ConsistencySnapshot(
                    date: dayStart,
                    didCompleteSprint: didCompleteSprint,
                    minutesFocused: minutesFocused,
                    tasksCompleted: tasksCompleted
                )
            )
        }

        saveChanges()
    }

    // Fix #3: push isDeleted filter into SwiftData predicate instead of filtering in Swift
    private func allAssignments() -> [Assignment] {
        let fetch = FetchDescriptor<Assignment>(predicate: #Predicate { !$0.isDeleted })
        return (try? modelContext.fetch(fetch)) ?? []
    }

    private func allSprints() -> [FocusSprint] {
        let fetch = FetchDescriptor<FocusSprint>(predicate: #Predicate { !$0.isDeleted })
        return (try? modelContext.fetch(fetch)) ?? []
    }

    private func canPersistAssignmentTitle(_ title: String) -> Bool {
        !Self.bannedPlaceholderTitles.contains(title.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func sprint(with id: UUID) -> FocusSprint? {
        let predicate = #Predicate<FocusSprint> { sprint in
            sprint.id == id
        }
        let fetch = FetchDescriptor<FocusSprint>(predicate: predicate)
        return (try? modelContext.fetch(fetch))?.first(where: { !$0.isDeleted })
    }

    private func purgePlaceholderAssignments() {
        let fetch = FetchDescriptor<Assignment>()
        guard let allAssignments = try? modelContext.fetch(fetch) else { return }
        let banned = allAssignments.filter { !canPersistAssignmentTitle($0.title) }
        guard !banned.isEmpty else { return }
        for assignment in banned {
            modelContext.delete(assignment)
        }
        saveChanges()
    }

    private func isRemoteSprintNewer(remote: FocusSprint, local: FocusSprint) -> Bool {
        SyncVersionComparator.isRemoteNewer(
            remoteUpdatedAt: remote.clientUpdatedAt,
            remoteVersion: remote.syncVersion,
            remoteDeviceId: remote.updatedByDeviceId,
            localUpdatedAt: local.clientUpdatedAt,
            localVersion: local.syncVersion,
            localDeviceId: local.updatedByDeviceId
        )
    }

    private func isLocalSprintNewer(local: FocusSprint, remote: FocusSprint) -> Bool {
        SyncVersionComparator.isRemoteNewer(
            remoteUpdatedAt: local.clientUpdatedAt,
            remoteVersion: local.syncVersion,
            remoteDeviceId: local.updatedByDeviceId,
            localUpdatedAt: remote.clientUpdatedAt,
            localVersion: remote.syncVersion,
            localDeviceId: remote.updatedByDeviceId
        )
    }
}
