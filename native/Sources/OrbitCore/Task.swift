import Foundation

public enum TaskCategory: String, Codable, CaseIterable, Identifiable {
    case work, personal, life
    public var id: String { rawValue }
    public var title: String { switch self { case .work: "工作"; case .personal: "个人"; case .life: "生活" } }
    public var symbol: String { switch self { case .work: "briefcase"; case .personal: "star"; case .life: "house" } }
}

public struct TaskStatus: RawRepresentable, Codable, CaseIterable, Identifiable, Hashable {
    public let rawValue: String
    public var id: String { rawValue }
    public static let todo = TaskStatus(rawValue: "todo")!
    public static let doing = TaskStatus(rawValue: "doing")!
    public static let done = TaskStatus(rawValue: "done")!
    public static let allCases: [TaskStatus] = [.todo, .doing, .done]
    public var isCustom: Bool { rawValue.hasPrefix("custom:") }
    public var title: String {
        switch rawValue {
        case "todo": "待办"; case "doing": "进行中"; case "done": "已完成"
        default: String(rawValue.dropFirst(7))
        }
    }
    public init?(rawValue: String) {
        if !["todo", "doing", "done"].contains(rawValue) {
            guard rawValue.hasPrefix("custom:") else { return nil }
            let name = String(rawValue.dropFirst(7))
            guard !name.isEmpty, name.utf16.count <= 20,
                  name == name.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  !["待办", "进行中", "已完成"].contains(name) else { return nil }
        }
        self.rawValue = rawValue
    }
    public static func custom(title: String) throws -> TaskStatus {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard let status = TaskStatus(rawValue: "custom:" + name) else {
            throw OrbitError.invalid("请输入1至20字的状态名称，且不能与已有状态重复。")
        }
        return status
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let status = TaskStatus(rawValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "任务状态无效")
        }
        self = status
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer(); try container.encode(rawValue)
    }
}

public enum TaskPriority: String, Codable, CaseIterable, Identifiable {
    case high, medium, low
    public var id: String { rawValue }
    public var title: String { switch self { case .high: "高"; case .medium: "中"; case .low: "低" } }
    public var rank: Int { switch self { case .high: 0; case .medium: 1; case .low: 2 } }
}

