import Foundation

public struct TaskBackup: Codable {
    public static let maximumBytes = 64 * 1024 * 1024
    public var app = "ORBIT"
    public var version = 1
    public var exportedAt: String
    public var tasks: [OrbitTask]
    /// Omitted for legacy V1 backups. V2 retains empty custom columns as well.
    public var statuses: [TaskStatus]?
    public var projects: [TaskProject]?
    public var disabledStatuses: [TaskStatus]?
    public var settings: [String: String]?
    public var workspaceID: String?
    public var revision: String?
    public var resolvedProjects: [TaskProject] { projects ?? [] }
    public var resolvedDisabledStatuses: [TaskStatus] { disabledStatuses ?? [] }
    public var resolvedSettings: [String: String] { settings ?? [:] }
    public var resolvedStatuses: [TaskStatus] { statuses ?? TaskStatus.allCases }
    public init(tasks: [OrbitTask], statuses: [TaskStatus] = TaskStatus.allCases, projects: [TaskProject] = [],
                disabledStatuses: [TaskStatus] = [], settings: [String: String] = [:],
                workspaceID: String? = nil, revision: String? = nil, now: Date = Date()) {
        self.tasks = tasks; exportedAt = OrbitDate.timestamp(now)
        var definitions = statuses
        for status in tasks.map(\.status) where !definitions.contains(status) { definitions.insert(status, at: max(0, definitions.count - 1)) }
        if definitions != TaskStatus.allCases {
            self.statuses = definitions; version = 2; app = "Space"
        }
        if !projects.isEmpty || !disabledStatuses.isEmpty || !settings.isEmpty || workspaceID != nil {
            self.statuses = definitions; self.projects = projects; self.disabledStatuses = disabledStatuses
            self.settings = settings; self.workspaceID = workspaceID; self.revision = revision
            version = 3; app = "Space"
        }
        if tasks.contains(where: { !$0.attachments.isEmpty }) { version = 4; app = "Space" }
        if tasks.contains(where: { $0.startDate != nil }) { version = 5; app = "Space" }
        if tasks.contains(where: { $0.richDescription != nil }) { version = 6; app = "Space" }
    }
    public static func decode(_ data: Data) throws -> TaskBackup {
        guard data.count <= Self.maximumBytes else { throw OrbitError.tooLarge }
        let backup: TaskBackup
        do { backup = try JSONDecoder().decode(TaskBackup.self, from: data) }
        catch { throw OrbitError.invalid("无法读取备份：文件格式、任务字段或日期格式有误。") }
        guard [1, 2, 3, 4, 5, 6].contains(backup.version) else { throw OrbitError.unsupportedVersion }
        guard backup.version >= 4 || !backup.tasks.contains(where: { !$0.attachments.isEmpty }) else {
            throw OrbitError.invalid("图片与附件需要Space V4格式备份。")
        }
        guard backup.version >= 5 || !backup.tasks.contains(where: { $0.startDate != nil }) else {
            throw OrbitError.invalid("开始日期需要Space V5格式备份。")
        }
        guard backup.version >= 6 || !backup.tasks.contains(where: { $0.richDescription != nil }) else {
            throw OrbitError.invalid("富文本需要Space V6格式备份。")
        }
        var result = backup
        result.tasks = try validate(backup.tasks)
        try validateStatuses(backup.resolvedStatuses, tasks: result.tasks)
        guard backup.version >= 2 || (backup.statuses == nil && !result.tasks.contains(where: { $0.status.isCustom })) else {
            throw OrbitError.invalid("自定义状态需要Space V2格式备份。")
        }
        result.projects = try backup.resolvedProjects.map { try $0.validated() }
        try validateExtras(projects: result.resolvedProjects, disabled: result.resolvedDisabledStatuses,
                           statuses: result.resolvedStatuses, tasks: result.tasks, settings: result.resolvedSettings)
        if backup.version < 3 && (!result.resolvedProjects.isEmpty || !result.resolvedDisabledStatuses.isEmpty || !result.resolvedSettings.isEmpty || result.tasks.contains(where: { $0.projectID != nil })) {
            throw OrbitError.invalid("项目与状态管理需要Space V3格式备份。")
        }
        return result
    }
    public static func validate(_ tasks: [OrbitTask]) throws -> [OrbitTask] {
        guard tasks.count <= 10000 else { throw OrbitError.invalid("最多支持 10,000 项任务。") }
        guard Set(tasks.map(\.id)).count == tasks.count else { throw OrbitError.invalid("备份中存在重复任务标识。") }
        return try tasks.map { try $0.validated() }
    }
    public static func validateStatuses(_ statuses: [TaskStatus], tasks: [OrbitTask]) throws {
        guard statuses.count <= 100, TaskStatus.allCases.allSatisfy(statuses.contains),
              Set(statuses).count == statuses.count else { throw OrbitError.invalid("状态列表无效或存在重复状态。") }
        let names = statuses.map { $0.title.precomposedStringWithCanonicalMapping.lowercased() }
        guard Set(names).count == names.count else { throw OrbitError.invalid("状态名称不能重复。") }
        guard tasks.allSatisfy({ statuses.contains($0.status) }) else { throw OrbitError.invalid("任务引用了未定义的状态。") }
    }
    public static func validateExtras(projects: [TaskProject], disabled: [TaskStatus], statuses: [TaskStatus],
                                      tasks: [OrbitTask], settings: [String: String]) throws {
        guard projects.count <= 10000, Set(projects.map(\.id)).count == projects.count,
              Set(projects.map { $0.name.lowercased() }).count == projects.count else {
            throw OrbitError.invalid("项目存在重复名称或标识。")
        }
        let projectIDs = Set(projects.map(\.id))
        guard tasks.allSatisfy({ $0.projectID.map(projectIDs.contains) ?? true }) else { throw OrbitError.invalid("任务引用了不存在的项目。") }
        guard Set(disabled).count == disabled.count, disabled.allSatisfy({ $0.isCustom && statuses.contains($0) }) else {
            throw OrbitError.invalid("停用状态列表无效。")
        }
        guard settings.count <= 256, settings.allSatisfy({ $0.key.utf8.count <= 100 && $0.value.utf8.count <= 8192 }) else {
            throw OrbitError.invalid("设置数据无效或过大。")
        }
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw OrbitError.tooLarge }
        return data
    }
}

