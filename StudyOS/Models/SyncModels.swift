import Foundation
import SwiftData

enum SyncState: String, Codable, CaseIterable {
    case clean
    case pendingUpload
    case pendingDelete
    case failed
}

enum SyncEntityType: String, Codable {
    case assignment
    case sprint
}

enum SyncEventType: String, Codable {
    case localMutation
    case remoteApplied
    case conflictResolved
    case syncSucceeded
    case syncFailed
}

struct ConflictNotice: Equatable {
    let entityType: SyncEntityType
    let entityId: UUID
    let entityTitle: String
    let localVersion: Int64
    let remoteVersion: Int64
    let resolvedBy: String
}

struct SyncVersionComparator {
    static func isRemoteNewer(
        remoteUpdatedAt: Date,
        remoteVersion: Int64,
        remoteDeviceId: String,
        localUpdatedAt: Date,
        localVersion: Int64,
        localDeviceId: String
    ) -> Bool {
        if remoteUpdatedAt != localUpdatedAt {
            return remoteUpdatedAt > localUpdatedAt
        }
        if remoteVersion != localVersion {
            return remoteVersion > localVersion
        }
        return remoteDeviceId > localDeviceId
    }
}

@Model
final class SyncEvent: Identifiable {
    var id: UUID
    var entityTypeRaw: String
    var entityId: UUID
    var eventTypeRaw: String
    var timestamp: Date
    var deviceId: String
    var summary: String

    init(
        id: UUID = UUID(),
        entityType: SyncEntityType,
        entityId: UUID,
        eventType: SyncEventType,
        timestamp: Date = Date(),
        deviceId: String,
        summary: String
    ) {
        self.id = id
        self.entityTypeRaw = entityType.rawValue
        self.entityId = entityId
        self.eventTypeRaw = eventType.rawValue
        self.timestamp = timestamp
        self.deviceId = deviceId
        self.summary = summary
    }

    var entityType: SyncEntityType {
        get { SyncEntityType(rawValue: entityTypeRaw) ?? .assignment }
        set { entityTypeRaw = newValue.rawValue }
    }

    var eventType: SyncEventType {
        get { SyncEventType(rawValue: eventTypeRaw) ?? .syncFailed }
        set { eventTypeRaw = newValue.rawValue }
    }
}

enum SyncDevice {
    private static let key = "Struc.Sync.DeviceId"

    static var id: String {
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}

extension Assignment {
    func markLocalMutation(deviceId: String, state: SyncState = .pendingUpload, at date: Date = Date()) {
        syncVersion += 1
        clientUpdatedAt = date
        updatedByDeviceId = deviceId
        syncState = state
        lastModified = date
    }

    func markSynced(at date: Date = Date()) {
        lastSyncedAt = date
        syncState = .clean
    }
}

extension FocusSprint {
    func markLocalMutation(deviceId: String, state: SyncState = .pendingUpload, at date: Date = Date()) {
        syncVersion += 1
        clientUpdatedAt = date
        updatedByDeviceId = deviceId
        syncState = state
        lastModified = date
    }

    func markSynced(at date: Date = Date()) {
        lastSyncedAt = date
        syncState = .clean
    }
}