public struct OrbitTask: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var description: String
    /// Flat RTFD preserves formatting and images; description remains searchable plain text.
    public var richDescription: Data?
    public var category: TaskCategory
    public var status: TaskStatus
    public var priority: TaskPriority
    /// Date-only value; compatible with the confirmed HTML prototype backup.
    public var due: String
    /// Optional explicit scheduling start, independent of creation time.
    public var startDate: String?
    public var createdAt: String
    public var updatedAt: String
    public var completedAt: String?
    public var projectID: String?
    public var attachments: [TaskAttachment]

    enum CodingKeys: String, CodingKey {
        case id, title, description, richDescription, category, status, priority, due, startDate, createdAt, updatedAt, completedAt, projectID, attachments
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id); try container.encode(title, forKey: .title)
        try container.encodeIfPresent(richDescription, forKey: .richDescription)
        try container.encode(description, forKey: .description); try container.encode(category, forKey: .category)
        try container.encode(status, forKey: .status); try container.encode(priority, forKey: .priority)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encode(due, forKey: .due); try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        if !attachments.isEmpty { try container.encode(attachments, forKey: .attachments) }
        // The HTML prototype requires an explicit null for unfinished tasks.
        if let completedAt { try container.encode(completedAt, forKey: .completedAt) }
        else { try container.encodeNil(forKey: .completedAt) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        richDescription = try container.decodeIfPresent(Data.self, forKey: .richDescription)
        category = try container.decode(TaskCategory.self, forKey: .category)
        status = try container.decode(TaskStatus.self, forKey: .status)
        priority = try container.decode(TaskPriority.self, forKey: .priority)
        due = try container.decode(String.self, forKey: .due)
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
        attachments = try container.decodeIfPresent([TaskAttachment].self, forKey: .attachments) ?? []
    }

    public init(id: String = UUID().uuidString, title: String = "", description: String = "",
                category: TaskCategory = .work, status: TaskStatus = .todo,
                priority: TaskPriority = .medium, due: String = "", startDate: String? = nil, projectID: String? = nil, attachments: [TaskAttachment] = [], now: Date = Date()) {
        self.id = id; self.title = title; self.description = description; self.richDescription = nil
        self.category = category; self.status = status; self.priority = priority; self.due = due; self.projectID = projectID
        self.startDate = startDate
        self.attachments = attachments
        createdAt = OrbitDate.timestamp(now); updatedAt = createdAt
        completedAt = status == .done ? createdAt : nil
    }

    public func validated() throws -> OrbitTask {
        var task = self
        task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.utf16.count < 200 else { throw OrbitError.invalid("任务标识无效。") }
        guard !task.title.isEmpty else { throw OrbitError.invalid("请输入任务标题。") }
        guard title.utf16.count <= 100 else { throw OrbitError.invalid("任务标题最多 100 字。") }
        guard description.utf16.count <= 5000 else { throw OrbitError.invalid("任务说明最多 5,000 字。") }
        guard due.isEmpty || OrbitDate.parseDay(due) != nil else { throw OrbitError.invalid("截止日期无效。") }
        if let startDate {
            guard OrbitDate.parseDay(startDate) != nil else { throw OrbitError.invalid("开始日期无效。") }
            guard due.isEmpty || startDate <= due else { throw OrbitError.invalid("开始日期不能晚于截止日期。") }
        }
        guard OrbitDate.parseTimestamp(createdAt) != nil, OrbitDate.parseTimestamp(updatedAt) != nil,
              completedAt == nil || OrbitDate.parseTimestamp(completedAt!) != nil else {
            throw OrbitError.invalid("任务时间格式无效。")
        }
        guard (status == .done) == (completedAt != nil) else {
            throw OrbitError.invalid("完成状态与完成时间不一致。")
        }
        guard (richDescription?.count ?? 0) <= 24 * 1024 * 1024 else { throw OrbitError.tooLarge }
        try TaskAttachment.validate(attachments)
        return task
    }

    public func changingStatus(to status: TaskStatus, now: Date = Date()) -> OrbitTask {
        guard self.status != status else { return self }
        var result = self
        result.status = status; result.updatedAt = OrbitDate.timestamp(now)
        result.completedAt = status == .done ? result.updatedAt : nil
        return result
    }

    public func isOverdue(today: String) -> Bool { status != .done && !due.isEmpty && due < today }
    public func isToday(_ today: String) -> Bool { status != .done && due == today }
}

public enum OrbitDate {
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return formatter
    }()
    private static let fractionalTimestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter
    }()
    private static let plainTimestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]; return formatter
    }()
    public static func day(_ date: Date = Date()) -> String { dayFormatter.string(from: date) }
    public static func parseDay(_ value: String) -> Date? {
        guard value.utf8.count == 10, value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let date = dayFormatter.date(from: value), day(date) == value else { return nil }
        return date
    }
    public static func timestamp(_ date: Date) -> String { fractionalTimestamp.string(from: date) }
    public static func parseTimestamp(_ value: String) -> Date? {
        fractionalTimestamp.date(from: value) ?? plainTimestamp.date(from: value)
    }
    public static func offsetDay(_ offset: Int, now: Date = Date()) -> String {
        day(calendar.date(byAdding: .day, value: offset, to: now)!)
    }
}

public enum OrbitError: LocalizedError {
    case invalid(String), conflict, tooLarge, unsupportedVersion
    public var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        case .conflict: "本地数据已被其他进程修改。请重新载入后再操作；当前输入仍保留。"
        case .tooLarge: "文件超过支持的大小，请选择较小的文件或减少附件。"
        case .unsupportedVersion: "备份版本不受支持，请选择Space或ORBIT任务备份。"
        }
    }
}

public struct TaskProject: Codable, Equatable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public init(id: String = UUID().uuidString, name: String) { self.id = id; self.name = name }
    public func validated() throws -> TaskProject {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !id.isEmpty, id.utf16.count < 200, !clean.isEmpty, clean.utf16.count <= 60,
              !clean.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw OrbitError.invalid("项目名称须为1至60字，不能包含换行。")
        }
        return TaskProject(id: id, name: clean)
    }
}
