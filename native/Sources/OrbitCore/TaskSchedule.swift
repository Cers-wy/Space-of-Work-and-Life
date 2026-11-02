import Foundation

/// Resolves explicit dates and presentation-only defaults without mutating tasks.
public struct TaskSchedule: Equatable {
    public let start: Date
    public let end: Date
    public let usesDefaultDeadline: Bool

    public init(task: OrbitTask, today: Date) {
        let calendar = OrbitDate.calendar
        let day = calendar.startOfDay(for: today)
        usesDefaultDeadline = task.due.isEmpty && task.status != .done
        if let due = OrbitDate.parseDay(task.due) {
            end = due
        } else if task.status == .done {
            end = calendar.startOfDay(for: task.completedAt.flatMap(OrbitDate.parseTimestamp) ?? day)
        } else {
            end = calendar.date(byAdding: .day, value: 5, to: task.startDate.flatMap(OrbitDate.parseDay) ?? day)!
        }
        let created = calendar.startOfDay(for: OrbitDate.parseTimestamp(task.createdAt) ?? day)
        start = min(task.startDate.flatMap(OrbitDate.parseDay) ?? (usesDefaultDeadline ? day : created), end)
    }

    public init(start: Date, end: Date, usesDefaultDeadline: Bool = false) {
        self.start = OrbitDate.calendar.startOfDay(for: start)
        self.end = max(self.start, OrbitDate.calendar.startOfDay(for: end))
        self.usesDefaultDeadline = usesDefaultDeadline
    }

    public enum Adjustment: Equatable { case move, start, end }
    /// Operates on the full interval even when the timeline clips either edge.
    public func adjusting(_ adjustment: Adjustment, by days: Int) -> TaskSchedule {
        let calendar = OrbitDate.calendar
        switch adjustment {
        case .move:
            return TaskSchedule(start: calendar.date(byAdding: .day, value: days, to: start)!,
                                end: calendar.date(byAdding: .day, value: days, to: end)!)
        case .start:
            return TaskSchedule(start: min(calendar.date(byAdding: .day, value: days, to: start)!, end), end: end)
        case .end:
            return TaskSchedule(start: start, end: max(start, calendar.date(byAdding: .day, value: days, to: end)!))
        }
    }
    public func applying(to task: OrbitTask, now: Date = Date()) throws -> OrbitTask {
        var result = task
        result.startDate = OrbitDate.day(start); result.due = OrbitDate.day(end)
        result.updatedAt = OrbitDate.timestamp(now)
        return try result.validated()
    }

    public func contains(_ date: Date) -> Bool {
        let day = OrbitDate.calendar.startOfDay(for: date)
        return day >= start && day <= end
    }

    /// Inclusive grid bounds; clips old or distant tasks to the currently visible timeline.
    public func visibleOffsets(in days: [Date]) -> ClosedRange<Int>? {
        guard let first = days.firstIndex(where: contains),
              let last = days.lastIndex(where: contains) else { return nil }
        return first...last
    }
}

public enum ScheduleCalendar {
    public static func weekStart(_ date: Date) -> Date {
        let calendar = OrbitDate.calendar
        let weekday = calendar.component(.weekday, from: date)
        return calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: calendar.startOfDay(for: date))!
    }
    public static func days(starting date: Date, count: Int) -> [Date] {
        let calendar = OrbitDate.calendar
        let start = calendar.startOfDay(for: date)
        return (0..<max(0, count)).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }
    public static func monthDays(_ date: Date) -> [Date] {
        let calendar = OrbitDate.calendar
        let month = calendar.dateInterval(of: .month, for: date)!
        let first = weekStart(month.start)
        let last = calendar.date(byAdding: .day, value: -1, to: month.end)!
        let count = calendar.dateComponents([.day], from: first, to: last).day! + 1
        return days(starting: first, count: ((count + 6) / 7) * 7)
    }
    public static func movingMonth(_ date: Date, by value: Int) -> Date {
        OrbitDate.calendar.date(byAdding: .month, value: value, to: date)!
    }
}
