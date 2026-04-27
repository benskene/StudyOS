import Foundation
import Combine
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

enum SyncMutationOperation: String, Codable {
    case upsert
    case tombstone
}

struct SyncMutationEnvelope: Identifiable {
    let id: UUID
    let entityType: SyncEntityType
    let entityId: UUID
    var operation: SyncMutationOperation
    var assignmentPayload: CloudAssignmentPayload?
    var sprintPayload: CloudSprintPayload?
    let localVersion: Int64
    let queuedAt: Date
    var retryCount: Int
}

struct CloudAssignmentPayload: Identifiable {
    let id: UUID
    let title: String
    let className: String
    let dueDate: Date
    let estMinutes: Int
    let source: String?
    let externalId: String?
    let isCompleted: Bool
    let notes: String
    let totalMinutesWorked: Int
    let lastTinyStep: String
    let lastModified: Date
    let priorityScore: Double
    let isFlexibleDueDate: Bool
    let energyLevel: String
    let syncVersion: Int64
    let clientUpdatedAt: Date
    let updatedByDeviceId: String
    let isDeleted: Bool

    #if canImport(FirebaseFirestore)
    init?(document: DocumentSnapshot) {
        let data = document.data() ?? [:]

        guard let title = data["title"] as? String,
              let dueDateTimestamp = data["dueDate"] as? Timestamp,
              let estMinutes = data["estMinutes"] as? Int,
              let isCompleted = data["isCompleted"] as? Bool,
              let lastModifiedTimestamp = data["lastModified"] as? Timestamp else {
            return nil
        }
        let className = data["className"] as? String ?? ""

        let notes = data["notes"] as? String ?? ""
        let source = data["source"] as? String
        let externalId = data["externalId"] as? String
        let totalMinutesWorked = data["totalMinutesWorked"] as? Int ?? 0
        let lastTinyStep = data["lastTinyStep"] as? String ?? ""
        let priorityScore = data["priorityScore"] as? Double ?? 0
        let isFlexibleDueDate = data["isFlexibleDueDate"] as? Bool ?? false
        let energyLevel = data["energyLevel"] as? String ?? AssignmentEnergyLevel.medium.rawValue
        let syncVersion: Int64
        if let raw = data["syncVersion"] as? Int64 {
            syncVersion = raw
        } else if let raw = data["syncVersion"] as? Int {
            syncVersion = Int64(raw)
        } else {
            syncVersion = 0
        }
        let clientUpdatedAt = (data["clientUpdatedAt"] as? Timestamp)?.dateValue() ?? lastModifiedTimestamp.dateValue()
        let updatedByDeviceId = data["updatedByDeviceId"] as? String ?? ""
        let isDeleted = data["isDeleted"] as? Bool ?? false
        let id = UUID(uuidString: document.documentID) ?? UUID()

        self.id = id
        self.title = title
        self.className = className
        self.dueDate = dueDateTimestamp.dateValue()
        self.estMinutes = estMinutes
        self.source = source
        self.externalId = externalId
        self.isCompleted = isCompleted
        self.notes = notes
        self.totalMinutesWorked = totalMinutesWorked
        self.lastTinyStep = lastTinyStep
        self.lastModified = lastModifiedTimestamp.dateValue()
        self.priorityScore = priorityScore
        self.isFlexibleDueDate = isFlexibleDueDate
        self.energyLevel = energyLevel
        self.syncVersion = syncVersion
        self.clientUpdatedAt = clientUpdatedAt
        self.updatedByDeviceId = updatedByDeviceId
        self.isDeleted = isDeleted
    }
    #endif

