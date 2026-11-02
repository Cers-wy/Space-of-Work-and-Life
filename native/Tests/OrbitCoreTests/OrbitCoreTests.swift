import XCTest
@testable import OrbitCore

final class OrbitCoreTests: XCTestCase {
    private let now = OrbitDate.parseTimestamp("2026-10-28T16:05:00.000Z")!

    func testShanghaiDateBoundaryAndLeapYears() {
        XCTAssertEqual(OrbitDate.day(now), "2026-10-29")
        XCTAssertEqual(OrbitDate.day(now.addingTimeInterval(-600)), "2026-10-28")
        XCTAssertNotNil(OrbitDate.parseDay("2028-02-29"))
        for invalid in ["2026-02-29", "2026-04-31", "2026-13-01", "2026-1-01", "2026-00-01", "not-a-date"] {
            XCTAssertNil(OrbitDate.parseDay(invalid), invalid)
        }
    }

    func testValidationTrimsTitleAndRejectsInvalidInput() throws {
        var task = OrbitTask(title: "  开发原生应用 \n", now: now)
        XCTAssertEqual(try task.validated().title, "开发原生应用")
        task.title = " \n "; XCTAssertThrowsError(try task.validated())
        task.title = String(repeating: "任", count: 101); XCTAssertThrowsError(try task.validated())
        task.title = "任务"; task.description = String(repeating: "a", count: 5001)
        XCTAssertThrowsError(try task.validated())
        task.description = ""; task.due = "2026-02-30"; XCTAssertThrowsError(try task.validated())
        task.due = ""; task.createdAt = "invalid"; XCTAssertThrowsError(try task.validated())
    }

    func testCompletionAndReopeningTimestampRules() throws {
        let task = OrbitTask(title: "流程", now: now)
        let done = task.changingStatus(to: .done, now: now.addingTimeInterval(10))
        XCTAssertEqual(done.completedAt, done.updatedAt)
        XCTAssertEqual(done.createdAt, task.createdAt)
        XCTAssertEqual(done.changingStatus(to: .done, now: now.addingTimeInterval(20)), done)
        let reopened = done.changingStatus(to: .todo, now: now.addingTimeInterval(30))
        XCTAssertNil(reopened.completedAt)
        let again = reopened.changingStatus(to: .done, now: now.addingTimeInterval(40))
        XCTAssertNotEqual(again.completedAt, done.completedAt)
        XCTAssertNoThrow(try again.validated())
    }

    func testCompletedTaskCannotBeOverdueOrToday() {
        let past = OrbitTask(title: "过去", due: "2026-10-28", now: now)
        let today = OrbitTask(title: "今天", due: "2026-10-29", now: now)
        let noDate = OrbitTask(title: "无日期", now: now)
        XCTAssertTrue(past.isOverdue(today: "2026-10-29"))
        XCTAssertFalse(past.changingStatus(to: .done).isOverdue(today: "2026-10-29"))
        XCTAssertTrue(today.isToday("2026-10-29"))
        XCTAssertFalse(today.changingStatus(to: .done).isToday("2026-10-29"))
        XCTAssertFalse(noDate.isOverdue(today: "2026-10-29"))
    }

    func testEveryScopeAndCombinedFilters() {
        let samples = SampleTasks.make(now: now)
        XCTAssertEqual(samples.count, 10)
        for (scope, count) in [(TaskScope.all, 10), (.today, 3), (.overdue, 1), (.done, 3), (.work, 4), (.personal, 3), (.life, 3)] {
            var query = TaskQuery(); query.scope = scope
            XCTAssertEqual(query.apply(to: samples, today: "2026-10-29").count, count, scope.title)
        }
        var query = TaskQuery(); query.scope = .work; query.priority = .high; query.status = .doing
        XCTAssertEqual(query.apply(to: samples, today: "2026-10-29").count, 1)
        query.text = "关键交互" // Search descriptions as well as titles.
        XCTAssertEqual(query.apply(to: samples).count, 1)
        query.category = .life
        XCTAssertTrue(query.apply(to: samples).isEmpty)
    }

    func testDateFilterAndStableSortRules() {
        let early = OrbitTask(id: "early", title: "先", priority: .low, due: "2026-10-28", now: now)
        let high = OrbitTask(id: "high", title: "高", priority: .high, due: "2026-10-30", now: now.addingTimeInterval(10))
        let none = OrbitTask(id: "none", title: "无日期", now: now.addingTimeInterval(20))
        var query = TaskQuery()
        XCTAssertEqual(query.apply(to: [none, high, early]).map(\.id), ["early", "high", "none"])
        query.sort = .priority
        XCTAssertEqual(query.apply(to: [early, none, high]).map(\.id), ["high", "none", "early"])
        query.sort = .created
        XCTAssertEqual(query.apply(to: [early, none, high]).map(\.id), ["none", "high", "early"])
        query.dueFilter = "none"
        XCTAssertEqual(query.apply(to: [early, none, high]).map(\.id), ["none"])
        query.dueFilter = "overdue"
        XCTAssertEqual(query.apply(to: [early, none, high], today: "2026-10-29").map(\.id), ["early"])
    }

