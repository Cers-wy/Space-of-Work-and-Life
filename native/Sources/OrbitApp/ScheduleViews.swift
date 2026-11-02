import SwiftUI
import OrbitCore

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case board, list, gantt, calendar
    var id: String { rawValue }
    var title: String {
        switch self { case .board: "看板"; case .list: "列表"; case .gantt: "甘特图"; case .calendar: "日历" }
    }
    var symbol: String {
        switch self { case .board: "rectangle.split.3x1"; case .list: "list.bullet"; case .gantt: "chart.bar.xaxis"; case .calendar: "calendar" }
    }
}
enum CalendarMode: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
    var title: String { switch self { case .day: "日"; case .week: "周"; case .month: "月" } }
}

struct SpaceViewSwitch: View {
    @Binding var selection: WorkspaceMode
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = OrbitPalette(dark: scheme == .dark)
        HStack(spacing: 2) {
            ForEach(WorkspaceMode.allCases) { mode in
                Button { selection = mode } label: {
                    Image(systemName: mode.symbol).font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(selection == mode ? palette.accent : palette.secondary)
                        .background(selection == mode ? palette.card : .clear,
                                    in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius))
                        .contentShape(RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius))
                }.buttonStyle(.plain).help(mode.title + "视图")
                    .accessibilityLabel(mode.title + "视图")
                    .accessibilityIdentifier("view-" + mode.rawValue)
                    .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }.padding(2)
            .background(palette.hover.opacity(0.65), in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius).strokeBorder(palette.border) }
    }
}

private enum ScheduleText {
    private static let formatters: [String: DateFormatter] = {
        Dictionary(uniqueKeysWithValues: ["MM/dd", "M/d", "EE", "yyyy年M月d日", "M月d日", "yyyy年M月", "M月d日 EEEE", "d", "EEEE"].map { pattern in
            let formatter = DateFormatter(); formatter.calendar = OrbitDate.calendar
            formatter.timeZone = OrbitDate.calendar.timeZone; formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = pattern; return (pattern, formatter)
        })
    }()
    static func date(_ date: Date, _ pattern: String) -> String { formatters[pattern]!.string(from: date) }
    static func deadline(_ schedule: TaskSchedule) -> String {
        (schedule.usesDefaultDeadline ? "默认截止 " : "截止 ") + date(schedule.end, "MM/dd")
    }
}
private struct ScheduledTask: Identifiable {
    let task: OrbitTask
    let schedule: TaskSchedule
    var id: String { task.id }
}

struct GanttView: View {
    let tasks: [OrbitTask]
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchor = OrbitDate.calendar.startOfDay(for: Date())
    private let dayCount = 14
    @State private var collapsed: Set<String> = []
    private let leftWidth: CGFloat = 400
    private var palette: OrbitPalette { OrbitPalette(dark: store.dark) }
    private var today: Date { OrbitDate.parseDay(store.today)! }
    private var days: [Date] { ScheduleCalendar.days(starting: anchor, count: dayCount) }
    private var groups: [GanttProjectGroup] { GanttProjectGroup.make(tasks: tasks, projects: store.projects) }

