import XCTest
@testable import OrbitCore

final class SQLiteAndSyncTests: XCTestCase {
    private let now = OrbitDate.parseTimestamp("2026-10-29T05:00:00.000Z")!
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("space-sql-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    func testLegacyJSONMigrationPreservesOriginalAndStatusOrder() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let review = try TaskStatus.custom(title: "延期")
        let tasks = [OrbitTask(title: "历史任务", status: review, now: now)]
        let bytes = try TaskBackup(tasks: tasks, statuses: [.todo, review, .doing, .done]).encoded()
        let legacy = directory.appendingPathComponent("tasks.json"); try bytes.write(to: legacy)
        let repository = TaskRepository(directory: directory)
        XCTAssertEqual(try repository.load(), tasks)
        XCTAssertEqual(repository.statuses, [.todo, review, .doing, .done])
        XCTAssertEqual(try Data(contentsOf: legacy), bytes)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("tasks.before-sqlite.json")), bytes)
        XCTAssertEqual(try Data(contentsOf: repository.fileURL).prefix(16), Data("SQLite format 3\0".utf8))
        XCTAssertEqual(try TaskRepository(directory: directory).load(), tasks)
    }
    func testProjectSettingsDisabledStatusAndReorderingPersistTogether() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TaskRepository(directory: directory); _ = try repository.load()
        let project = TaskProject(name: "财务系统"), review = try TaskStatus.custom(title: "暂停")
        let task = OrbitTask(title: "项目任务", status: review, projectID: project.id, now: now)
        try repository.save([task], statuses: [review, .done, .doing, .todo], projects: [project], disabledStatuses: [review], settings: ["dark": "true", "navCollapsed": "false"])
        let reopened = TaskRepository(directory: directory)
        XCTAssertEqual(try reopened.load(), [task]); XCTAssertEqual(reopened.projects, [project]); XCTAssertEqual(reopened.disabledStatuses, [review])
        XCTAssertEqual(reopened.statuses, [review, .done, .doing, .todo]); XCTAssertEqual(reopened.settings["dark"], "true")
        let backup = try TaskBackup.decode(reopened.state.encoded())
        XCTAssertEqual(backup.version, 3); XCTAssertEqual(backup.resolvedProjects, [project]); XCTAssertEqual(backup.resolvedDisabledStatuses, [review])
    }
    func testProjectValidationRejectsMissingReferencesAndDuplicateNames() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TaskRepository(directory: directory); _ = try repository.load()
        XCTAssertThrowsError(try repository.save([OrbitTask(title: "坏引用", projectID: "missing", now: now)]))
        XCTAssertThrowsError(try repository.save([], projects: [TaskProject(name: "Alpha"), TaskProject(name: "alpha")]))
        XCTAssertThrowsError(try TaskProject(name: "\n").validated())
        XCTAssertThrowsError(try TaskProject(name: String(repeating: "a", count: 61)).validated())
        XCTAssertThrowsError(try repository.save([], disabledStatuses: [.done]))
        XCTAssertTrue(try repository.load().isEmpty)
    }
    func testProjectSearchAndFilter() throws {
        let task = OrbitTask(title: "更新报表", projectID: "finance", now: now)
        var query = TaskQuery(); query.text = "财务"
        XCTAssertEqual(query.apply(to: [task], projectNames: ["finance": "财务系统"]), [task])
        query.text = ""; query.projectID = "other"; XCTAssertTrue(query.apply(to: [task]).isEmpty)
        query.projectID = "finance"; XCTAssertEqual(query.apply(to: [task]), [task])
    }
    func testSQLiteSnapshotIncludesCommittedWALAndIsStandalone() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TaskRepository(directory: directory); _ = try repository.load()
        let heldConnection = try SpaceDatabase(repository.fileURL)
        try heldConnection.execute("PRAGMA journal_mode=WAL")
        let task = OrbitTask(title: "WAL中已提交的数据", now: now); try repository.save([task])
        let snapshot = directory.appendingPathComponent("export.sqlite"); try repository.exportSnapshot(to: snapshot)
        XCTAssertEqual(try TaskRepository.readBackup(at: snapshot).tasks, [task])
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.path + "-wal"))
        XCTAssertEqual(try SpaceDatabase(snapshot, readOnly: true).scalar("PRAGMA journal_mode"), "delete")
    }
    func testTransactionFailureRollsBackAllTablesAndKeepsRevision() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TaskRepository(directory: directory); _ = try repository.load()
        let task = OrbitTask(title: "保留内容", now: now); try repository.save([task]); let revision = repository.revision
        let database = try SpaceDatabase(repository.fileURL)
        try database.execute("CREATE TRIGGER reject_tasks BEFORE INSERT ON tasks BEGIN SELECT RAISE(ABORT,'forced failure'); END")
        XCTAssertThrowsError(try repository.save([task.changingStatus(to: .doing)], settings: ["dark": "true"]))
        XCTAssertEqual(repository.revision, revision)
        XCTAssertEqual(try TaskRepository(directory: directory).load(), [task])
        XCTAssertEqual(try database.scalar("SELECT COUNT(*) FROM statuses"), "3")
        XCTAssertEqual(try database.scalar("SELECT COUNT(*) FROM settings"), "0")
    }
    func testCorruptReloadCannotOverwriteUntilExplicitRecovery() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TaskRepository(directory: directory); _ = try repository.load()
        let corrupt = Data("broken sqlite".utf8); try corrupt.write(to: repository.fileURL, options: .atomic)
        XCTAssertThrowsError(try repository.load()); XCTAssertThrowsError(try repository.save([]))
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), corrupt)
        try repository.save([], allowRecovery: true)
        XCTAssertEqual(try Data(contentsOf: repository.previousURL), corrupt)
        XCTAssertTrue(try repository.load().isEmpty)
    }
    func testSnapshotExportCannotOverwriteLiveDatabase() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TaskRepository(directory: directory); _ = try repository.load()
        XCTAssertThrowsError(try repository.exportSnapshot(to: repository.fileURL))
        XCTAssertThrowsError(try repository.exportSnapshot(to: repository.previousURL))
    }
    func testSyncCipherChecksCodeTamperingAndExpiry() throws {
        let code = try DatabaseSync.generateCode(), bytes = Data("private snapshot".utf8)
        let packet = try DatabaseSync.seal(bytes, code: code, now: now, lifetime: 60)
        XCTAssertEqual(try DatabaseSync.unseal(packet, code: code.lowercased(), now: now), bytes)
        XCTAssertThrowsError(try DatabaseSync.unseal(packet, code: try DatabaseSync.generateCode(), now: now))
        XCTAssertThrowsError(try DatabaseSync.unseal(packet, code: code, now: now.addingTimeInterval(61)))
        var tampered = packet; tampered[tampered.count / 2] ^= 1
        XCTAssertThrowsError(try DatabaseSync.unseal(tampered, code: code, now: now))
        XCTAssertThrowsError(try DatabaseSync.normalizeCode("123456"))
        XCTAssertFalse(String(decoding: packet, as: UTF8.self).contains("private snapshot"))
    }
    func testLocalTransportUploadsEncryptedSnapshotAndDownloadsByCode() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let remote = directory.appendingPathComponent("remote"); try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        let source = TaskRepository(directory: directory.appendingPathComponent("source")); _ = try source.load()
        let project = TaskProject(name: "跨设备项目"), task = OrbitTask(title: "同步任务", projectID: project.id, now: now)
        try source.save([task], projects: [project], settings: ["dark": "true"])
        let snapshot = directory.appendingPathComponent("snapshot.sqlite"); try source.exportSnapshot(to: snapshot)
        let config = SyncConfiguration(location: remote.path)
        let receipt = try await DatabaseSync.upload(snapshot: snapshot, configuration: config, now: now)
        let downloaded = try await DatabaseSync.download(code: receipt.code, configuration: config, now: now)
        XCTAssertEqual(downloaded.backup.tasks, [task]); XCTAssertEqual(downloaded.backup.resolvedProjects, [project]); XCTAssertEqual(downloaded.backup.resolvedSettings["dark"], "true")
        let target = TaskRepository(directory: directory.appendingPathComponent("target")); _ = try target.load()
        try target.save(downloaded.backup.tasks, statuses: downloaded.backup.resolvedStatuses, projects: downloaded.backup.resolvedProjects, settings: downloaded.backup.resolvedSettings)
        XCTAssertEqual(try TaskRepository(directory: target.directory).load(), [task])
        let artifacts = try FileManager.default.contentsOfDirectory(at: remote, includingPropertiesForKeys: nil)
        XCTAssertEqual(artifacts.count, 1)
        XCTAssertFalse(try Data(contentsOf: artifacts[0]).starts(with: Data("SQLite format 3".utf8)))
    }
    func testInvalidNetworkLocationAndMissingBackupAreReported() async throws {
        for value in ["", "http://example.com/", "https://user:password@example.com/", "https://example.com/?token=secret"] { XCTAssertThrowsError(try SyncConfiguration(location: value).baseURL()) }
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await DatabaseSync.download(code: try DatabaseSync.generateCode(), configuration: SyncConfiguration(location: directory.path), now: now)
            XCTFail("missing artifact should fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("没有找到")) }
    }
    func testMergeKeepsBothDevicesTasksAndReusesProjectNames() throws {
        let leftProject = TaskProject(id: "left-project", name: "财务"), rightProject = TaskProject(id: "right-project", name: "财务")
        let original = OrbitTask(id: "shared", title: "初版", projectID: leftProject.id, now: now)
        var newer = original; newer.title = "较新版本"; newer.projectID = rightProject.id; newer.updatedAt = OrbitDate.timestamp(now.addingTimeInterval(20))
        let localOnly = OrbitTask(id: "local", title: "仅本机", now: now), remoteOnly = OrbitTask(id: "remote", title: "仅另一设备", now: now)
        let merged = try DatabaseSync.merge(local: TaskBackup(tasks: [original, localOnly], projects: [leftProject], settings: ["sync.location": "/local", "dark": "false"]),
                                           remote: TaskBackup(tasks: [newer, remoteOnly], projects: [rightProject], settings: ["sync.location": "/remote", "dark": "true"]))
        XCTAssertEqual(merged.tasks.count, 3); XCTAssertEqual(merged.tasks.first { $0.id == "shared" }?.title, "较新版本")
        XCTAssertEqual(merged.tasks.first { $0.id == "shared" }?.projectID, leftProject.id); XCTAssertEqual(merged.resolvedProjects.count, 1)
        XCTAssertEqual(merged.resolvedSettings["sync.location"], "/local"); XCTAssertEqual(merged.resolvedSettings["dark"], "true")
    }
    func testMergeRefusesEqualTimestampConflicts() throws {
        let local = OrbitTask(id: "same", title: "本机修改", now: now)
        var remote = local; remote.title = "另一设备修改"
        XCTAssertThrowsError(try DatabaseSync.merge(local: TaskBackup(tasks: [local]), remote: TaskBackup(tasks: [remote])))
    }
}