    func testBackupRoundTripAndPrototypeCompatibility() throws {
        let tasks = SampleTasks.make(now: now)
        let decoded = try TaskBackup.decode(TaskBackup(tasks: tasks, now: now).encoded())
        XCTAssertEqual(decoded.tasks, tasks)
        // This is the exact field layout used by the HTML prototype's export.
        let htmlJSON = #"{"app":"ORBIT","version":1,"exportedAt":"2026-10-29T01:00:00.000Z","tasks":[{"id":"html-1","title":"从浏览器迁移","description":"原型备份","category":"work","status":"todo","priority":"medium","due":"2026-10-29","createdAt":"2026-10-28T12:00:00.000Z","updatedAt":"2026-10-28T12:00:00.000Z","completedAt":null}]}"#
        let imported = try TaskBackup.decode(Data(htmlJSON.utf8))
        XCTAssertEqual(imported.tasks[0].id, "html-1")
        XCTAssertEqual(imported.tasks[0].due, "2026-10-29")
        XCTAssertEqual(try TaskBackup.decode(imported.encoded()).tasks, imported.tasks)
    }

    func testImportRejectsDuplicatesBadStateUnknownVersionAndOversize() throws {
        let task = OrbitTask(title: "有效任务", now: now)
        XCTAssertThrowsError(try TaskBackup.decode(TaskBackup(tasks: [task, task]).encoded()))
        var invalid = task; invalid.status = .done
        XCTAssertThrowsError(try TaskBackup.decode(TaskBackup(tasks: [invalid]).encoded()))
        var backup = TaskBackup(tasks: [task]); backup.version = 99
        XCTAssertThrowsError(try TaskBackup.decode(backup.encoded()))
        XCTAssertThrowsError(try TaskBackup.decode(Data("不是JSON".utf8)))
        XCTAssertThrowsError(try TaskBackup.decode(Data(repeating: 32, count: 12 * 1024 * 1024 + 1)))
        XCTAssertThrowsError(try TaskBackup.validate(Array(repeating: task, count: 10001)))
    }

    func testExportKeepsExplicitNullForHTMLImporter() throws {
        let data = try TaskBackup(tasks: [OrbitTask(title: "双向迁移", now: now)]).encoded()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tasks = try XCTUnwrap(object["tasks"] as? [[String: Any]])
        XCTAssertTrue(tasks[0]["completedAt"] is NSNull)
    }