    init(assignment: Assignment) {
        self.id = assignment.id
        self.title = assignment.title
        self.className = assignment.courseName
        self.dueDate = assignment.dueDate
        self.estMinutes = assignment.estMinutes
        self.source = assignment.source
        self.externalId = assignment.externalId
        self.isCompleted = assignment.isCompleted
        self.notes = assignment.notes
        self.totalMinutesWorked = assignment.totalMinutesWorked
        self.lastTinyStep = assignment.lastTinyStep
        self.lastModified = assignment.lastModified
        self.priorityScore = assignment.priorityScore
        self.isFlexibleDueDate = assignment.isFlexibleDueDate
        self.energyLevel = assignment.energyLevel
        self.syncVersion = assignment.syncVersion
        self.clientUpdatedAt = assignment.clientUpdatedAt
        self.updatedByDeviceId = assignment.updatedByDeviceId
        self.isDeleted = assignment.isDeleted
    }

    static func tombstone(from assignment: Assignment, deviceId: String) -> CloudAssignmentPayload {
        CloudAssignmentPayload(
            id: assignment.id,
            title: assignment.title,
            className: assignment.courseName,
            dueDate: assignment.dueDate,
            estMinutes: assignment.estMinutes,
            source: assignment.source,
            externalId: assignment.externalId,
            isCompleted: assignment.isCompleted,
            notes: assignment.notes,
            totalMinutesWorked: assignment.totalMinutesWorked,
            lastTinyStep: assignment.lastTinyStep,
            lastModified: Date(),
            priorityScore: assignment.priorityScore,
            isFlexibleDueDate: assignment.isFlexibleDueDate,
            energyLevel: assignment.energyLevel,
            syncVersion: assignment.syncVersion + 1,
            clientUpdatedAt: Date(),
            updatedByDeviceId: deviceId,
            isDeleted: true
        )
    }

    init(
        id: UUID,
        title: String,
        className: String,
        dueDate: Date,
        estMinutes: Int,
        source: String?,
        externalId: String?,
        isCompleted: Bool,
        notes: String,
        totalMinutesWorked: Int,
        lastTinyStep: String,
        lastModified: Date,
        priorityScore: Double,
        isFlexibleDueDate: Bool,
        energyLevel: String,
        syncVersion: Int64,
        clientUpdatedAt: Date,
        updatedByDeviceId: String,
        isDeleted: Bool
    ) {
        self.id = id
        self.title = title
        self.className = className
        self.dueDate = dueDate
        self.estMinutes = estMinutes
        self.source = source
        self.externalId = externalId
        self.isCompleted = isCompleted
        self.notes = notes
        self.totalMinutesWorked = totalMinutesWorked
        self.lastTinyStep = lastTinyStep
        self.lastModified = lastModified
        self.priorityScore = priorityScore
        self.isFlexibleDueDate = isFlexibleDueDate
        self.energyLevel = energyLevel
        self.syncVersion = syncVersion
        self.clientUpdatedAt = clientUpdatedAt
        self.updatedByDeviceId = updatedByDeviceId
        self.isDeleted = isDeleted
    }

    func toAssignment() -> Assignment {
        Assignment(
            id: id,
            title: title,
            courseName: className,
            dueDate: dueDate,
            estMinutes: estMinutes,
            source: source,
            externalId: externalId,
            isCompleted: isCompleted,
            notes: notes,
            totalMinutesWorked: totalMinutesWorked,
            lastTinyStep: lastTinyStep,
            lastModified: lastModified,
            priorityScore: priorityScore,
            isFlexibleDueDate: isFlexibleDueDate,
            energyLevel: AssignmentEnergyLevel(rawValue: energyLevel) ?? .medium,
            syncVersion: syncVersion,
            clientUpdatedAt: clientUpdatedAt,
            updatedByDeviceId: updatedByDeviceId,
            isDeleted: isDeleted,
            lastSyncedAt: nil,
            syncState: .clean
        )
    }

