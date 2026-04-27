import Foundation
import SwiftData

enum AssignmentEnergyLevel: String, Codable, CaseIterable {
    case low
    case medium
    case high
}

@Model
final class Assignment: Identifiable {
    var id: UUID
    var title: String
    // Renamed from `className` — that name shadows NSObject.className in the ObjC runtime,
    // causing SwiftData-backed models to return "NSManagedObject" instead of the real value.
    @Attribute(originalName: "className") var courseName: String
    var dueDate: Date
    var estMinutes: Int
    var source: String?
    var externalId: String?
    var isCompleted: Bool
    var notes: String
    var totalMinutesWorked: Int
    var lastTinyStep: String
    var lastModified: Date
    var priorityScore: Double
    var isFlexibleDueDate: Bool
    var energyLevel: String
    var syncVersion: Int64
    var clientUpdatedAt: Date
    var updatedByDeviceId: String
    var isDeleted: Bool
    var lastSyncedAt: Date?
    var syncStateRaw: String

    init(
        id: UUID,
        title: String,
        courseName: String,
        dueDate: Date,
        estMinutes: Int,
        source: String? = "manual",
        externalId: String? = nil,
        isCompleted: Bool = false,
        notes: String = "",
        totalMinutesWorked: Int = 0,
        lastTinyStep: String = "",
        lastModified: Date = Date(),
        priorityScore: Double = 0,
        isFlexibleDueDate: Bool = false,
        energyLevel: AssignmentEnergyLevel = .medium,
        syncVersion: Int64 = 0,
        clientUpdatedAt: Date? = nil,
        updatedByDeviceId: String = SyncDevice.id,
        isDeleted: Bool = false,
        lastSyncedAt: Date? = nil,
        syncState: SyncState = .clean
    ) {
        self.id = id
        self.title = title
        self.courseName = courseName
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
        self.energyLevel = energyLevel.rawValue
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