    func testAtomicPersistenceReopenAndPreviousBackup() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TaskRepository(directory: directory)
        XCTAssertEqual(try repository.load(), [])
        let task = OrbitTask(title: "本地保存", now: now)
        try repository.save([task])
        var edited = task; edited.title = "已修改"
        try repository.save([edited])
        XCTAssertEqual(try TaskRepository(directory: directory).load(), [edited])
        XCTAssertEqual(try TaskRepository.readBackup(at: repository.previousURL).tasks, [task])
    }

    func testStaleWriterCannotOverwriteExternalModification() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = TaskRepository(directory: directory), second = TaskRepository(directory: directory)
        _ = try first.load(); _ = try second.load()
        let task = OrbitTask(title: "另一进程保存", now: now)
        try first.save([task])
        XCTAssertThrowsError(try second.save([]))
        XCTAssertEqual(try first.load(), [task])
        _ = try second.load(); try second.save([])
        XCTAssertEqual(try first.load(), [])
    }

    func testCorruptFileIsPreservedUntilExplicitRecovery() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TaskRepository(directory: directory)
        let corrupt = Data("broken-data".utf8)
        try corrupt.write(to: repository.fileURL)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), corrupt)
        let restored = OrbitTask(title: "恢复任务", now: now)
        try repository.save([restored], allowRecovery: true)
        XCTAssertEqual(try Data(contentsOf: repository.previousURL), corrupt)
        XCTAssertEqual(try repository.load(), [restored])
    }

    func testFailedWriteLeavesAcceptedDataUntouched() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TaskRepository(directory: directory)
        _ = try repository.load()
        let task = OrbitTask(title: "保留已保存内容", now: now)
        try repository.save([task])
        // Force the automatic backup write to fail (a folder occupies its URL).
        try FileManager.default.removeItem(at: repository.previousURL)
        try FileManager.default.createDirectory(at: repository.previousURL, withIntermediateDirectories: true)
        XCTAssertThrowsError(try repository.save([]))
        XCTAssertEqual(try TaskRepository(directory: directory).load(), [task])
        try FileManager.default.removeItem(at: repository.previousURL)
        try repository.save([]) // A retry succeeds with the same expected revision.
        XCTAssertEqual(try repository.load(), [])
    }

    func testCustomStatusesRoundTripAndRetainEmptyColumns() throws {
        let review = try TaskStatus.custom(title: "  待审核  ")
        let blocked = try TaskStatus.custom(title: "等待反馈")
        let definitions: [TaskStatus] = [.todo, .doing, review, blocked, .done]
        let task = OrbitTask(title: "评审方案", status: review, now: now)
        let backup = try TaskBackup.decode(TaskBackup(tasks: [task], statuses: definitions).encoded())
        XCTAssertEqual(backup.version, 2)
        XCTAssertEqual(backup.tasks[0].status.title, "待审核")
        XCTAssertEqual(backup.resolvedStatuses, definitions)
        let empty = try TaskBackup.decode(TaskBackup(tasks: [], statuses: definitions).encoded())
        XCTAssertEqual(empty.resolvedStatuses, definitions)
        XCTAssertTrue(empty.tasks.isEmpty)
        let legacy = try TaskBackup.decode(TaskBackup(tasks: [OrbitTask(title: "旧版")]).encoded())
        XCTAssertEqual(legacy.version, 1)
        XCTAssertNil(legacy.statuses)
        XCTAssertEqual(legacy.resolvedStatuses, TaskStatus.allCases)
    }

    func testCustomStatusValidationAndInvalidReferences() throws {
        for name in ["", " ", "已完成", "待办", "进行中", "审核\n通过", String(repeating: "审", count: 21)] {
            XCTAssertThrowsError(try TaskStatus.custom(title: name), name)
        }
        XCTAssertNil(TaskStatus(rawValue: "unknown"))
        let review = try TaskStatus.custom(title: "Review")
        let duplicate = try TaskStatus.custom(title: "review")
        XCTAssertThrowsError(try TaskBackup.validateStatuses([.todo, .doing, review, duplicate, .done], tasks: []))
        let task = OrbitTask(title: "引用状态", status: review, now: now)
        XCTAssertThrowsError(try TaskBackup.validateStatuses(TaskStatus.allCases, tasks: [task]))
        var backup = TaskBackup(tasks: [task], statuses: [.todo, .doing, review, .done])
        backup.statuses = TaskStatus.allCases
        XCTAssertThrowsError(try TaskBackup.decode(backup.encoded()))
        backup.statuses = [.todo, .doing, review, review, .done]
        XCTAssertThrowsError(try TaskBackup.decode(backup.encoded()))
        backup.statuses = [.todo, .doing, review, .done]; backup.version = 1
        XCTAssertThrowsError(try TaskBackup.decode(backup.encoded()))
    }

    func testCustomStatusRepositoryReopenBackupAndOrdinarySave() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let review = try TaskStatus.custom(title: "待审核")
        let definitions: [TaskStatus] = [.todo, .doing, review, .done]
        let repository = TaskRepository(directory: directory)
        _ = try repository.load()
        try repository.save([], statuses: definitions)
        let reopened = TaskRepository(directory: directory)
        XCTAssertEqual(try reopened.load(), [])
        XCTAssertEqual(reopened.statuses, definitions)
        let task = OrbitTask(title: "审核任务", status: review, now: now)
        try reopened.save([task])
        XCTAssertEqual(try TaskRepository.readBackup(at: reopened.previousURL).resolvedStatuses, definitions)
        let again = TaskRepository(directory: directory)
        XCTAssertEqual(try again.load(), [task])
        XCTAssertEqual(again.statuses, definitions)
        try again.save([])
        XCTAssertEqual(try TaskRepository.readBackup(at: again.fileURL).resolvedStatuses, definitions)
    }

    func testCustomStatusCompletionReopeningAndFiltering() throws {
        let review = try TaskStatus.custom(title: "待审核")
        let task = OrbitTask(title: "审核任务", status: review, due: "2026-10-28", now: now)
        XCTAssertTrue(task.isOverdue(today: "2026-10-29"))
        XCTAssertNil(task.completedAt)
        var query = TaskQuery(); query.status = review
        XCTAssertEqual(query.apply(to: [task], today: "2026-10-29"), [task])
        let done = task.changingStatus(to: .done, now: now.addingTimeInterval(20))
        XCTAssertNotNil(done.completedAt)
        XCTAssertFalse(done.isOverdue(today: "2026-10-29"))
        let reopened = done.changingStatus(to: review, now: now.addingTimeInterval(30))
        XCTAssertNil(reopened.completedAt)
        XCTAssertNoThrow(try reopened.validated())
        XCTAssertEqual(query.apply(to: [done, reopened], today: "2026-10-29"), [reopened])
    }

    func testFailedCustomStatusSavePreservesDefinitionsAndData() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TaskRepository(directory: directory)
        _ = try repository.load()
        let task = OrbitTask(title: "保留任务", now: now)
        try repository.save([task])
        let original = try Data(contentsOf: repository.fileURL)
        try FileManager.default.removeItem(at: repository.previousURL)
        try FileManager.default.createDirectory(at: repository.previousURL, withIntermediateDirectories: true)
        let review = try TaskStatus.custom(title: "待审核")
        XCTAssertThrowsError(try repository.save([task], statuses: [.todo, .doing, review, .done]))
        XCTAssertEqual(repository.statuses, TaskStatus.allCases)
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), original)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
