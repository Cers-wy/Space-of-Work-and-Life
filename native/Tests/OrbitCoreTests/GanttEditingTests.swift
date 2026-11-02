import XCTest
@testable import OrbitCore

final class GanttEditingTests: XCTestCase {
    private let today = OrbitDate.parseDay("2026-10-29")!
    private var task: OrbitTask { OrbitTask(id: "drag-fixture", title: "拖拽排期", due: "2026-11-03", now: OrbitDate.parseDay("2026-10-27")!) }
    private func day(_ value: String) -> Date { OrbitDate.parseDay(value)! }
    func testMovePreservesInclusiveDurationAndCreationAndCompletionMetadata() throws {
        let original = task.changingStatus(to: .done, now: today)
        let schedule = TaskSchedule(task: original, today: today)
        let moved = schedule.adjusting(.move, by: 4)
        let changed = try moved.applying(to: original, now: today)
        XCTAssertEqual(changed.startDate, "2026-10-31"); XCTAssertEqual(changed.due, "2026-11-07")
        XCTAssertEqual(changed.createdAt, original.createdAt); XCTAssertEqual(changed.completedAt, original.completedAt)
        XCTAssertEqual(changed.status, .done)
        XCTAssertEqual(moved.end.timeIntervalSince(moved.start), schedule.end.timeIntervalSince(schedule.start))
    }
    func testResizeEachEdgeClampsToOneDayWithoutCrossing() {
        let schedule = TaskSchedule(task: task, today: today)
        XCTAssertEqual(schedule.adjusting(.start, by: 50).start, schedule.end)
        XCTAssertEqual(schedule.adjusting(.end, by: -50).end, schedule.start)
        XCTAssertEqual(OrbitDate.day(schedule.adjusting(.start, by: -2).start), "2026-10-25")
        XCTAssertEqual(OrbitDate.day(schedule.adjusting(.end, by: 5).end), "2026-11-08")
        XCTAssertEqual(schedule.adjusting(.move, by: 0), schedule)
    }
    func testClippedBarStillMovesFullIntervalAcrossYearAndLeapDay() {
        let schedule = TaskSchedule(start: day("2028-02-27"), end: day("2028-03-04"))
        XCTAssertEqual(schedule.visibleOffsets(in: ScheduleCalendar.days(starting: day("2028-02-29"), count: 3)), 0...2)
        XCTAssertEqual(OrbitDate.day(schedule.adjusting(.move, by: 2).start), "2028-02-29")
        XCTAssertEqual(OrbitDate.day(TaskSchedule(start: day("2026-12-30"), end: day("2027-01-02")).adjusting(.move, by: 2).end), "2027-01-04")
    }
    func testExplicitStartPersistsIndependentlyOfCreatedAtAndDefaultDeadline() throws {
        var original = task; original.startDate = "2026-10-30"
        XCTAssertEqual(TaskSchedule(task: original, today: today).start, day("2026-10-30"))
        original.due = ""; original.startDate = "2026-11-20"
        let interval = TaskSchedule(task: original, today: today)
        XCTAssertEqual(interval.start, day("2026-11-20")); XCTAssertEqual(interval.end, day("2026-11-25"))
        XCTAssertTrue(interval.usesDefaultDeadline)
        let changed = try interval.adjusting(.end, by: 1).applying(to: original)
        XCTAssertEqual(changed.due, "2026-11-26"); XCTAssertFalse(TaskSchedule(task: changed, today: today).usesDefaultDeadline)
    }
    func testInvalidStartAndInvertedDatesAreRejected() {
        var original = task; original.startDate = "2026-02-30"; XCTAssertThrowsError(try original.validated())
        original.startDate = "2026-11-04"; XCTAssertThrowsError(try original.validated())
        original.startDate = "2026-11-03"; XCTAssertNoThrow(try original.validated())
    }
    func testV5DatesRoundTripWithAttachmentsAndBlockDowngrade() throws {
        var original = task; original.startDate = "2026-10-30"
        original.attachments = [TaskAttachment(name: "说明.txt", typeIdentifier: "public.text", data: Data("附件".utf8))]
        let backup = TaskBackup(tasks: [original]); XCTAssertEqual(backup.version, 5)
        let decoded = try TaskBackup.decode(backup.encoded()); XCTAssertEqual(decoded.tasks, [original])
        var invalid = backup; invalid.version = 4; XCTAssertThrowsError(try TaskBackup.decode(invalid.encoded()))
        let legacy = TaskBackup(tasks: [task]); XCTAssertEqual(legacy.version, 1)
        XCTAssertNil(try TaskBackup.decode(legacy.encoded()).tasks.first?.startDate)
    }
    func testProjectHierarchyUsesStableProjectOrderAndFilteredTasks() {
        let projects = [TaskProject(id: "b", name: "乙"), TaskProject(id: "a", name: "甲"), TaskProject(id: "empty", name: "空项目")]
        var a = task; a.projectID = "a"
        var b = task; b.id = "b-task"; b.projectID = "b"
        var none = task; none.id = "unassigned"
        let groups = GanttProjectGroup.make(tasks: [a, none, b], projects: projects)
        XCTAssertEqual(groups.map(\.id), ["b", "a", ""])
        XCTAssertEqual(groups.map { $0.tasks.count }, [1, 1, 1]); XCTAssertEqual(groups.last?.name, "未分配项目")
        XCTAssertEqual(GanttProjectGroup.make(tasks: [a], projects: projects).map(\.id), ["a"])
        XCTAssertTrue(GanttProjectGroup.make(tasks: [], projects: projects).isEmpty)
        XCTAssertEqual(groups.first?.schedule(today: today), TaskSchedule(start: day("2026-10-27"), end: day("2026-11-03")))
    }
    func testDateEditSQLiteSnapshotAndUndoPayloadRetainStart() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = TaskRepository(directory: folder); _ = try repository.load(); try repository.save([task])
        let changed = try TaskSchedule(task: task, today: today).adjusting(.start, by: 1).applying(to: task)
        try repository.save([changed]); XCTAssertEqual(try TaskRepository(directory: folder).load(), [changed])
        XCTAssertEqual(try SpaceDatabase(repository.fileURL).scalar("PRAGMA user_version"), "2")
        XCTAssertEqual(try SpaceDatabase(repository.previousURL).scalar("PRAGMA user_version"), "1")
        XCTAssertEqual(try TaskRepository.readBackup(at: repository.previousURL).tasks, [task])
        let snapshot = folder.appendingPathComponent("export.sqlite"); try repository.exportSnapshot(to: snapshot)
        XCTAssertEqual(try TaskRepository.readBackup(at: snapshot).tasks, [changed])
        try repository.save([task])
        XCTAssertEqual(try SpaceDatabase(repository.fileURL).scalar("PRAGMA user_version"), "2")
    }
    func testPreferenceUpdateDoesNotRewriteTasksOrReplaceRecoverySnapshot() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = TaskRepository(directory: folder); _ = try repository.load()
        try repository.save([task]); try repository.save([task.changingStatus(to: .doing)])
        let previous = try Data(contentsOf: repository.previousURL)
        let database = try SpaceDatabase(repository.fileURL)
        try database.execute("CREATE TRIGGER prevent_payload_rewrite BEFORE DELETE ON tasks BEGIN SELECT RAISE(ABORT,'payload rewrite'); END")
        let oldRevision = repository.revision
        try repository.savePreferences(["viewMode": "gantt"])
        XCTAssertNotEqual(oldRevision, repository.revision)
        XCTAssertEqual(try Data(contentsOf: repository.previousURL), previous)
        let reopened = TaskRepository(directory: folder)
        XCTAssertEqual(try reopened.load(), repository.state.tasks); XCTAssertEqual(reopened.settings["viewMode"], "gantt")
        let unchangedRevision = repository.revision
        try repository.savePreferences(repository.settings); XCTAssertEqual(repository.revision, unchangedRevision)
    }
    func testPreferencesStillRejectStaleWritersAndRollBackOnFailure() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = TaskRepository(directory: folder); _ = try first.load()
        let stale = TaskRepository(directory: folder); _ = try stale.load()
        try first.savePreferences(["dark": "true"])
        XCTAssertThrowsError(try stale.savePreferences(["viewMode": "list"]))
        let database = try SpaceDatabase(first.fileURL)
        try database.execute("CREATE TRIGGER prevent_setting BEFORE INSERT ON settings BEGIN SELECT RAISE(ABORT,'preference failure'); END")
        let revision = first.revision
        XCTAssertThrowsError(try first.savePreferences(["dark": "false"]))
        XCTAssertEqual(first.revision, revision)
        let reopened = TaskRepository(directory: folder); _ = try reopened.load()
        XCTAssertEqual(reopened.settings, ["dark": "true"])
    }
}