    var body: some View {
        let projectGroups = groups
        VStack(spacing: 0) {
            toolbar(projectGroups)
            Divider().overlay(palette.border)
            GeometryReader { geometry in
                let dates = days
                let dayWidth = max(48, (geometry.size.width - leftWidth) / CGFloat(dayCount))
                let timelineWidth = dayWidth * CGFloat(dayCount)
                ScrollView(.horizontal) {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section {
                                ForEach(projectGroups) { group in
                                    projectRow(group, dates: dates, dayWidth: dayWidth)
                                    if !collapsed.contains(group.id) {
                                        ForEach(group.tasks) { task in
                                            GanttTaskRow(task: task, today: today, dates: dates,
                                                         dayWidth: dayWidth, leftWidth: leftWidth, palette: palette)
                                                .transition(.opacity)
                                        }
                                    }
                                }
                                if tasks.isEmpty {
                                    Text(store.query.hasFilters ? "没有符合筛选条件的任务" : "暂无任务，点击加号开始安排")
                                        .orbitFont(14).foregroundStyle(palette.muted)
                                        .frame(width: leftWidth + timelineWidth, height: 160)
                                }
                                HStack {
                                    Button { store.create() } label: { Label("添加任务", systemImage: "plus") }
                                        .buttonStyle(.plain).foregroundStyle(palette.muted).orbitFont(12)
                                    Spacer()
                                }.padding(16).frame(width: leftWidth + timelineWidth)
                            } header: { timelineHeader(dates, dayWidth: dayWidth) }
                        }
                    }.frame(width: leftWidth + timelineWidth)
                }
            }
            Divider().overlay(palette.border)
            HStack(spacing: 16) {
                ScheduleLegend()
                Spacer(minLength: 8)
                Text("拖动排期条平移 · 拖动两端调整时长 · 虚线为默认排期")
                    .orbitFont(12).foregroundStyle(palette.muted)
            }.padding(12)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).glass(palette)
    }
    private func toolbar(_ groups: [GanttProjectGroup]) -> some View {
        HStack(spacing: 12) {
            Label("甘特图", systemImage: "chart.bar.xaxis").orbitFont(16, weight: .semibold)
            Text(ScheduleText.date(anchor, "yyyy年M月d日") + " 至 " + ScheduleText.date(days.last!, "M月d日"))
                .orbitFont(12).foregroundStyle(palette.secondary)
            Spacer(minLength: 8)
            OrbitIconButton(symbol: "list.bullet.indent", label: "展开全部项目", compact: true) {
                withAnimation(SpaceMotion.animation(reduceMotion)) { collapsed.removeAll() }
            }.disabled(collapsed.isEmpty)
            OrbitIconButton(symbol: "list.bullet", label: "收起全部项目", compact: true) {
                withAnimation(SpaceMotion.animation(reduceMotion)) { collapsed = Set(groups.map(\.id)) }
            }.disabled(groups.isEmpty || groups.allSatisfy { collapsed.contains($0.id) })
            SpaceDatePicker(selection: Binding(get: { OrbitDate.day(anchor) }, set: {
                if let date = OrbitDate.parseDay($0) { anchor = date }
            }), fieldName: "查看日期", allowsClear: false).frame(width: 176)

        }.padding(12)
    }
    private func move(_ count: Int) { anchor = OrbitDate.calendar.date(byAdding: .day, value: count, to: anchor)! }
    private func timelineHeader(_ dates: [Date], dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("项目 / 任务名称").frame(width: 184, alignment: .leading)
                Text("状态").frame(width: 64, alignment: .leading)
                Text("开始 / 截止日期").frame(width: 128, alignment: .leading)
            }.orbitFont(12).foregroundStyle(palette.secondary).padding(.horizontal, 12)
                .frame(width: leftWidth, height: 64)
            HStack(spacing: 0) {
                ForEach(dates, id: \.self) { day in
                    VStack(spacing: 4) {
                        Text(ScheduleText.date(day, "M/d")).orbitFont(12, weight: .semibold)
                        Text(day == today ? "今天" : ScheduleText.date(day, "EE"))
                            .orbitFont(12).foregroundStyle(day == today ? palette.accent : palette.muted)
                    }.frame(width: dayWidth, height: 64)
                        .background(day == today ? palette.hover : .clear)
                        .overlay { Rectangle().strokeBorder(palette.border.opacity(0.45), lineWidth: 0.5) }
                }
            }
        }.background { Rectangle().fill(.regularMaterial).overlay(palette.panel) }
            .overlay(alignment: .bottom) { Divider().overlay(palette.border) }
    }
    private func projectRow(_ group: GanttProjectGroup, dates: [Date], dayWidth: CGFloat) -> some View {
        let isCollapsed = collapsed.contains(group.id)
        return HStack(spacing: 0) {
            Button {
                withAnimation(SpaceMotion.animation(reduceMotion)) {
                    if isCollapsed { collapsed.remove(group.id) } else { collapsed.insert(group.id) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(isCollapsed ? 0 : 90)).frame(width: 16)
                    Image(systemName: "folder").foregroundStyle(palette.purple)
                    Text(group.name).lineLimit(1)
                    Text("\(group.tasks.count)").foregroundStyle(palette.muted).monospacedDigit()
                    Spacer(minLength: 0)
                }.orbitFont(14, weight: .semibold).padding(.horizontal, 12)
                    .frame(width: leftWidth, height: 48).contentShape(Rectangle())
            }.buttonStyle(.plain).help((isCollapsed ? "展开" : "收起") + group.name + "的任务")
                .accessibilityLabel((isCollapsed ? "展开项目：" : "收起项目：") + group.name + "，\(group.tasks.count)项任务")
            ZStack(alignment: .leading) {
                GanttGrid(dates: dates, today: today, dayWidth: dayWidth, palette: palette)
                if let schedule = group.schedule(today: today), let range = schedule.visibleOffsets(in: dates) {
                    RoundedRectangle(cornerRadius: 4).fill(palette.purple.opacity(0.45))
                        .frame(width: max(12, CGFloat(range.count) * dayWidth - 12), height: 8)
                        .offset(x: CGFloat(range.lowerBound) * dayWidth + 6)
                        .help(group.name + " · " + OrbitDate.day(schedule.start) + " 至 " + OrbitDate.day(schedule.end))
                }
            }.frame(width: CGFloat(dates.count) * dayWidth, height: 48)
        }.background(palette.hover.opacity(0.7))
            .overlay(alignment: .bottom) { Divider().overlay(palette.border) }
    }
}