    func apply(to assignment: Assignment) {
        assignment.title = title
        assignment.courseName = className
        assignment.dueDate = dueDate
        assignment.estMinutes = estMinutes
        assignment.source = source
        assignment.externalId = externalId
        assignment.isCompleted = isCompleted
        assignment.notes = notes
        assignment.totalMinutesWorked = totalMinutesWorked
        assignment.lastTinyStep = lastTinyStep
        assignment.lastModified = lastModified
        assignment.priorityScore = priorityScore
        assignment.isFlexibleDueDate = isFlexibleDueDate
        assignment.energyLevel = energyLevel
        assignment.syncVersion = syncVersion
        assignment.clientUpdatedAt = clientUpdatedAt
        assignment.updatedByDeviceId = updatedByDeviceId
        assignment.isDeleted = isDeleted
        assignment.markSynced()
    }

    func asDictionary() -> [String: Any] {
        #if canImport(FirebaseFirestore)
        var data: [String: Any] = [
            "id": id.uuidString,
            "title": title,
            "className": className,
            "dueDate": Timestamp(date: dueDate),
            "estMinutes": estMinutes,
            "isCompleted": isCompleted,
            "notes": notes,
            "totalMinutesWorked": totalMinutesWorked,
            "lastTinyStep": lastTinyStep,
            "lastModified": Timestamp(date: lastModified),
            "priorityScore": priorityScore,
            "isFlexibleDueDate": isFlexibleDueDate,
            "energyLevel": energyLevel,
            "syncVersion": Int(syncVersion),
            "clientUpdatedAt": Timestamp(date: clientUpdatedAt),
            "updatedByDeviceId": updatedByDeviceId,
            "isDeleted": isDeleted
        ]
        if let source {
            data["source"] = source
        }
        if let externalId {
            data["externalId"] = externalId
        }
        return data
        #else
        return [:]
        #endif
    }
}

