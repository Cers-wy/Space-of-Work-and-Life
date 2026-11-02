import XCTest
@testable import OrbitCore

final class TaskScheduleTests: XCTestCase {
    private let today = OrbitDate.parseDay("2026-10-29")!
    private func task(due: String = "", status: TaskStatus = .todo, created: String = "2026-10-20") -> OrbitTask {
        OrbitTask(title: "排期验证", status: status, due: due, now: OrbitDate.parseDay(created)!)
    }
    func testMissingDeadlineIsFiveCalendarDaysFromTodayWithoutChangingTask() throws {
        let original = task()
        let schedule = TaskSchedule(task: original, today: today)
        XCTAssertTrue(schedule.usesDefaultDeadline)
        XCTAssertEqual(OrbitDate.day(schedule.start), "2026-10-29")
        XCTAssertEqual(OrbitDate.day(schedule.end), "2026-11-03")
        XCTAssertTrue(original.due.isEmpty)
        XCTAssertFalse(original.isOverdue(today: "2026-11-04"))
        XCTAssertEqual(try JSONDecoder().decode(OrbitTask.self, from: JSONEncoder().encode(original)), original)
    }
    func testDatedAndOverdueTasksKeepTheirRealDeadline() {
        let schedule = TaskSchedule(task: task(due: "2026-10-25"), today: today)
        XCTAssertFalse(schedule.usesDefaultDeadline)
        XCTAssertEqual(OrbitDate.day(schedule.start), "2026-10-20")
        XCTAssertEqual(OrbitDate.day(schedule.end), "2026-10-25")
        XCTAssertFalse(schedule.contains(today))
    }
    func testCompletedUndatedTaskStaysOnItsCompletionDate() {
        let completed = task(created: "2026-10-26").changingStatus(to: .done, now: OrbitDate.parseDay("2026-10-28")!)
        let schedule = TaskSchedule(task: completed, today: today)
        XCTAssertFalse(schedule.usesDefaultDeadline)
        XCTAssertEqual(OrbitDate.day(schedule.end), "2026-10-28")
        XCTAssertFalse(schedule.contains(today))
    }
    func testTimelineClipsBothEndsAndOmitsTasksOutsideWindow() {
        let schedule = TaskSchedule(task: task(due: "2026-11-30"), today: today)
        let dates = ScheduleCalendar.days(starting: today, count: 14)
        XCTAssertEqual(schedule.visibleOffsets(in: dates), 0...13)
        XCTAssertNil(TaskSchedule(task: task(due: "2026-10-25"), today: today).visibleOffsets(in: dates))
        XCTAssertNil(schedule.visibleOffsets(in: []))
    }
    func testEarlierDeadlineThanCreationIsStillVisibleOnDeadline() {
        let schedule = TaskSchedule(task: task(due: "2026-10-01"), today: today)
        XCTAssertEqual(schedule.start, schedule.end)
        XCTAssertTrue(schedule.contains(OrbitDate.parseDay("2026-10-01")!))
    }
    func testMonthGridHasMondayStartAndCorrectCrossMonthDays() {
        let dates = ScheduleCalendar.monthDays(today)
        XCTAssertEqual(dates.count, 35)
        XCTAssertEqual(OrbitDate.day(dates.first!), "2026-09-28")
        XCTAssertEqual(OrbitDate.day(dates.last!), "2026-11-01")
        let august = ScheduleCalendar.monthDays(OrbitDate.parseDay("2026-08-15")!)
        XCTAssertEqual(august.count, 42)
        XCTAssertEqual(OrbitDate.calendar.component(.weekday, from: august.first!), 2)
    }
    func testLeapYearYearBoundaryAndBeijingMidnight() {
        XCTAssertTrue(ScheduleCalendar.monthDays(OrbitDate.parseDay("2028-02-01")!).contains(OrbitDate.parseDay("2028-02-29")!))
        XCTAssertEqual(OrbitDate.day(ScheduleCalendar.weekStart(OrbitDate.parseDay("2027-01-01")!)), "2026-12-28")
        let utc = OrbitDate.parseTimestamp("2026-10-28T16:30:00Z")!
        XCTAssertEqual(OrbitDate.day(TaskSchedule(task: task(), today: utc).end), "2026-11-03")
        XCTAssertEqual(OrbitDate.day(ScheduleCalendar.movingMonth(OrbitDate.parseDay("2026-01-31")!, by: 1)), "2026-02-28")
    }
}
