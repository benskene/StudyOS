import Foundation
import SwiftUI
import UserNotifications
import Combine

enum SprintSessionState: String, Codable {
    case running
    case completed
    case canceled
}

struct SprintSession: Codable, Equatable {
    let id: UUID
    let assignmentId: UUID?
    let startedAt: Date
    let endsAt: Date
    var state: SprintSessionState
    let tinyStep: String

    var remainingSeconds: Int {
        max(0, Int(ceil(endsAt.timeIntervalSinceNow)))
    }

    var isExpired: Bool {
        Date() >= endsAt
    }
}

@MainActor
final class SprintSessionManager: ObservableObject {
    @Published private(set) var activeSession: SprintSession?
    @Published private(set) var lastCompletedSession: SprintSession?
    @Published private(set) var recoveryMessage: String?
    // Single clock source for all sprint UI so screens stay in sync.
    @Published private(set) var currentTime = Date()

    private static let storageKey = "Struc.Sprint.ActiveSession"
    private static let completedStorageKey = "Struc.Sprint.CompletedSession"
    private static let finalizedStorageKey = "Struc.Sprint.FinalizedSessionIds"
    private var ticker: AnyCancellable?
    private var finalizedSessionIds = Set<UUID>()

    init() {
        restoreFinalizedSessionIds()
        restoreFromStorage()
    }

    func startSession(assignmentId: UUID?, durationMinutes: Int, tinyStep: String) -> SprintSession {
        _ = refreshForCurrentTime()

        if let activeSession, activeSession.state == .running, !activeSession.isExpired {
            return activeSession
        }
        if activeSession != nil {
            cancelActiveSession()
        }

        let now = Date()
        let session = SprintSession(
            id: UUID(),
            assignmentId: assignmentId,
            startedAt: now,
            endsAt: now.addingTimeInterval(TimeInterval(durationMinutes * 60)),
            state: .running,
            tinyStep: tinyStep
        )

        currentTime = now
        activeSession = session
        persist(activeSession: session)
        startTicker()
        scheduleSprintEndNotification(for: session)
        return session
    }

    func cancelActiveSession() {
        guard let session = activeSession else { return }
        cancelNotification(for: session)
        activeSession = nil
        clearPersistedSession()
        stopTicker()
    }

    func refreshForCurrentTime(isResumingApp: Bool = false) -> SprintSession? {
        guard var session = activeSession else { return nil }
        guard session.state == .running else { return nil }

        if session.isExpired {
            session.state = .completed
            return finalizeCompletedSession(session, isResumingApp: isResumingApp)
        }

        persist(activeSession: session)
        return nil
    }

    func markSessionCompleted(_ sessionId: UUID) {
        guard let session = activeSession, session.id == sessionId else { return }
        var completed = session
        completed.state = .completed
        _ = finalizeCompletedSession(completed, isResumingApp: false)
    }

    func consumeCompletedSession() -> SprintSession? {
        let completed = lastCompletedSession
        lastCompletedSession = nil
        UserDefaults.standard.removeObject(forKey: Self.completedStorageKey)
        return completed
    }

    func clearRecoveryMessage() {
        recoveryMessage = nil
    }

    func resetPersistence() {
        activeSession = nil
        lastCompletedSession = nil
        recoveryMessage = nil
        finalizedSessionIds.removeAll()
        clearPersistedSession()
        UserDefaults.standard.removeObject(forKey: Self.completedStorageKey)
        UserDefaults.standard.removeObject(forKey: Self.finalizedStorageKey)
        stopTicker()
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            _ = refreshForCurrentTime(isResumingApp: true)
        case .inactive, .background:
            break
        @unknown default:
            break
        }
    }

    private func restoreFromStorage() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let session = try? JSONDecoder().decode(SprintSession.self, from: data),
           session.state == .running {
            activeSession = session
            startTicker()
            let completed = refreshForCurrentTime(isResumingApp: true)
            if completed == nil {
                recoveryMessage = "Sprint resumed from your last session."
            }
        }

        if let data = UserDefaults.standard.data(forKey: Self.completedStorageKey),
           let completed = try? JSONDecoder().decode(SprintSession.self, from: data) {
            lastCompletedSession = completed
        }
    }

    private func restoreFinalizedSessionIds() {
        let values = UserDefaults.standard.array(forKey: Self.finalizedStorageKey) as? [String] ?? []
        finalizedSessionIds = Set(values.compactMap(UUID.init(uuidString:)))
    }

    private func persist(activeSession: SprintSession) {
        if let data = try? JSONEncoder().encode(activeSession) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func clearPersistedSession() {
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    private func persistLastCompletedSession(_ session: SprintSession) {
        lastCompletedSession = session
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.completedStorageKey)
        }
    }

    private func persistFinalizedSessionIds() {
        // Cap at 20 to prevent unbounded UserDefaults growth
        let values = Array(finalizedSessionIds).prefix(20).map(\.uuidString)
        UserDefaults.standard.set(values, forKey: Self.finalizedStorageKey)
    }

    private func finalizeCompletedSession(_ session: SprintSession, isResumingApp: Bool) -> SprintSession? {
        guard !finalizedSessionIds.contains(session.id) else {
            activeSession = nil
            clearPersistedSession()
            cancelNotification(for: session)
            stopTicker()
            return nil
        }

        finalizedSessionIds.insert(session.id)
        persistFinalizedSessionIds()
        persistLastCompletedSession(session)
        activeSession = nil
        clearPersistedSession()
        cancelNotification(for: session)
        stopTicker()

        if isResumingApp {
            recoveryMessage = "Sprint completed while you were away."
        }
        return session
    }

    private func scheduleSprintEndNotification(for session: SprintSession) {
        let content = UNMutableNotificationContent()
        content.title = "Sprint finished"
        let minutes = max(1, Int(round(session.endsAt.timeIntervalSince(session.startedAt) / 60)))
        content.body = "Your \(minutes)-minute sprint is complete."
        content.sound = .default

        let triggerInterval = max(1, session.endsAt.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: triggerInterval, repeats: false)
        let request = UNNotificationRequest(
            identifier: "sprint-end-\(session.id.uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func cancelNotification(for session: SprintSession) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["sprint-end-\(session.id.uuidString)"]
        )
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.currentTime = Date()
                _ = self.refreshForCurrentTime()
            }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }
}