struct CloudSprintPayload: Identifiable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let durationSeconds: Int
    let assignmentId: UUID?
    let reflectionNote: String?
    let focusRating: Int?
    let createdAt: Date
    let lastModified: Date
    let syncVersion: Int64
    let clientUpdatedAt: Date
    let updatedByDeviceId: String
    let isDeleted: Bool

    #if canImport(FirebaseFirestore)
    init?(document: DocumentSnapshot) {
        let data = document.data() ?? [:]
        guard let startTimeTimestamp = data["startTime"] as? Timestamp,
              let endTimeTimestamp = data["endTime"] as? Timestamp,
              let durationSeconds = data["durationSeconds"] as? Int,
              let createdAtTimestamp = data["createdAt"] as? Timestamp,
              let lastModifiedTimestamp = data["lastModified"] as? Timestamp else {
            return nil
        }

        self.id = UUID(uuidString: document.documentID) ?? UUID()
        self.startTime = startTimeTimestamp.dateValue()
        self.endTime = endTimeTimestamp.dateValue()
        self.durationSeconds = durationSeconds
        if let assignmentIdString = data["assignmentId"] as? String {
            self.assignmentId = UUID(uuidString: assignmentIdString)
        } else {
            self.assignmentId = nil
        }
        self.reflectionNote = data["reflectionNote"] as? String
        self.focusRating = data["focusRating"] as? Int
        self.createdAt = createdAtTimestamp.dateValue()
        self.lastModified = lastModifiedTimestamp.dateValue()
        if let raw = data["syncVersion"] as? Int64 {
            self.syncVersion = raw
        } else if let raw = data["syncVersion"] as? Int {
            self.syncVersion = Int64(raw)
        } else {
            self.syncVersion = 0
        }
        self.clientUpdatedAt = (data["clientUpdatedAt"] as? Timestamp)?.dateValue() ?? lastModifiedTimestamp.dateValue()
        self.updatedByDeviceId = data["updatedByDeviceId"] as? String ?? ""
        self.isDeleted = data["isDeleted"] as? Bool ?? false
    }
    #endif

    init(sprint: FocusSprint) {
        self.id = sprint.id
        self.startTime = sprint.startTime
        self.endTime = sprint.endTime
        self.durationSeconds = sprint.durationSeconds
        self.assignmentId = sprint.assignmentId
        self.reflectionNote = sprint.reflectionNote
        self.focusRating = sprint.focusRating
        self.createdAt = sprint.createdAt
        self.lastModified = sprint.lastModified
        self.syncVersion = sprint.syncVersion
        self.clientUpdatedAt = sprint.clientUpdatedAt
        self.updatedByDeviceId = sprint.updatedByDeviceId
        self.isDeleted = sprint.isDeleted
    }

    static func tombstone(from sprint: FocusSprint, deviceId: String) -> CloudSprintPayload {
        CloudSprintPayload(
            id: sprint.id,
            startTime: sprint.startTime,
            endTime: sprint.endTime,
            durationSeconds: sprint.durationSeconds,
            assignmentId: sprint.assignmentId,
            reflectionNote: sprint.reflectionNote,
            focusRating: sprint.focusRating,
            createdAt: sprint.createdAt,
            lastModified: Date(),
            syncVersion: sprint.syncVersion + 1,
            clientUpdatedAt: Date(),
            updatedByDeviceId: deviceId,
            isDeleted: true
        )
    }

    init(
        id: UUID,
        startTime: Date,
        endTime: Date,
        durationSeconds: Int,
        assignmentId: UUID?,
        reflectionNote: String?,
        focusRating: Int?,
        createdAt: Date,
        lastModified: Date,
        syncVersion: Int64,
        clientUpdatedAt: Date,
        updatedByDeviceId: String,
        isDeleted: Bool
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.assignmentId = assignmentId
        self.reflectionNote = reflectionNote
        self.focusRating = focusRating
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.syncVersion = syncVersion
        self.clientUpdatedAt = clientUpdatedAt
        self.updatedByDeviceId = updatedByDeviceId
        self.isDeleted = isDeleted
    }

    func toSprint() -> FocusSprint {
        FocusSprint(
            id: id,
            startTime: startTime,
            endTime: endTime,
            durationSeconds: durationSeconds,
            assignmentId: assignmentId,
            reflectionNote: reflectionNote,
            focusRating: focusRating,
            createdAt: createdAt,
            lastModified: lastModified,
            syncVersion: syncVersion,
            clientUpdatedAt: clientUpdatedAt,
            updatedByDeviceId: updatedByDeviceId,
            isDeleted: isDeleted,
            lastSyncedAt: nil,
            syncState: .clean
        )
    }

    func apply(to sprint: FocusSprint) {
        sprint.startTime = startTime
        sprint.endTime = endTime
        sprint.durationSeconds = durationSeconds
        sprint.assignmentId = assignmentId
        sprint.reflectionNote = reflectionNote
        sprint.focusRating = focusRating
        sprint.createdAt = createdAt
        sprint.lastModified = lastModified
        sprint.syncVersion = syncVersion
        sprint.clientUpdatedAt = clientUpdatedAt
        sprint.updatedByDeviceId = updatedByDeviceId
        sprint.isDeleted = isDeleted
        sprint.markSynced()
    }

    func asDictionary() -> [String: Any] {
        #if canImport(FirebaseFirestore)
        var data: [String: Any] = [
            "id": id.uuidString,
            "startTime": Timestamp(date: startTime),
            "endTime": Timestamp(date: endTime),
            "durationSeconds": durationSeconds,
            "createdAt": Timestamp(date: createdAt),
            "lastModified": Timestamp(date: lastModified),
            "syncVersion": Int(syncVersion),
            "clientUpdatedAt": Timestamp(date: clientUpdatedAt),
            "updatedByDeviceId": updatedByDeviceId,
            "isDeleted": isDeleted
        ]
        if let assignmentId {
            data["assignmentId"] = assignmentId.uuidString
        }
        if let reflectionNote {
            data["reflectionNote"] = reflectionNote
        }
        if let focusRating {
            data["focusRating"] = focusRating
        }
        return data
        #else
        return [:]
        #endif
    }
}

