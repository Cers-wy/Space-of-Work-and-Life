import SwiftUI
import OrbitCore

struct ColumnFramesKey: PreferenceKey {
    static let defaultValue: [TaskStatus: CGRect] = [:]
    static func reduce(value: inout [TaskStatus: CGRect], nextValue: () -> [TaskStatus: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct BoardColumn: View {
    let status: TaskStatus
    let tasks: [OrbitTask]
    @ObservedObject var drag: BoardDragState
    @EnvironmentObject private var store: AppStore
    private var palette: OrbitPalette { OrbitPalette(dark: store.dark) }
    @State private var statusDropTarget = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal").font(.system(size: 12)).foregroundStyle(palette.muted)
                    .frame(width: 24, height: 28).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("orbit-board"))
                        .onChanged { drag.update(point: $0.location, frames: store.columnFrames, viewport: store.boardViewport) }
                        .onEnded { value in
                            drag.reset()
                            if let target = store.columnFrames.first(where: { $0.value.contains(value.location) })?.key {
                                store.moveStatus(status, to: target)
                            }
                        })
                    .help("拖动此手柄，调整“\(status.title)”状态列的顺序")
                    .accessibilityLabel("拖动排序：\(status.title)")
                Circle().fill(palette.status(status)).frame(width: 7, height: 7)
                Text(status.title).orbitFont(14, weight: .semibold)
                if store.disabledStatuses.contains(status) { Text("已停用").orbitFont(12).foregroundStyle(palette.amber) }
                Text(tasks.count.formatted()).orbitFont(12).foregroundStyle(palette.muted)
                Spacer()
                OrbitIconButton(symbol: "plus", label: "在\(status.title)中新建任务", compact: true) { store.create(status: status) }.disabled(store.disabledStatuses.contains(status))
            }.padding(.horizontal, 12).padding(.vertical, 4)
                .background(palette.status(status).opacity(store.dark ? 0.07 : 0.05))
            Divider().overlay(palette.border)
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(tasks) { task in TaskCard(task: task, drag: drag) }
                    Button { store.create(status: status) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus"); Text("添加任务"); Spacer()
                        }.orbitFont(12).foregroundStyle(palette.muted).padding(12)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("添加\(status.title)任务").help("在“\(status.title)”列中新建任务").disabled(store.disabledStatuses.contains(status))
                    if tasks.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray").font(.system(size: 24, weight: .light))
                            Text("暂无\(status.title)任务").orbitFont(12)
                            Text("拖动任务到这里，或点击加号新建。").orbitFont(12)
                        }.foregroundStyle(palette.muted).frame(maxWidth: .infinity).padding(.top, 24)
                    }
                }.padding(8)
            }.scrollIndicators(.automatic)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glass(palette)
        .contentShape(Rectangle())
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ColumnFramesKey.self, value: [status: proxy.frame(in: .named("orbit-board"))])
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous).strokeBorder(
                statusDropTarget || drag.target == status ? palette.accent : .clear,
                lineWidth: 2)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let value = items.first, value.hasPrefix("space-status:"),
                  let source = TaskStatus(rawValue: String(value.dropFirst("space-status:".count))), store.statuses.contains(source) else { return false }
            store.moveStatus(source, to: status); return true
        } isTargeted: { statusDropTarget = $0 }
        .accessibilityElement(children: .contain).accessibilityLabel("\(status.title)，\(tasks.count) 项任务")
    }
}

