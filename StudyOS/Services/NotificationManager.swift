//
//  NotificationManager.swift
//  Struc
//
//  Created by Ben Skene on 2/2/26.
//

import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private let dailySprintNudgeIdentifier = "daily-sprint-nudge"
    private let scheduledSprintPrefix = "scheduled-sprint-reminder-"
    private let dueSoonDigestIdentifier = "due-soon-digest"
    private let recoveryNudgeIdentifier = "recovery-nudge"

    private init() {}

    func requestPermission(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    func scheduleDailyReminder(hour: Int = 16, minute: Int = 0) {
        let content = UNMutableNotificationContent()
        content.title = "School check-in"
        content.body = "You still have assignments due today. Open Struc to see what’s next."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "daily-assignment-reminder",
            content: content,
            trigger: trigger
        )

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        center.add(request)
    }

    func scheduleDailySprintNudge(hour: Int = 17, minute: Int = 30) {
        scheduleDailySprintNudge(hour: hour, minute: minute, contentBody: "If you have 5 minutes, start one sprint now.")
    }

    func defaultSprintNudgeTime(for preferenceRaw: String?) -> (hour: Int, minute: Int) {
        switch preferenceRaw {
        case StudyTimePreference.afternoon.rawValue:
            return (16, 30)
        case StudyTimePreference.lateNight.rawValue:
            return (20, 30)
        default:
            return (17, 30)
        }
    }

    func scheduleDueSoonDigest(assignments: [Assignment], sprints: [FocusSprint], now: Date = Date()) {
        let openDueSoon = assignments.filter { assignment in
            guard !assignment.isCompleted else { return false }
            let interval = assignment.dueDate.timeIntervalSince(now)
            return interval > 0 && interval <= (48 * 3600)
        }

        guard !openDueSoon.isEmpty else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dueSoonDigestIdentifier])
            return
        }

        guard canScheduleNotification(on: now), !hasSprintInLastThreeHours(sprints: sprints, now: now) else { return }

        var components = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: now)
        components.hour = 18
        components.minute = 30
        components.second = 0
        guard let triggerDate = Calendar.autoupdatingCurrent.date(from: components), triggerDate > now else { return }
        guard canScheduleNotification(on: triggerDate) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Due soon"
        content.body = "You have \(openDueSoon.count) assignment(s) due in the next 48 hours."
        content.sound = .default

        let triggerComponents = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let request = UNNotificationRequest(identifier: dueSoonDigestIdentifier, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dueSoonDigestIdentifier])
        center.add(request)
    }

    func scheduleRecoveryNudgeIfNeeded(assignments: [Assignment], sprints: [FocusSprint], now: Date = Date()) {
        let unfinishedExists = assignments.contains { !$0.isCompleted }
        guard unfinishedExists else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [recoveryNudgeIdentifier])
            return
        }
        guard !hasSprintInLastThreeHours(sprints: sprints, now: now) else { return }

        let calendar = Calendar.autoupdatingCurrent
        let hour = calendar.component(.hour, from: now)
        guard hour < 20 else { return }

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 20
        components.minute = 0
        components.second = 0
        guard let triggerDate = calendar.date(from: components), triggerDate > now else { return }
        guard canScheduleNotification(on: triggerDate) else { return }

        let content = UNMutableNotificationContent()
        content.title = "2-minute start"
        content.body = "Start tiny: open Struc and do the first 2 minutes."
        content.sound = .default

        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let request = UNNotificationRequest(identifier: recoveryNudgeIdentifier, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [recoveryNudgeIdentifier])
        center.add(request)
    }

    private func scheduleDailySprintNudge(hour: Int, minute: Int, contentBody: String) {
        let content = UNMutableNotificationContent()
        content.title = "Focus sprint"
        content.body = contentBody
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: dailySprintNudgeIdentifier,
            content: content,
            trigger: trigger
        )

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailySprintNudgeIdentifier])
        center.add(request)
    }

    func cancelDailySprintNudge() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailySprintNudgeIdentifier])
    }

    func scheduleUnstartedSprintReminder(for assignmentId: UUID, in minutes: Int = 20) {
        let identifier = scheduledSprintPrefix + assignmentId.uuidString
        let content = UNMutableNotificationContent()
        content.title = "Planned sprint reminder"
        content.body = "You planned to start a sprint. Start it when you are ready."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(60, TimeInterval(minutes * 60)),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.add(request)
    }

    func cancelUnstartedSprintReminder(for assignmentId: UUID) {
        let identifier = scheduledSprintPrefix + assignmentId.uuidString
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelAllNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func canScheduleNotification(on date: Date) -> Bool {
        let startOfTargetDay = Calendar.autoupdatingCurrent.startOfDay(for: date)
        let endOfTargetDay = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: startOfTargetDay) ?? date

        let semaphore = DispatchSemaphore(value: 0)
        var pendingCount = 0
        var deliveredCount = 0

        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            pendingCount = requests.filter { request in
                guard let triggerDate = self.triggerDate(for: request.trigger) else { return false }
                return triggerDate >= startOfTargetDay && triggerDate < endOfTargetDay
            }.count
            semaphore.signal()
        }
        semaphore.wait()

        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            deliveredCount = notifications.filter {
                $0.date >= startOfTargetDay && $0.date < endOfTargetDay
            }.count
            semaphore.signal()
        }
        semaphore.wait()

        return pendingCount + deliveredCount < 2
    }

    private func hasSprintInLastThreeHours(sprints: [FocusSprint], now: Date) -> Bool {
        let threshold = now.addingTimeInterval(-3 * 3600)
        return sprints.contains { $0.endTime >= threshold && $0.endTime <= now }
    }

    private func triggerDate(for trigger: UNNotificationTrigger?) -> Date? {
        switch trigger {
        case let calendarTrigger as UNCalendarNotificationTrigger:
            return calendarTrigger.nextTriggerDate()
        case let timeIntervalTrigger as UNTimeIntervalNotificationTrigger:
            return Date().addingTimeInterval(timeIntervalTrigger.timeInterval)
        default:
            return nil
        }
    }

    func scheduleTestNotification(in seconds: Int) {
        let content = UNMutableNotificationContent()
        content.title = "School check-in"
        content.body = "You still have assignments due today. Open Struc to see what’s next."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let request = UNNotificationRequest(
            identifier: "test-assignment-reminder",
            content: content,
            trigger: trigger
        )

        let center = UNUserNotificationCenter.current()
        center.add(request)
    }
}
