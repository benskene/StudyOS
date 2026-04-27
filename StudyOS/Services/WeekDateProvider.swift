import Foundation

struct WeekDateProvider {
    private var calendar: Calendar

    init(calendar: Calendar = .autoupdatingCurrent) {
        var configured = calendar
        configured.timeZone = .autoupdatingCurrent
        configured.firstWeekday = 2
        self.calendar = configured
    }

    func weekRange(containing date: Date = Date()) -> Range<Date>? {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysFromMonday = (weekday + 5) % 7
        guard let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: startOfDay),
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return nil
        }
        return weekStart..<weekEnd
    }

    func weekDates(containing date: Date = Date()) -> [Date] {
        guard let range = weekRange(containing: date) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: range.lowerBound) }
    }

    func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func date(byAdding component: Calendar.Component, value: Int, to date: Date) -> Date? {
        calendar.date(byAdding: component, value: value, to: date)
    }

    func dateComponents(_ components: Set<Calendar.Component>, from date: Date) -> DateComponents {
        calendar.dateComponents(components, from: date)
    }

    func date(from components: DateComponents) -> Date? {
        calendar.date(from: components)
    }
}