@MainActor
final class CloudSyncManager: ObservableObject {
    @Published var isSyncing = false
    @Published private(set) var pendingUploadCount = 0
    @Published private(set) var pendingDeletionCount = 0
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastSyncErrorMessage: String?
    @Published private(set) var lastConflictSummary: String?

    var onRemoteChange: (([CloudAssignmentPayload], [UUID]) -> Void)?
    var onRemoteSprintChange: (([CloudSprintPayload], [UUID]) -> Void)?
    var onMutationAcknowledged: ((SyncEntityType, UUID, Date) -> Void)?

    #if canImport(FirebaseFirestore)
    private let db = Firestore.firestore()
    private var assignmentListener: ListenerRegistration?
    private var sprintListener: ListenerRegistration?
    #endif

    private var pendingMutations: [SyncMutationEnvelope] = []
    private var isFlushing = false
    private let maxRetryCount = 8
    private let deviceId: String

    init(deviceId: String = SyncDevice.id) {
        self.deviceId = deviceId
    }

    func uploadAssignments(_ assignments: [Assignment]) {
        let mutations = assignments.map {
            SyncMutationEnvelope(
                id: UUID(),
                entityType: .assignment,
                entityId: $0.id,
                operation: .upsert,
                assignmentPayload: CloudAssignmentPayload(assignment: $0),
                sprintPayload: nil,
                localVersion: $0.syncVersion,
                queuedAt: Date(),
                retryCount: 0
            )
        }
        enqueue(mutations)
        flushPendingWrites()
    }

    func uploadSprints(_ sprints: [FocusSprint]) {
        let mutations = sprints.map {
            SyncMutationEnvelope(
                id: UUID(),
                entityType: .sprint,
                entityId: $0.id,
                operation: .upsert,
                assignmentPayload: nil,
                sprintPayload: CloudSprintPayload(sprint: $0),
                localVersion: $0.syncVersion,
                queuedAt: Date(),
                retryCount: 0
            )
        }
        enqueue(mutations)
        flushPendingWrites()
    }

    func deleteAssignment(_ assignment: Assignment) {
        let payload = CloudAssignmentPayload.tombstone(from: assignment, deviceId: deviceId)
        let mutation = SyncMutationEnvelope(
            id: UUID(),
            entityType: .assignment,
            entityId: assignment.id,
            operation: .tombstone,
            assignmentPayload: payload,
            sprintPayload: nil,
            localVersion: payload.syncVersion,
            queuedAt: Date(),
            retryCount: 0
        )
        enqueue([mutation])
        flushPendingWrites()
    }

    func deleteSprint(_ sprint: FocusSprint) {
        let payload = CloudSprintPayload.tombstone(from: sprint, deviceId: deviceId)
        let mutation = SyncMutationEnvelope(
            id: UUID(),
            entityType: .sprint,
            entityId: sprint.id,
            operation: .tombstone,
            assignmentPayload: nil,
            sprintPayload: payload,
            localVersion: payload.syncVersion,
            queuedAt: Date(),
            retryCount: 0
        )
        enqueue([mutation])
        flushPendingWrites()
    }

