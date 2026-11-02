import Foundation

public enum SampleTasks {
    public static func make(now: Date = Date()) -> [OrbitTask] {
        let rows: [(String, String, TaskCategory, TaskStatus, TaskPriority, Int)] = [
            ("梳理个人工作台 V1 功能范围", "明确第一版任务管理边界，整理看板与列表的关键交互。", .work, .doing, .high, 0),
            ("准备周五的产品方案评审", "补充核心业务流程，确认待讨论事项和演示顺序。", .work, .todo, .high, 1),
            ("完成本月项目进度整理", "汇总已完成事项与待推进问题，更新项目计划。", .work, .todo, .medium, 0),
            ("阅读《设计心理学》第二章", "从日常物品中发现设计线索，记录三个有启发的案例。", .personal, .doing, .medium, 2),
            ("规划周末城市漫步路线", "选一家想去的咖啡馆，留半天时间探索新的街区。", .life, .todo, .low, 3),
            ("整理桌面与资料文件夹", "归档历史文档，给正在进行的项目留出清晰空间。", .personal, .todo, .low, -1),
            ("本周运动计划 · 第二次训练", "45 分钟力量训练，结束后拉伸。", .life, .doing, .medium, 0),
            ("完成新版本原型走查", "检查关键页面和表单状态，整理交互优化建议。", .work, .done, .high, -1),
            ("建立个人阅读清单", "整理接下来想读的书，为持续学习留一块空间。", .personal, .done, .low, -2),
            ("预约年度健康体检", "确认体检时间和注意事项，已添加到个人日程。", .life, .done, .medium, -2)
        ]
        return rows.enumerated().map { index, row in
            OrbitTask(title: row.0, description: row.1, category: row.2, status: row.3,
                      priority: row.4, due: OrbitDate.offsetDay(row.5, now: now),
                      now: now.addingTimeInterval(Double(index - 10) * 3600))
        }
    }
}