/// A single canvas replaces the many nested grid/background/border views per day and row.
private struct GanttGrid: View {
    let dates: [Date]
    let today: Date
    let dayWidth: CGFloat
    let palette: OrbitPalette
    var body: some View {
        Canvas { context, size in
            for (index, day) in dates.enumerated() {
                let x = CGFloat(index) * dayWidth
                let rect = CGRect(x: x, y: 0, width: dayWidth, height: size.height)
                if day == today || OrbitDate.calendar.isDateInWeekend(day) {
                    context.fill(Path(rect), with: .color(palette.hover.opacity(day == today ? 1 : 0.28)))
                }
                var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(day == today ? palette.accent.opacity(0.65) : palette.border.opacity(0.45)), lineWidth: day == today ? 1 : 0.5)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct GanttDrag: Equatable {
    let adjustment: TaskSchedule.Adjustment
    let days: Int
}
private struct GanttTaskRow: View {
    let task: OrbitTask
    let today: Date
    let dates: [Date]
    let dayWidth: CGFloat
    let leftWidth: CGFloat
    let palette: OrbitPalette
    @EnvironmentObject private var store: AppStore
    @GestureState private var drag: GanttDrag?
    private var original: TaskSchedule { TaskSchedule(task: task, today: today) }
    private var schedule: TaskSchedule { drag.map { original.adjusting($0.adjustment, by: $0.days) } ?? original }
    var body: some View {
        let interval = schedule
        HStack(spacing: 0) {
            Button { store.edit(task) } label: {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title).orbitFont(14, weight: .semibold).lineLimit(1)
                        CategoryBadge(category: task.category)
                    }.padding(.leading, 24).frame(width: 184, alignment: .leading)
                    HStack(spacing: 4) {
                        Circle().fill(palette.status(task.status)).frame(width: 6, height: 6)
                        Text(task.status.title).lineLimit(1)
                    }.orbitFont(12).foregroundStyle(palette.secondary).frame(width: 64, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ScheduleText.date(interval.start, "MM/dd") + " → " + ScheduleText.date(interval.end, "MM/dd"))
                        Text(interval.usesDefaultDeadline ? "默认排期" : "\(OrbitDate.calendar.dateComponents([.day], from: interval.start, to: interval.end).day! + 1) 天")
                            .foregroundStyle(palette.muted)
                    }.orbitFont(12).monospacedDigit().frame(width: 128, alignment: .leading)
                }.padding(.horizontal, 12).frame(width: leftWidth, height: 64).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("编辑任务：" + task.title)
            ZStack(alignment: .leading) {
                GanttGrid(dates: dates, today: today, dayWidth: dayWidth, palette: palette)
                if let range = interval.visibleOffsets(in: dates) {
                    bar(interval, range: range)
                }
            }.frame(width: CGFloat(dates.count) * dayWidth, height: 64).clipped()
        }.background(drag == nil ? .clear : palette.hover)
            .overlay(alignment: .bottom) { Divider().overlay(palette.border.opacity(0.5)) }
    }
    private func bar(_ interval: TaskSchedule, range: ClosedRange<Int>) -> some View {
        let color = palette.status(task.status)
        return HStack(spacing: 0) {
            if interval.start >= dates.first! { handle(.start, label: "调整开始日期") }
            HStack(spacing: 4) {
                if task.status == .done { Image(systemName: "checkmark.circle.fill") }
                Text(task.title).lineLimit(1)
                Spacer(minLength: 0)
            }.orbitFont(12).foregroundStyle(palette.text).padding(.horizontal, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                .gesture(gesture(.move))
                .onTapGesture { store.edit(task) }
                .accessibilityLabel("平移排期：" + task.title + "，" + OrbitDate.day(interval.start) + " 至 " + OrbitDate.day(interval.end))
                .accessibilityAdjustableAction { direction in adjust(.move, direction: direction) }
            if interval.end <= dates.last! { handle(.end, label: "调整截止日期") }
        }.frame(width: max(12, CGFloat(range.count) * dayWidth - 12), height: 32)
            .background(color.opacity(interval.usesDefaultDeadline ? 0.13 : 0.35), in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius).strokeBorder(color.opacity(0.85),
                    style: StrokeStyle(lineWidth: drag == nil ? 1 : 2, dash: interval.usesDefaultDeadline ? [5, 3] : []))
                    .allowsHitTesting(false)
            }.offset(x: CGFloat(range.lowerBound) * dayWidth + 6)
            .help(task.title + " · " + OrbitDate.day(interval.start) + " 至 " + OrbitDate.day(interval.end) + "；拖动中间平移，两端调整时长")
    }
    private func handle(_ adjustment: TaskSchedule.Adjustment, label: String) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(palette.status(task.status).opacity(0.9))
            .frame(width: 3, height: 16).frame(width: 12, height: 32).contentShape(Rectangle())
            .gesture(gesture(adjustment))
            .accessibilityLabel(label + "：" + task.title)
            .accessibilityAdjustableAction { direction in adjust(adjustment, direction: direction) }
            .help(label + "，左右拖动按天调整")
    }
    private func gesture(_ adjustment: TaskSchedule.Adjustment) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($drag) { value, state, transaction in
                transaction.animation = nil
                state = GanttDrag(adjustment: adjustment, days: Int((value.translation.width / dayWidth).rounded()))
            }
            .onEnded { value in
                let days = Int((value.translation.width / dayWidth).rounded())
                guard days != 0 else { return }
                let changed = original.adjusting(adjustment, by: days)
                guard changed.start != original.start || changed.end != original.end else { return }
                store.updateSchedule(task, to: changed)
            }
    }
    private func adjust(_ adjustment: TaskSchedule.Adjustment, direction: AccessibilityAdjustmentDirection) {
        let days: Int
        switch direction { case .increment: days = 1; case .decrement: days = -1; @unknown default: return }
        let changed = original.adjusting(adjustment, by: days)
        guard changed.start != original.start || changed.end != original.end else { return }
        store.updateSchedule(task, to: changed)
    }
}