    func downloadAssignments() async -> [Assignment] {
        #if canImport(FirebaseFirestore)
        guard let collection = assignmentsCollection else { return [] }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let snapshot = try await collection.getDocuments()
            lastSyncDate = Date()
            lastSyncErrorMessage = nil
            return snapshot.documents.compactMap { CloudAssignmentPayload(document: $0) }.map { $0.toAssignment() }
        } catch {
            lastSyncErrorMessage = "Download sync failed: \(error.localizedDescription)"
            return []
        }
        #else
        return []
        #endif
    }

    func downloadSprints() async -> [FocusSprint] {
        #if canImport(FirebaseFirestore)
        guard let collection = sprintsCollection else { return [] }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let snapshot = try await collection.getDocuments()
            lastSyncDate = Date()
            lastSyncErrorMessage = nil
            return snapshot.documents.compactMap { CloudSprintPayload(document: $0) }.map { $0.toSprint() }
        } catch {
            lastSyncErrorMessage = "Sprint download sync failed: \(error.localizedDescription)"
            return []
        }
        #else
        return []
        #endif
    }

    func observeRemoteChanges() {
        #if canImport(FirebaseFirestore)
        observeRemoteAssignmentChanges()
        observeRemoteSprintChanges()
        #endif
    }

    func resumePendingWrites() {
        flushPendingWrites()
    }

    func recordConflict(_ summary: String) {
        lastConflictSummary = summary
    }

    func clearConflictSummary() {
        lastConflictSummary = nil
    }

    func resetSyncErrors() {
        lastSyncErrorMessage = nil
    }

    func deleteAllRemoteAssignments() async {
        #if canImport(FirebaseFirestore)
        do {
            if let assignmentCollection = assignmentsCollection {
                let assignmentSnapshot = try await assignmentCollection.getDocuments()
                for document in assignmentSnapshot.documents {
                    try await assignmentCollection.document(document.documentID).delete()
                }
            }

            if let sprintCollection = sprintsCollection {
                let sprintSnapshot = try await sprintCollection.getDocuments()
                for document in sprintSnapshot.documents {
                    try await sprintCollection.document(document.documentID).delete()
                }
            }

            lastSyncDate = Date()
            lastSyncErrorMessage = nil
        } catch {
            lastSyncErrorMessage = "Failed to reset remote data: \(error.localizedDescription)"
        }
        #endif
    }

    func stopObserving() {
        #if canImport(FirebaseFirestore)
        assignmentListener?.remove()
        assignmentListener = nil
        sprintListener?.remove()
        sprintListener = nil
        #endif
    }

    #if canImport(FirebaseFirestore)
    private var assignmentsCollection: CollectionReference? {
        #if canImport(FirebaseAuth)
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        return db.collection("users").document(userId).collection("assignments")
        #else
        return nil
        #endif
    }

    private var sprintsCollection: CollectionReference? {
        #if canImport(FirebaseAuth)
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        return db.collection("users").document(userId).collection("sprints")
        #else
        return nil
        #endif
    }

    private func observeRemoteAssignmentChanges() {
        guard assignmentListener == nil, let collection = assignmentsCollection else { return }
        assignmentListener = collection.addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let snapshot else { return }

            let changes = snapshot.documentChanges
            var updates: [CloudAssignmentPayload] = []
            var deletions: [UUID] = []

            for change in changes {
                switch change.type {
                case .added, .modified:
                    if let payload = CloudAssignmentPayload(document: change.document) {
                        updates.append(payload)
                    }
                case .removed:
                    if let id = UUID(uuidString: change.document.documentID) {
                        deletions.append(id)
                    }
                }
            }

            if !updates.isEmpty || !deletions.isEmpty {
                self.onRemoteChange?(updates, deletions)
            }
        }
    }

    private func observeRemoteSprintChanges() {
        guard sprintListener == nil, let collection = sprintsCollection else { return }
        sprintListener = collection.addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let snapshot else { return }

            let changes = snapshot.documentChanges
            var updates: [CloudSprintPayload] = []
            var deletions: [UUID] = []

            for change in changes {
                switch change.type {
                case .added, .modified:
                    if let payload = CloudSprintPayload(document: change.document) {
                        updates.append(payload)
                    }
                case .removed:
                    if let id = UUID(uuidString: change.document.documentID) {
                        deletions.append(id)
                    }
                }
            }

            if !updates.isEmpty || !deletions.isEmpty {
                self.onRemoteSprintChange?(updates, deletions)
            }
        }
    }
    #endif

    private func enqueue(_ mutations: [SyncMutationEnvelope]) {
        for mutation in mutations {
            if let existingIndex = pendingMutations.firstIndex(where: {
                $0.entityType == mutation.entityType && $0.entityId == mutation.entityId
            }) {
                pendingMutations[existingIndex] = mutation
            } else {
                pendingMutations.append(mutation)
            }
        }
        refreshPendingCounts()
    }

    private func flushPendingWrites() {
        #if canImport(FirebaseFirestore)
        guard !isFlushing else { return }
        guard assignmentsCollection != nil || sprintsCollection != nil else { return }
        guard !pendingMutations.isEmpty else { return }

        isFlushing = true
        isSyncing = true

        Task { @MainActor in
            await self.runFlushLoop()
        }
        #endif
    }

    private func runFlushLoop() async {
        while !pendingMutations.isEmpty {
            do {
                try await processHeadMutation()
            } catch {
                guard !pendingMutations.isEmpty else { break }
                var mutation = pendingMutations[0]
                mutation.retryCount += 1
                pendingMutations[0] = mutation

                let category = categorize(error)
                lastSyncErrorMessage = "\(category): \(error.localizedDescription)"

                if category == "auth" || category == "permission" || mutation.retryCount >= maxRetryCount {
                    pauseFlushWithFailureState()
                    refreshPendingCounts()
                    return
                }

                let delaySeconds = backoffSeconds(for: mutation.retryCount)
                refreshPendingCounts()
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
        }

        isFlushing = false
        isSyncing = false
        refreshPendingCounts()
    }

    private func processHeadMutation() async throws {
        guard let mutation = pendingMutations.first else { return }

        switch mutation.entityType {
        case .assignment:
            guard let payload = mutation.assignmentPayload else {
                pendingMutations.removeFirst()
                return
            }
            #if canImport(FirebaseFirestore)
            guard let assignmentCollection = assignmentsCollection else {
                throw NSError(domain: "Sync", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication required"])
            }
            try await assignmentCollection.document(payload.id.uuidString).setData(payload.asDictionary(), merge: true)
            #endif
        case .sprint:
            guard let payload = mutation.sprintPayload else {
                pendingMutations.removeFirst()
                return
            }
            #if canImport(FirebaseFirestore)
            guard let sprintCollection = sprintsCollection else {
                throw NSError(domain: "Sync", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication required"])
            }
            try await sprintCollection.document(payload.id.uuidString).setData(payload.asDictionary(), merge: true)
            #endif
        }

        pendingMutations.removeFirst()
        lastSyncDate = Date()
        lastSyncErrorMessage = nil
        onMutationAcknowledged?(mutation.entityType, mutation.entityId, Date())
        refreshPendingCounts()
    }

    private func pauseFlushWithFailureState() {
        isFlushing = false
        isSyncing = false
    }

    private func refreshPendingCounts() {
        pendingUploadCount = pendingMutations.filter { $0.operation == .upsert }.count
        pendingDeletionCount = pendingMutations.filter { $0.operation == .tombstone }.count
    }

    private func backoffSeconds(for retryCount: Int) -> Double {
        let exponential = min(60.0, pow(2.0, Double(retryCount)))
        let jitter = Double.random(in: 0...0.75)
        return exponential + jitter
    }

    private func categorize(_ error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain {
            return "network"
        }

        #if canImport(FirebaseFirestore)
        if nsError.domain == "FIRFirestoreErrorDomain",
           let code = FirestoreErrorCode.Code(rawValue: nsError.code) {
            switch code {
            case .permissionDenied:
                return "permission"
            case .unauthenticated:
                return "auth"
            case .unavailable, .deadlineExceeded:
                return "network"
            default:
                return "unknown"
            }
        }
        #endif

        if nsError.code == 401 {
            return "auth"
        }

        return "unknown"
    }
}
