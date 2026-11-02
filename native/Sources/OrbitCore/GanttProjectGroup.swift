import Foundation

public struct GanttProjectGroup: Identifiable {
    public let id: String
    public let name: String
    public let tasks: [OrbitTask]
    public static func make(tasks: [OrbitTask], projects: [TaskProject]) -> [GanttProjectGroup] {
        let grouped = Dictionary(grouping: tasks, by: { $0.projectID ?? "" })
        var result = projects.compactMap { project -> GanttProjectGroup? in
            guard let items = grouped[project.id], !items.isEmpty else { return nil }
            return GanttProjectGroup(id: project.id, name: project.name, tasks: items)
        }
        if let unassigned = grouped[""], !unassigned.isEmpty {
            result.append(GanttProjectGroup(id: "", name: "未分配项目", tasks: unassigned))
        }
        return result
    }
    public func schedule(today: Date) -> TaskSchedule? {
        let intervals = tasks.map { TaskSchedule(task: $0, today: today) }
        guard let start = intervals.map(\.start).min(), let end = intervals.map(\.end).max() else { return nil }
        return TaskSchedule(start: start, end: end)
    }
}
