import XCTest
@testable import StudyOS

final class SyncArchitectureTests: XCTestCase {
    func testLWWPrefersNewerTimestamp() {
        let localDate = Date(timeIntervalSince1970: 100)
        let remoteDate = Date(timeIntervalSince1970: 200)

        let result = SyncVersionComparator.isRemoteNewer(
            remoteUpdatedAt: remoteDate,
            remoteVersion: 1,
            remoteDeviceId: "b",
            localUpdatedAt: localDate,
            localVersion: 10,
            localDeviceId: "a"
        )

        XCTAssertTrue(result)
    }

    func testLWWPrefersHigherVersionWhenTimestampMatches() {
        let date = Date(timeIntervalSince1970: 100)

        let result = SyncVersionComparator.isRemoteNewer(
            remoteUpdatedAt: date,
            remoteVersion: 5,
            remoteDeviceId: "a",
            localUpdatedAt: date,
            localVersion: 4,
            localDeviceId: "z"
        )

        XCTAssertTrue(result)
    }

    func testLWWUsesDeviceTieBreakerAsLastRule() {
        let date = Date(timeIntervalSince1970: 100)

        let result = SyncVersionComparator.isRemoteNewer(
            remoteUpdatedAt: date,
            remoteVersion: 5,
            remoteDeviceId: "z-device",
            localUpdatedAt: date,
            localVersion: 5,
            localDeviceId: "a-device"
        )

        XCTAssertTrue(result)
    }

    func testAssignmentLocalMutationUpdatesSyncMetadata() {
        let assignment = Assignment(
            id: UUID(),
            title: "Test",
            className: "Class",
            dueDate: Date(),
            estMinutes: 30
        )

        let previousVersion = assignment.syncVersion
        assignment.markLocalMutation(deviceId: "device-123", state: .pendingUpload, at: Date(timeIntervalSince1970: 500))

        XCTAssertEqual(assignment.syncVersion, previousVersion + 1)
        XCTAssertEqual(assignment.updatedByDeviceId, "device-123")
        XCTAssertEqual(assignment.syncState, .pendingUpload)
        XCTAssertEqual(assignment.clientUpdatedAt, Date(timeIntervalSince1970: 500))
    }

    func testTombstonePayloadMarksDeleted() {
        let assignment = Assignment(
            id: UUID(),
            title: "Delete Me",
            className: "Class",
            dueDate: Date(),
            estMinutes: 20,
            syncVersion: 3,
            updatedByDeviceId: "device-a"
        )

        let payload = CloudAssignmentPayload.tombstone(from: assignment, deviceId: "device-b")

        XCTAssertTrue(payload.isDeleted)
        XCTAssertEqual(payload.syncVersion, 4)
        XCTAssertEqual(payload.updatedByDeviceId, "device-b")
    }
}
