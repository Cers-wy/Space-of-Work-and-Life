import Foundation

public enum TaskScope: String, CaseIterable, Identifiable {
    case all, today, overdue, done, work, personal, life
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: "任务"; case .today: "今天"; case .overdue: "已逾期"; case .done: "已完成"
        case .work: "工作"; case .personal: "个人"; case .life: "生活"
        }
    }
    public var category: TaskCategory? { TaskCategory(rawValue: rawValue) }
    public var symbol: String {
        switch self {
        case .all: "square.grid.2x2"; case .today: "sun.max"; case .overdue: "clock"
        case .done: "checkmark.circle"; case .work: "briefcase"; case .personal: "star"; case .life: "house"
        }
    }
    public func contains(_ task: OrbitTask, today: String) -> Bool {
        switch self {
        case .all: true
        case .today: task.isToday(today)
        case .overdue: task.isOverdue(today: today)
        case .done: task.status == .done
        case .work, .personal, .life: task.category == category
        }
    }
}

public enum TaskSort: String, CaseIterable, Identifiable {
    case due, priority, created
    public var id: String { rawValue }
    public var title: String { switch self { case .due: "截止日期优先"; case .priority: "优先级由高到低"; case .created: "最近创建优先" } }
}

public struct TaskQuery {
    public var scope: TaskScope = .all
    public var text = ""
    public var status: TaskStatus?
    public var projectID: String?
    public var category: TaskCategory?
    public var priority: TaskPriority?
    public var dueFilter: String = "all"
    public var sort: TaskSort = .due
    public init() {}
    public var hasFilters: Bool { !text.isEmpty || projectID != nil || status != nil || category != nil || priority != nil || dueFilter != "all" }
    public func apply(to tasks: [OrbitTask], today: String = OrbitDate.day(), projectNames: [String: String] = [:]) -> [OrbitTask] {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks.filter { task in
            scope.contains(task, today: today)
            && (term.isEmpty || (task.title + " " + task.description + " " + (task.projectID.flatMap { projectNames[$0] } ?? "")).localizedStandardContains(term))
            && (status == nil || task.status == status)
            && (projectID == nil || task.projectID == projectID)
            && (category == nil || task.category == category)
            && (priority == nil || task.priority == priority)
            && (dueFilter == "all" || dueFilter == "none" && task.due.isEmpty
                || dueFilter == "today" && task.due == today
                || dueFilter == "overdue" && task.isOverdue(today: today))
        }.sorted { lhs, rhs in
            if sort == .created, lhs.createdAt != rhs.createdAt {
                return OrbitDate.parseTimestamp(lhs.createdAt)! > OrbitDate.parseTimestamp(rhs.createdAt)!
            }
            if sort == .priority, lhs.priority.rank != rhs.priority.rank { return lhs.priority.rank < rhs.priority.rank }
            let left = lhs.due.isEmpty ? "9999-12-31" : lhs.due
            let right = rhs.due.isEmpty ? "9999-12-31" : rhs.due
            if left != right { return left < right }
            let leftDate = OrbitDate.parseTimestamp(lhs.createdAt)!, rightDate = OrbitDate.parseTimestamp(rhs.createdAt)!
            if leftDate != rightDate { return leftDate > rightDate }
            return lhs.id < rhs.id
        }
    }
}
