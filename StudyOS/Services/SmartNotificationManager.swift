//
//  SmartNotificationManager.swift
//  Struc
//
//  Created by Ben Skene on 2/2/26.
//

import Foundation
import SwiftData
import UserNotifications

@MainActor
final class SmartNotificationManager {
    private enum Identifier {
        static let eveningCheckIn = "smart-evening-check-in"
        static let tomorrowPreview = "smart-tomorrow-preview"
        static let urgentWarningPrefix = "smart-urgent-warning-"
        static let dueReminderPrefix = "assignment-due-"
        static func urgentWarning(for assignmentId: UUID) -> String {
            urgentWarningPrefix + assignmentId.uuidString
        }
        static func dueReminder(for assignmentId: UUID) -> String {
            dueReminderPrefix + assignmentId.uuidString
        }
    }

    private let modelContext: ModelContext
    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    init(modelContext: ModelContext,
         center: UNUserNotificationCenter = .current(),
         calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.center = center
        self.calendar = calendar
    }

    func scheduleEveningCheckIn() {
        guard hasIncompleteAssignmentsDueTodayOrEarlier() else {
            cancelEveningCheckIn()
            return
        }

        cancelEveningCheckIn()

        let fireDate = nextOccurrence(hour: 16, minute: 0)
        canScheduleNotification(on: fireDate) { [weak self] canSchedule in
            guard let self, canSchedule else { return }

            let content = UNMutableNotificationContent()
            content.title = "School check-in"
            content.body = "You still have work due today. Tap to see what’s next."
            content.sound = .default

            let components = self.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: Identifier.eveningCheckIn,
                                                content: content,
                                                trigger: trigger)
            self.center.add(request)
        }
    }

    func scheduleTomorrowPreview() {
        guard hasIncompleteAssignmentsDueTodayTomorrowOrEarlier() else {
            cancelTomorrowPreview()
            return
        }

        cancelTomorrowPreview()

        guard isAfter(hour: 18, minute: 0) else { return }

        let fireDate = nextOccurrence(hour: 19, minute: 30)

        canScheduleNotification(on: fireDate) { [weak self] canSchedule in
            guard let self, canSchedule else { return }
            let count = self.assignmentsDueTomorrowCount()
            guard count > 0 else { return }

            let content = UNMutableNotificationContent()
            content.title = "Heads up for tomorrow"
            content.body = "You have \(count) assignment(s) due tomorrow. Plan ahead tonight."
            content.sound = .default

            let components = self.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: Identifier.tomorrowPreview,
                                                content: content,
                                                trigger: trigger)
            self.center.add(request)
        }
    }

    func scheduleUrgentDeadlineWarning(for assignment: Assignment) {
        guard !assignment.isCompleted else { return }
        cancelUrgentWarning(for: assignment.id)

        guard withinNotificationWindow() else { return }
        guard isDueWithinNext24Hours(assignment) else { return }

        canScheduleNotification(on: Date()) { [weak self] canSchedule in
            guard let self, canSchedule else { return }

            let content = UNMutableNotificationContent()
            content.title = "Upcoming deadline"
            content.body = "\(assignment.title) is due soon — consider starting now."
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let identifier = Identifier.urgentWarning(for: assignment.id)
            let request = UNNotificationRequest(identifier: identifier,
                                                content: content,
                                                trigger: trigger)
            self.center.add(request)
        }
    }

    func cancelEveningCheckIn() {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.eveningCheckIn])
    }

    func cancelTomorrowPreview() {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.tomorrowPreview])
    }

    func cancelUrgentWarnings() {
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(Identifier.urgentWarningPrefix) }
            guard !identifiers.isEmpty else { return }
            self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    func cancelUrgentWarning(for assignmentId: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.urgentWarning(for: assignmentId)])
    }

    func rescheduleAllNotifications() {
        scheduleEveningCheckIn()
        scheduleTomorrowPreview()
        let fetch = FetchDescriptor<Assignment>(predicate: #Predicate { !$0.isCompleted })
        let assignments = (try? modelContext.fetch(fetch)) ?? []
        for assignment in assignments {
            scheduleDueReminder(for: assignment)
            scheduleUrgentDeadlineWarning(for: assignment)
        }
    }

    func cancelAllManagedNotifications() {
        cancelAllSmartNotifications()
    }

    func scheduleTestNotification(in seconds: Int) {
        let content = UNMutableNotificationContent()
        content.title = "School check-in"
        content.body = "You still have work due today. Tap to see what’s next."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let request = UNNotificationRequest(identifier: "smart-test-notification",
                                            content: content,
                                            trigger: trigger)
        center.add(request)
    }

    private func cancelAllSmartNotifications() {
        cancelEveningCheckIn()
        cancelTomorrowPreview()
        cancelUrgentWarnings()
        center.getPendingNotificationRequests { requests in
            let dueIds = requests.map(\.identifier).filter { $0.hasPrefix(Identifier.dueReminderPrefix) }
            if !dueIds.isEmpty {
                self.center.removePendingNotificationRequests(withIdentifiers: dueIds)
            }
        }
    }

    private func scheduleDueReminder(for assignment: Assignment) {
        cancelDueReminder(for: assignment.id)
        guard !assignment.isCompleted else { return }
        guard assignment.dueDate > Date() else { return }
        let dueReminderDate = assignment.dueDate.addingTimeInterval(-3600)
        guard dueReminderDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Assignment due soon"
        content.body = "\(assignment.title) is due in about an hour."
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: dueReminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: Identifier.dueReminder(for: assignment.id),
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    private func cancelDueReminder(for assignmentId: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.dueReminder(for: assignmentId)])
    }

    private func hasIncompleteAssignmentsDueTodayTomorrowOrEarlier() -> Bool {
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfDayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday) ?? Date()

        let predicate = #Predicate<Assignment> { assignment in
            !assignment.isCompleted && assignment.dueDate < startOfDayAfterTomorrow
        }

        var fetch = FetchDescriptor<Assignment>(predicate: predicate)
        fetch.fetchLimit = 1
        guard let results = try? modelContext.fetch(fetch) else { return false }
        return !results.isEmpty
    }

    private func hasIncompleteAssignmentsDueTodayOrEarlier() -> Bool {
        let startOfTomorrow = calendar.date(byAdding: .day,
                                            value: 1,
                                            to: calendar.startOfDay(for: Date())) ?? Date()
        let predicate = #Predicate<Assignment> { assignment in
            !assignment.isCompleted && assignment.dueDate < startOfTomorrow
        }

        var fetch = FetchDescriptor<Assignment>(predicate: predicate)
        fetch.fetchLimit = 1
        guard let results = try? modelContext.fetch(fetch) else { return false }
        return !results.isEmpty
    }

    private func assignmentsDueTomorrowCount() -> Int {
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? Date()
        let startOfDayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday) ?? Date()

        let predicate = #Predicate<Assignment> { assignment in
            !assignment.isCompleted
            && assignment.dueDate >= startOfTomorrow
            && assignment.dueDate < startOfDayAfterTomorrow
        }

        let fetch = FetchDescriptor<Assignment>(predicate: predicate)
        return (try? modelContext.fetchCount(fetch)) ?? 0
    }

    private func isDueWithinNext24Hours(_ assignment: Assignment) -> Bool {
        let now = Date()
        guard assignment.dueDate >= now else { return false }
        guard let threshold = calendar.date(byAdding: .hour, value: 24, to: now) else { return false }
        return assignment.dueDate <= threshold
    }

    private func withinNotificationWindow() -> Bool {
        let hour = calendar.component(.hour, from: Date())
        let minute = calendar.component(.minute, from: Date())

        let isAfterStart = hour > 7 || (hour == 7 && minute >= 0)
        let isBeforeEnd = hour < 21 || (hour == 21 && minute <= 30)
        return isAfterStart && isBeforeEnd
    }

    private func canScheduleNotification(on date: Date, completion: @escaping (Bool) -> Void) {
        let startOfTargetDay = calendar.startOfDay(for: date)
        let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfTargetDay) ?? date

        let group = DispatchGroup()
        var pendingCount = 0
        var deliveredCount = 0

        group.enter()
        center.getPendingNotificationRequests { requests in
            pendingCount = requests.filter { request in
                guard let triggerDate = self.triggerDate(for: request.trigger) else { return false }
                return triggerDate >= startOfTargetDay && triggerDate < startOfNextDay
            }.count
            group.leave()
        }

        group.enter()
        center.getDeliveredNotifications { notifications in
            deliveredCount = notifications.filter { notification in
                notification.date >= startOfTargetDay && notification.date < startOfNextDay
            }.count
            group.leave()
        }

        group.notify(queue: .main) {
            completion(pendingCount + deliveredCount < 2)
        }
    }

    private func isAfter(hour: Int, minute: Int) -> Bool {
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let reference = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: startOfToday) ?? now
        return now >= reference
    }

    private func nextOccurrence(hour: Int, minute: Int) -> Date {
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: startOfToday) ?? now
        if now <= today {
            return today
        }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
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
}