struct TaskCard: View {
    let task: OrbitTask
    @ObservedObject var drag: BoardDragState
    @EnvironmentObject private var store: AppStore
    @State private var hover = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var palette: OrbitPalette { OrbitPalette(dark: store.dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CategoryBadge(category: task.category)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(palette.category(task.category).opacity(0.08), in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
                Spacer()
                Menu { TaskActionMenu(task: task) } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 20)
                        .foregroundStyle(palette.muted).contentShape(Rectangle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("任务操作")
            }
            if let project = store.projectName(task.projectID) {
                Label(project, systemImage: "folder").orbitFont(12).foregroundStyle(palette.purple).lineLimit(1).help("所属项目：\(project)")
            }
            Button { store.edit(task) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title).orbitFont(14, weight: .semibold).foregroundStyle(palette.text)
                        .lineLimit(3).multilineTextAlignment(.leading)
                    if !task.description.isEmpty {
                        Text(task.description).orbitFont(12).foregroundStyle(palette.secondary)
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                }.frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("编辑任务：\(task.title)").help("打开“\(task.title)”的详情，可修改项目、状态与日期")
            HStack(spacing: 8) {
                Label(task.priority.title, systemImage: "flag").foregroundStyle(palette.priority(task.priority))
                DueBadge(task: task)
                Spacer(minLength: 0)
                Button { store.setStatus(task.id, to: task.status == .done ? .todo : .done) } label: {
                    Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .ultraLight))
                        .foregroundStyle(task.status == .done ? palette.green : palette.muted.opacity(0.65))
                        .frame(width: 28, height: 28).contentShape(Circle())
                }.buttonStyle(.plain).help(task.status == .done ? "重新开启" : "完成任务")
                    .accessibilityLabel(task.status == .done ? "重新开启：\(task.title)" : "完成：\(task.title)")
            }.orbitFont(12)
        }
        .padding(16)
        .background {
            let shape = RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous)
            ZStack(alignment: .bottom) {
                if reduceTransparency { shape.fill(store.dark ? Color(hex: 0x1F1F1F) : .white) }
                else { shape.fill(.ultraThinMaterial).overlay { shape.fill(palette.card) } }
            }.clipShape(shape)
        }
        .overlay {
            CardFlowDecoration(palette: palette, emphasized: hover || task.status == .doing,
                               animating: hover && drag.task == nil && scenePhase == .active && !reduceMotion)
        }
        .shadow(color: .black.opacity(store.dark ? 0.16 : 0.025), radius: 4, y: 2)
        .onHover { hover = $0 }
        .contentShape(RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
        .opacity(drag.task?.id == task.id ? 0.45 : 1)
        .simultaneousGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("orbit-board"))
                .onChanged { value in
                    drag.update(task: task, point: value.location, frames: store.columnFrames, viewport: store.boardViewport)
                }
                .onEnded { value in store.finishDrag(task.id, at: value.location) }
        )
        .contextMenu { TaskActionMenu(task: task) }
    }

}

/// One clock for the hovered card; resting cards retain both highlights without frame callbacks.
private struct CardFlowDecoration: View {
    let palette: OrbitPalette
    let emphasized: Bool
    let animating: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animating)) { context in
            let time = animating ? context.date.timeIntervalSinceReferenceDate : 0
            ZStack(alignment: .bottom) {
                GeometryReader { geometry in
                    Capsule().fill(palette.accent.opacity(emphasized ? 0.6 : 0.35))
                        .frame(width: geometry.size.width * 0.6, height: 12).blur(radius: 12)
                        .offset(x: geometry.size.width * ((sin(time / 4.5) + 1) / 2 - 0.25), y: 6)
                }.frame(height: 16)
                ring(angle: animating ? time.truncatingRemainder(dividingBy: 12) * 30 : 220)
            }.clipShape(RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius))
        }.allowsHitTesting(false).accessibilityHidden(true)
    }

    private func ring(angle: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous)
        let glow = AngularGradient(stops: [
            .init(color: palette.accent.opacity(0.12), location: 0),
            .init(color: palette.accent.opacity(0.16), location: 0.48),
            .init(color: palette.accent.opacity(0.55), location: 0.68),
            .init(color: palette.dark ? Color(hex: 0xE6C5FF) : palette.accent, location: 0.8),
            .init(color: palette.accent.opacity(0.85), location: 0.85),
            .init(color: palette.accent.opacity(0.12), location: 1)
        ], center: .center, angle: .degrees(angle))
        return ZStack {
            shape.strokeBorder(palette.dark ? palette.accent.opacity(0.35) : palette.border, lineWidth: 1)
            shape.strokeBorder(glow, lineWidth: emphasized ? 3 : 2)
                .blur(radius: palette.dark ? 4 : 3).opacity(palette.dark ? 0.85 : 0.3)
            shape.strokeBorder(glow, lineWidth: emphasized ? 1.5 : 1)
        }
    }
}

