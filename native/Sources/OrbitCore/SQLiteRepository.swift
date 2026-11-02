import Foundation
import CSQLite

private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SpaceDatabase {
    var handle: OpaquePointer?
    init(_ url: URL, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(url.path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            if let handle { sqlite3_close(handle) }; handle = nil
            throw OrbitError.invalid("SQLite：\(message)")
        }
        sqlite3_busy_timeout(handle, 5000)
        do {
            try execute("PRAGMA trusted_schema=OFF")
            try execute("PRAGMA foreign_keys=ON")
        } catch { sqlite3_close(handle); handle = nil; throw error }
    }
    deinit { if let handle { sqlite3_close(handle) } }
    func execute(_ sql: String, _ values: [String?] = []) throws {
        _ = try rows(sql, values)
    }
    func rows(_ sql: String, _ values: [String?] = []) throws -> [[String?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let result = value.map { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, transient) }
                ?? sqlite3_bind_null(statement, Int32(index + 1))
            guard result == SQLITE_OK else { throw failure() }
        }
        var result: [[String?]] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return result }
            guard code == SQLITE_ROW else { throw failure() }
            result.append((0..<sqlite3_column_count(statement)).map { column in
                sqlite3_column_text(statement, column).map { String(cString: $0) }
            })
        }
    }
    func scalar(_ sql: String, _ values: [String?] = []) throws -> String? { try rows(sql, values).first?.first ?? nil }
    func failure() -> OrbitError { .invalid("SQLite：\(String(cString: sqlite3_errmsg(handle)))") }
    func createSchema() throws {
        for sql in [
            "PRAGMA application_id=1397768515",
            "CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL)",
            "CREATE TABLE statuses(id TEXT PRIMARY KEY,position INTEGER NOT NULL,active INTEGER NOT NULL CHECK(active IN (0,1)))",
            "CREATE TABLE projects(id TEXT PRIMARY KEY,name TEXT NOT NULL UNIQUE COLLATE NOCASE)",
            "CREATE TABLE tasks(id TEXT PRIMARY KEY,status_id TEXT NOT NULL REFERENCES statuses(id),project_id TEXT REFERENCES projects(id),payload TEXT NOT NULL)",
            "CREATE INDEX task_status ON tasks(status_id)", "CREATE INDEX task_project ON tasks(project_id)",
            "CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)", "PRAGMA user_version=1"
        ] { try execute(sql) }
    }
    func readState() throws -> TaskBackup {
        guard ["1", "2", "3"].contains(try scalar("PRAGMA user_version") ?? "") else { throw OrbitError.unsupportedVersion }
        guard try scalar("PRAGMA quick_check") == "ok" else { throw OrbitError.invalid("数据库完整性检查失败。") }
        let definitions = try rows("SELECT id FROM statuses ORDER BY position").map { row -> TaskStatus in
            guard let raw = row[0], let status = TaskStatus(rawValue: raw) else { throw OrbitError.invalid("数据库状态无效。") }; return status
        }
        let disabled = try rows("SELECT id FROM statuses WHERE active=0 ORDER BY position").compactMap { $0[0].flatMap(TaskStatus.init(rawValue:)) }
        let projects = try rows("SELECT id,name FROM projects ORDER BY rowid").map { row -> TaskProject in
            guard let id = row[0], let name = row[1] else { throw OrbitError.invalid("数据库项目字段缺失。") }
            return try TaskProject(id: id, name: name).validated()
        }
        let tasks = try rows("SELECT payload FROM tasks ORDER BY rowid").map { row -> OrbitTask in
            guard let value = row[0] else { throw OrbitError.invalid("数据库任务内容缺失。") }
            return try JSONDecoder().decode(OrbitTask.self, from: Data(value.utf8))
        }
        var settings: [String: String] = [:]
        for row in try rows("SELECT key,value FROM settings") {
            guard let key = row[0], let value = row[1], settings[key] == nil else { throw OrbitError.invalid("数据库设置字段缺失或重复。") }
            settings[key] = value
        }
        guard let workspace = try scalar("SELECT value FROM metadata WHERE key='workspaceID'"),
              let revision = try scalar("SELECT value FROM metadata WHERE key='revision'") else { throw OrbitError.invalid("数据库身份信息缺失。") }
        let state = TaskBackup(tasks: tasks, statuses: definitions, projects: projects, disabledStatuses: disabled,
                               settings: settings, workspaceID: workspace, revision: revision)
        _ = try TaskBackup.decode(state.encoded())
        return state
    }
    func writeState(_ state: TaskBackup, revision: String) throws {
        // Older builds decode unknown task keys permissively. Bump the file version so they
        // refuse scheduled data instead of silently discarding explicit starts on the next save.
        let current = Int(try scalar("PRAGMA user_version") ?? "1") ?? 1
        let required = state.tasks.contains(where: { $0.richDescription != nil }) ? 3 : state.tasks.contains(where: { $0.startDate != nil }) ? 2 : 1
        try execute("PRAGMA user_version=\(max(current, required))")
        try execute("DELETE FROM tasks"); try execute("DELETE FROM statuses"); try execute("DELETE FROM projects"); try execute("DELETE FROM settings")
        for (position, status) in state.resolvedStatuses.enumerated() {
            try execute("INSERT INTO statuses VALUES(?,?,?)", [status.rawValue, String(position), state.resolvedDisabledStatuses.contains(status) ? "0" : "1"])
        }
        for project in state.resolvedProjects { try execute("INSERT INTO projects VALUES(?,?)", [project.id, project.name]) }
        for task in state.tasks {
            let data = try JSONEncoder().encode(task)
            try execute("INSERT INTO tasks VALUES(?,?,?,?)", [task.id, task.status.rawValue, task.projectID, String(decoding: data, as: UTF8.self)])
        }
        for (key, value) in state.resolvedSettings { try execute("INSERT INTO settings VALUES(?,?)", [key, value]) }
        try execute("INSERT OR REPLACE INTO metadata VALUES('workspaceID',?)", [state.workspaceID ?? UUID().uuidString])
        try execute("INSERT OR REPLACE INTO metadata VALUES('revision',?)", [revision])
    }
    func snapshot(to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".snapshot-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            let target = try SpaceDatabase(temporary)
            guard let backup = sqlite3_backup_init(target.handle, "main", handle, "main") else { throw target.failure() }
            let step = sqlite3_backup_step(backup, -1)
            let finish = sqlite3_backup_finish(backup)
            guard step == SQLITE_DONE, finish == SQLITE_OK else { throw target.failure() }
            try target.execute("PRAGMA journal_mode=DELETE")
        }
        let bytes = try Data(contentsOf: temporary)
        try bytes.write(to: destination, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}