struct TaskCalendarView: View {
    let tasks: [OrbitTask]
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected = OrbitDate.calendar.startOfDay(for: Date())
    @State private var anchor = OrbitDate.calendar.startOfDay(for: Date())
    private var palette: OrbitPalette { OrbitPalette(dark: store.dark) }
    private var entries: [ScheduledTask] {
        let today = OrbitDate.parseDay(store.today)!
        return tasks.map { ScheduledTask(task: $0, schedule: TaskSchedule(task: $0, today: today)) }
    }
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(palette.border)
            Group {
                switch store.calendarMode {
                case .month: monthView
                case .week: weekView
                case .day: agenda(for: selected, entries: entries, wide: true)
                }
            }.id(store.calendarMode).transition(.opacity)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).glass(palette)
            .animation(SpaceMotion.animation(reduceMotion), value: store.calendarMode)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            SpaceDatePicker(selection: Binding(get: { OrbitDate.day(selected) }, set: {
                if let date = OrbitDate.parseDay($0) { selected = date; anchor = date }
            }), fieldName: "查看日期", allowsClear: false).frame(width: 176)
            Text(title).orbitFont(16, weight: .semibold).lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                ForEach(CalendarMode.allCases) { mode in
                    Button {
                        store.calendarMode = mode
                        anchor = selected
                    } label: {
                        Text(mode.title).orbitFont(14, weight: .semibold).frame(width: 40, height: 32)
                            .foregroundStyle(store.calendarMode == mode ? .white : palette.secondary)
                            .background(store.calendarMode == mode ? palette.primary : .clear,
                                        in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius))
                    }.buttonStyle(.plain).accessibilityLabel(mode.title + "视图")
                        .accessibilityIdentifier("calendar-" + mode.rawValue)
                        .accessibilityAddTraits(store.calendarMode == mode ? .isSelected : [])
                }
            }.padding(2).background(palette.hover, in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius))
        }.padding(12)
    }

    private var title: String {
        switch store.calendarMode {
        case .month: return ScheduleText.date(anchor, "yyyy年M月")
        case .day: return ScheduleText.date(selected, "M月d日 EEEE")
        case .week:
            let start = ScheduleCalendar.weekStart(anchor)
            let last = ScheduleCalendar.days(starting: start, count: 7).last!
            return ScheduleText.date(start, "M月d日") + " 至 " + ScheduleText.date(last, "M月d日")
        }
    }
    private func move(_ direction: Int) {
        let calendar = OrbitDate.calendar
        switch store.calendarMode {
        case .month: anchor = ScheduleCalendar.movingMonth(anchor, by: direction); selected = anchor
        case .week: anchor = calendar.date(byAdding: .day, value: direction * 7, to: anchor)!; selected = anchor
        case .day: selected = calendar.date(byAdding: .day, value: direction, to: selected)!; anchor = selected
        }
    }

    private var monthView: some View {
        GeometryReader { geometry in
            let dates = ScheduleCalendar.monthDays(anchor)
            let schedules = entries
            let sidebar: CGFloat = geometry.size.width >= 1100 ? 280 : 232
            let rowHeight = max(88, (geometry.size.height - 32) / CGFloat(dates.count / 7))
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(["周一", "周二", "周三", "周四", "周五", "周六", "周日"], id: \.self) { day in
                            Text(day).orbitFont(12).foregroundStyle(palette.muted).frame(maxWidth: .infinity).frame(height: 32)
                        }
                    }
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                            ForEach(dates, id: \.self) { day in
                                monthCell(day, schedules: schedules, height: rowHeight)
                            }
                        }
                    }
                }
                Divider().overlay(palette.border)
                agenda(for: selected, entries: schedules, wide: false).frame(width: sidebar)
            }
        }
    }

    private func monthCell(_ day: Date, schedules: [ScheduledTask], height: CGFloat) -> some View {
        let items = schedules.filter { $0.schedule.contains(day) }
        let isSelected = OrbitDate.calendar.isDate(day, inSameDayAs: selected)
        let inMonth = OrbitDate.calendar.isDate(day, equalTo: anchor, toGranularity: .month)
        let limit = max(1, min(3, Int((height - 60) / 24)))
        return VStack(alignment: .leading, spacing: 4) {
            Text(ScheduleText.date(day, "d")).orbitFont(12, weight: .semibold)
                .foregroundStyle(OrbitDate.day(day) == store.today ? .white : inMonth ? palette.text : palette.muted)
                .frame(width: 24, height: 24)
                .background(OrbitDate.day(day) == store.today ? palette.primary : .clear, in: Circle())
            ForEach(Array(items.prefix(limit))) { entry in
                Button { selected = day; store.edit(entry.task) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: entry.task.status == .done ? "checkmark.circle.fill" : "circle.fill")
                            .font(.system(size: 7)).foregroundStyle(palette.status(entry.task.status))
                        Text(entry.task.title).orbitFont(12).lineLimit(1)
                    }.padding(.horizontal, 4).frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                        .background(palette.status(entry.task.status).opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 4))
                }.buttonStyle(.plain).help(entry.task.title + " · " + ScheduleText.deadline(entry.schedule))
                    .accessibilityLabel("编辑任务：" + entry.task.title)
            }
            if items.count > limit {
                Button("还有 \(items.count - limit) 项") { selected = day }
                    .buttonStyle(.plain).orbitFont(12).foregroundStyle(palette.muted)
            }
            Spacer(minLength: 0)
        }.padding(8).frame(maxWidth: .infinity).frame(height: height, alignment: .topLeading).clipped()
            .background(isSelected ? palette.hover : .clear)
            .overlay { Rectangle().strokeBorder(isSelected ? palette.accent : palette.border.opacity(0.55), lineWidth: isSelected ? 1.5 : 0.5) }
            .contentShape(Rectangle()).onTapGesture { selected = day }
            .accessibilityElement(children: .contain).accessibilityLabel(ScheduleText.date(day, "M月d日") + "，\(items.count)项事项")
    }

    private var weekView: some View {
        GeometryReader { geometry in
            let dates = ScheduleCalendar.days(starting: ScheduleCalendar.weekStart(anchor), count: 7)
            let schedules = entries
            let columnWidth = max(148, geometry.size.width / 7)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(dates, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 0) {
                            Button { selected = day } label: {
                                VStack(spacing: 4) {
                                    Text(ScheduleText.date(day, "d")).orbitFont(16, weight: .semibold)
                                    Text(OrbitDate.day(day) == store.today ? "今天" : ScheduleText.date(day, "EEEE")).orbitFont(12)
                                }.frame(maxWidth: .infinity).frame(height: 64)
                                    .foregroundStyle(OrbitDate.day(day) == store.today ? palette.accent : palette.secondary)
                            }.buttonStyle(.plain)
                            Divider().overlay(palette.border)
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    let items = schedules.filter { $0.schedule.contains(day) }
                                    ForEach(items) { entry in ScheduleTaskRow(task: entry.task, schedule: entry.schedule, compact: true) }
                                    if items.isEmpty {
                                        Text("暂无事项").orbitFont(12).foregroundStyle(palette.muted).padding(.top, 24)
                                    }
                                    Button { store.create(due: OrbitDate.day(day)) } label: {
                                        Label("添加事项", systemImage: "plus").orbitFont(12).frame(maxWidth: .infinity, alignment: .leading)
                                    }.buttonStyle(.plain).foregroundStyle(palette.muted).padding(8)
                                }.padding(8)
                            }
                        }.frame(width: columnWidth, height: geometry.size.height)
                            .background(OrbitDate.calendar.isDate(day, inSameDayAs: selected) ? palette.hover.opacity(0.45) : .clear)
                            .overlay { Rectangle().strokeBorder(palette.border.opacity(0.45), lineWidth: 0.5) }
                    }
                }
            }
        }
    }

    private func agenda(for day: Date, entries: [ScheduledTask], wide: Bool) -> some View {
        let items = entries.filter { $0.schedule.contains(day) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(ScheduleText.date(day, "M月d日 EEEE")).orbitFont(16, weight: .semibold)
                Spacer(minLength: 0)
            }
            Text("\(items.count) 个事项 · 按排期展示").orbitFont(12).foregroundStyle(palette.muted)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(items) { entry in ScheduleTaskRow(task: entry.task, schedule: entry.schedule, compact: !wide) }
                    if items.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar").font(.system(size: 24, weight: .light))
                            Text("当天暂无事项").orbitFont(14)
                            Text("可添加事项，或选择其他日期。").orbitFont(12)
                        }.foregroundStyle(palette.muted).frame(maxWidth: .infinity).padding(.vertical, 32)
                    }
                    Button { store.create(due: OrbitDate.day(day)) } label: {
                        Label("添加事项", systemImage: "plus").orbitFont(12).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }.buttonStyle(.plain).foregroundStyle(palette.muted).help("新建事项，截止日期为选中日期")
                }
            }
            ScheduleLegend()
        }.padding(wide ? 24 : 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ScheduleTaskRow: View {
    let task: OrbitTask
    let schedule: TaskSchedule
    var compact = false
    @EnvironmentObject private var store: AppStore
    private var palette: OrbitPalette { OrbitPalette(dark: store.dark) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Button { store.setStatus(task.id, to: task.status == .done ? .todo : .done) } label: {
                    Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16)).foregroundStyle(task.status == .done ? palette.green : palette.muted)
                }.buttonStyle(.plain).help(task.status == .done ? "重新开启任务" : "完成任务")
                    .accessibilityLabel((task.status == .done ? "重新开启：" : "完成：") + task.title)
                Button { store.edit(task) } label: {
                    Text(task.title).orbitFont(14, weight: .semibold).lineLimit(compact ? 2 : 3)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("编辑任务：" + task.title)
                if !compact {
                    Menu { TaskActionMenu(task: task) } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
            }
            HStack(spacing: 8) {
                CategoryBadge(category: task.category)
                Text(task.status.title).orbitFont(12).foregroundStyle(palette.status(task.status))
            }
            Text(ScheduleText.deadline(schedule)).orbitFont(12).foregroundStyle(palette.muted)
            if let project = store.projectName(task.projectID) {
                Label(project, systemImage: "folder").orbitFont(12).foregroundStyle(palette.purple).lineLimit(1)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).glass(palette)
    }
}

private struct ScheduleLegend: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = OrbitPalette(dark: scheme == .dark)
        HStack(spacing: 12) {
            ForEach(TaskStatus.allCases) { status in
                HStack(spacing: 4) {
                    Circle().fill(palette.status(status)).frame(width: 7, height: 7)
                    Text(status.title).orbitFont(12).foregroundStyle(palette.muted)
                }
            }
        }
    }
}
