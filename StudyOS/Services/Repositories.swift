import Foundation
import SwiftData

@MainActor
final class AssignmentRepository {
    private let modelContext: ModelContext
    private let syncEngine: CloudSyncManager
    private let deviceId: String

    init(modelContext: ModelContext, syncEngine: CloudSyncManager, deviceId: String = SyncDevice.id) {
        self.modelContext = modelContext
        self.syncEngine = syncEngine
        self.deviceId = deviceId
    }

    func insert(_ assignment: Assignment) {
        modelContext.insert(assignment)
        assignment.markLocalMutation(deviceId: deviceId, state: .pendingUpload)
        save()
        syncEngine.uploadAssignments([assignment])
    }

    func mutate(_ assignment: Assignment, apply: () -> Void) {
        apply()
        assignment.markLocalMutation(deviceId: deviceId, state: .pendingUpload)
        save()
        syncEngine.uploadAssignments([assignment])
    }

    func softDeleteAndRemoveLocal(_ assignment: Assignment) {
        syncEngine.deleteAssignment(assignment)
        modelContext.delete(assignment)
        save()
    }

    func markSyncSucceeded(for id: UUID, at date: Date = Date()) {
        guard let assignment = fetchAssignment(id: id) else { return }
        assignment.markSynced(at: date)
        save()
    }

    private func fetchAssignment(id: UUID) -> Assignment? {
        let predicate = #Predicate<Assignment> { $0.id == id }
        let fetch = FetchDescriptor<Assignment>(predicate: predicate)
        return (try? modelContext.fetch(fetch))?.first
    }

    private func save() {
        try? modelContext.save()
    }
}

@MainActor
final class SprintRepository {
    private let modelContext: ModelContext
    private let syncEngine: CloudSyncManager
    private let deviceId: String

    init(modelContext: ModelContext, syncEngine: CloudSyncManager, deviceId: String = SyncDevice.id) {
        self.modelContext = modelContext
        self.syncEngine = syncEngine
        self.deviceId = deviceId
    }

    func insert(_ sprint: FocusSprint) {
        sprint.markLocalMutation(deviceId: deviceId, state: .pendingUpload)
        modelContext.insert(sprint)
        save()
        syncEngine.uploadSprints([sprint])
    }

    func mutate(_ sprint: FocusSprint, apply: () -> Void) {
        apply()
        sprint.markLocalMutation(deviceId: deviceId, state: .pendingUpload)
        save()
        syncEngine.uploadSprints([sprint])
    }

    func softDeleteAndRemoveLocal(_ sprint: FocusSprint) {
        syncEngine.deleteSprint(sprint)
        modelContext.delete(sprint)
        save()
    }

    func markSyncSucceeded(for id: UUID, at date: Date = Date()) {
        guard let sprint = fetchSprint(id: id) else { return }
        sprint.markSynced(at: date)
        save()
    }

    private func fetchSprint(id: UUID) -> FocusSprint? {
        let predicate = #Predicate<FocusSprint> { $0.id == id }
        let fetch = FetchDescriptor<FocusSprint>(predicate: predicate)
        return (try? modelContext.fetch(fetch))?.first
    }

    private func save() {
        try? modelContext.save()
    }
}