/// SQLite owns transactions; a revision token also prevents stale UI writers from replacing newer data.
public final class TaskRepository {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("space.sqlite") }
    public var previousURL: URL { directory.appendingPathComponent("space.previous.sqlite") }
    public var legacyURL: URL { directory.appendingPathComponent("tasks.json") }
    public private(set) var state = TaskBackup(tasks: [])
    public var statuses: [TaskStatus] { state.resolvedStatuses }
    public var projects: [TaskProject] { state.resolvedProjects }
    public var disabledStatuses: [TaskStatus] { state.resolvedDisabledStatuses }
    public var settings: [String: String] { state.resolvedSettings }
    public var revision: String? { state.revision }
    private var didLoad = false
    private var expectedRevision: String?
    public init(directory: URL) { self.directory = directory }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent(".sqlite-write-lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw OrbitError.invalid("无法打开数据库写入锁。") }; defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw OrbitError.invalid("无法锁定数据库。") }; defer { flock(fd, LOCK_UN) }
        return try body()
    }
    public func load() throws -> [OrbitTask] {
        do { return try locked {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                var initial = TaskBackup(tasks: [])
                if FileManager.default.fileExists(atPath: legacyURL.path) {
                    let data = try Data(contentsOf: legacyURL)
                    initial = try TaskBackup.decode(data)
                    let preserved = directory.appendingPathComponent("tasks.before-sqlite.json")
                    if !FileManager.default.fileExists(atPath: preserved.path) { try data.write(to: preserved, options: .atomic) }
                }
                try createDatabase(initial, at: fileURL)
            }
            let database = try SpaceDatabase(fileURL)
            try database.execute("BEGIN")
            do {
                let loaded = try database.readState()
                try database.execute("COMMIT")
                state = loaded; expectedRevision = loaded.revision; didLoad = true
                return loaded.tasks
            } catch { try? database.execute("ROLLBACK"); throw error }
        } } catch { didLoad = false; expectedRevision = nil; throw error }
    }
    private func createDatabase(_ initial: TaskBackup, at destination: URL) throws {
        let temporary = directory.appendingPathComponent(".new-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            let database = try SpaceDatabase(temporary)
            try database.execute("BEGIN IMMEDIATE")
            try database.createSchema()
            try database.writeState(initial, revision: UUID().uuidString)
            try database.execute("COMMIT")
            _ = try database.readState()
        }
        guard rename(temporary.path, destination.path) == 0 else { throw OrbitError.invalid("数据库写入失败，原文件已保留。") }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
    public func save(_ tasks: [OrbitTask], statuses: [TaskStatus]? = nil, projects: [TaskProject]? = nil,
                     disabledStatuses: [TaskStatus]? = nil, settings: [String: String]? = nil,
                     allowRecovery: Bool = false, workspaceID: String? = nil) throws {
        let candidate = TaskBackup(tasks: try TaskBackup.validate(tasks), statuses: statuses ?? self.statuses,
                                   projects: try (projects ?? self.projects).map { try $0.validated() }, disabledStatuses: disabledStatuses ?? self.disabledStatuses,
                                   settings: settings ?? self.settings, workspaceID: workspaceID ?? state.workspaceID ?? UUID().uuidString)
        _ = try TaskBackup.decode(candidate.encoded())
        // Do not auto-add missing statuses during repository writes.
        try TaskBackup.validateStatuses(statuses ?? self.statuses, tasks: candidate.tasks)
        try locked {
            guard didLoad || allowRecovery else { throw OrbitError.invalid("先成功载入数据库，或明确导入有效备份恢复。") }
            if !didLoad {
                if FileManager.default.fileExists(atPath: fileURL.path) { try Data(contentsOf: fileURL).write(to: previousURL, options: .atomic) }
                try createDatabase(candidate, at: fileURL)
                let accepted = try SpaceDatabase(fileURL).readState()
                state = accepted; expectedRevision = accepted.revision; didLoad = true
                return
            }
            let database = try SpaceDatabase(fileURL)
            // Use the SQLite backup API, including committed WAL pages, before changing the current database.
            guard try database.scalar("SELECT value FROM metadata WHERE key='revision'") == expectedRevision else { throw OrbitError.conflict }
            try database.snapshot(to: previousURL)
            try database.execute("BEGIN IMMEDIATE")
            do {
                guard try database.scalar("SELECT value FROM metadata WHERE key='revision'") == expectedRevision else { throw OrbitError.conflict }
                let nextRevision = UUID().uuidString
                try database.writeState(candidate, revision: nextRevision)
                try database.execute("COMMIT")
                var accepted = candidate; accepted.revision = nextRevision
                state = accepted; expectedRevision = nextRevision
            } catch { try? database.execute("ROLLBACK"); throw error }
        }
    }
    public func savePreferences(_ preferences: [String: String]) throws {
        try TaskBackup.validateExtras(projects: projects, disabled: disabledStatuses, statuses: statuses,
                                     tasks: state.tasks, settings: preferences)
        guard didLoad else { throw OrbitError.invalid("先成功载入数据库。") }
        guard preferences != settings else { return }
        try locked {
            let database = try SpaceDatabase(fileURL)
            try database.execute("BEGIN IMMEDIATE")
            do {
                guard try database.scalar("SELECT value FROM metadata WHERE key='revision'") == expectedRevision else { throw OrbitError.conflict }
                // Preferences never rewrite attachment payloads or replace the last task recovery snapshot.
                try database.execute("DELETE FROM settings")
                for (key, value) in preferences { try database.execute("INSERT INTO settings VALUES(?,?)", [key, value]) }
                let revision = UUID().uuidString
                try database.execute("INSERT OR REPLACE INTO metadata VALUES('revision',?)", [revision])
                try database.execute("COMMIT")
                state.settings = preferences; state.revision = revision; expectedRevision = revision
            } catch { try? database.execute("ROLLBACK"); throw error }
        }
    }
    public func exportSnapshot(to destination: URL) throws {
        guard destination.standardizedFileURL != fileURL.standardizedFileURL,
              destination.standardizedFileURL != previousURL.standardizedFileURL else { throw OrbitError.invalid("请选择其他备份位置。") }
        try locked {
            let database = try SpaceDatabase(fileURL, readOnly: true)
            guard try database.scalar("SELECT value FROM metadata WHERE key='revision'") == expectedRevision else { throw OrbitError.conflict }
            try database.snapshot(to: destination)
        }
    }
    public static func readBackup(at url: URL) throws -> TaskBackup {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 64 * 1024 * 1024 else { throw OrbitError.tooLarge }
        let prefix = try FileHandle(forReadingFrom: url)
        defer { try? prefix.close() }
        if try prefix.read(upToCount: 16) == Data("SQLite format 3\0".utf8) {
            let database = try SpaceDatabase(url, readOnly: true)
            try database.execute("BEGIN")
            let result = try database.readState()
            try database.execute("COMMIT")
            return result
        }
        return try TaskBackup.decode(Data(contentsOf: url))
    }
}