struct DueBadge: View {
    let task: OrbitTask
    @EnvironmentObject private var store: AppStore
    private var palette: OrbitPalette { OrbitPalette(dark: store.dark) }
    private var label: String {
        guard !task.due.isEmpty else { return "未设置" }
        if task.due == store.today { return "今天截止" }
        let parts = task.due.split(separator: "-")
        return "\(Int(parts[1]) ?? 0)月\(Int(parts[2]) ?? 0)日"
    }
    var body: some View {
        Label(task.isOverdue(today: store.today) ? "已逾期 · \(label)" : label, systemImage: "calendar")
            .orbitFont(12).lineLimit(1)
            .foregroundStyle(task.isOverdue(today: store.today) ? palette.red : task.due == store.today ? palette.blue : palette.muted)
            .help(task.due.isEmpty ? "未设置截止日期" : task.due + "（Asia/Shanghai）")
    }
}

struct TaskActionMenu: View {
    let task: OrbitTask
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Button("编辑任务") { store.edit(task) }.help("打开任务详情并修改内容")
        Divider()
        ForEach(store.activeStatuses) { status in
            Button { store.setStatus(task.id, to: status) } label: {
                if task.status == status { Label(status.title, systemImage: "checkmark") }
                else { Text("移至\(status.title)") }
            }.disabled(task.status == status).help("将任务移至“\(status.title)”")
        }
        Divider()
        Button("删除任务", role: .destructive) { store.delete(task.id) }.help("确认后删除任务，可通过撤销恢复")
    }
}

struct TaskListView: View {
    let tasks: [OrbitTask]
    @EnvironmentObject private var store: AppStore
    private var palette: OrbitPalette { OrbitPalette(dark: store.dark) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("任务名称").frame(maxWidth: .infinity, alignment: .leading)
                Text("分类").frame(width: 72, alignment: .leading)
                Text("状态").frame(width: 96, alignment: .leading)
                Text("优先级").frame(width: 56, alignment: .leading)
                Text("截止日期").frame(width: 144, alignment: .leading)
                Color.clear.frame(width: 24, height: 1)
            }.orbitFont(12, weight: .semibold).foregroundStyle(palette.secondary)
                .padding(.leading, 60).padding(.trailing, 16).frame(height: 48).background(palette.hover)
            Divider().overlay(palette.border)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(tasks) { task in
                        HStack(spacing: 16) {
                            Button { store.setStatus(task.id, to: task.status == .done ? .todo : .done) } label: {
                                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundStyle(task.status == .done ? palette.green : palette.muted)
                                    .frame(width: 28, height: 32)
                            }.buttonStyle(.plain).accessibilityLabel(task.status == .done ? "重新开启：\(task.title)" : "完成：\(task.title)").help(task.status == .done ? "重新开启此任务" : "将任务标记为已完成")
                            Button { store.edit(task) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title).orbitFont(14, weight: .semibold).lineLimit(2)
                                    if let project = store.projectName(task.projectID) { Label(project, systemImage: "folder").orbitFont(12).foregroundStyle(palette.purple).lineLimit(1) }
                                    if !task.description.isEmpty {
                                        Text(task.description).orbitFont(12).foregroundStyle(palette.muted).lineLimit(1)
                                    }
                                }.frame(maxWidth: .infinity, minHeight: 40, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("编辑任务：\(task.title)").help("打开“\(task.title)”的详情，可修改项目、状态与日期")
                            CategoryBadge(category: task.category).frame(width: 72, alignment: .leading)
                            SpaceSelect(label: "修改任务状态", selection: Binding(
                                get: { task.status }, set: { store.setStatus(task.id, to: $0) }),
                                        options: store.statusOptions(including: task.status), width: 96)
                            Label(task.priority.title, systemImage: "flag").orbitFont(12)
                                .foregroundStyle(palette.priority(task.priority)).frame(width: 56, alignment: .leading)
                            DueBadge(task: task).frame(width: 144, alignment: .leading)
                            Menu { TaskActionMenu(task: task) } label: { Image(systemName: "ellipsis").frame(width: 24) }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24).help("任务操作")
                        }.padding(16).background(palette.card.opacity(0.45))
                            .contextMenu { TaskActionMenu(task: task) }
                        Divider().overlay(palette.border)
                    }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).glass(palette)
    }
}
