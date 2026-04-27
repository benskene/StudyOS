import Foundation
import SwiftData

@Model
final class FocusSprint: Identifiable {
    var id: UUID
    var startTime: Date
    var endTime: Date
    var durationSeconds: Int
    var assignmentId: UUID?
    var reflectionNote: String?
    var focusRating: Int?
    var createdAt: Date
    var lastModified: Date
    var syncVersion: Int64
    var clientUpdatedAt: Date
    var updatedByDeviceId: String
    var isDeleted: Bool
    var lastSyncedAt: Date?
    var syncStateRaw: String

    init(
        id: UUID,
        startTime: Date,
        endTime: Date,
        durationSeconds: Int,
        assignmentId: UUID? = nil,
        reflectionNote: String? = nil,
        focusRating: Int? = nil,
        createdAt: Date = Date(),
        lastModified: Date = Date(),
        syncVersion: Int64 = 0,
        clientUpdatedAt: Date? = nil,
        updatedByDeviceId: String = SyncDevice.id,
        isDeleted: Bool = false,
        lastSyncedAt: Date? = nil,
        syncState: SyncState = .clean
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = max(1, durationSeconds)
        self.assignmentId = assignmentId
        self.reflectionNote = reflectionNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let focusRating {
            self.focusRating = min(5, max(1, focusRating))
        } else {
            self.focusRating = nil
        }
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.syncVersion = max(0, syncVersion)
        self.clientUpdatedAt = clientUpdatedAt ?? lastModified
        self.updatedByDeviceId = updatedByDeviceId
        self.isDeleted = isDeleted
        self.lastSyncedAt = lastSyncedAt
        self.syncStateRaw = syncState.rawValue
    }

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .clean }
        set { syncStateRaw = newValue.rawValue }
    }
}
