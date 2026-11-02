import SwiftUI
import AppKit
import OrbitCore

struct WorkspaceView: View {
    @EnvironmentObject private var store: AppStore
    @State private var filterPopover = false
    @State private var workspaceWidth: CGFloat = 1380
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    private var palette: OrbitPalette { OrbitPalette(dark: store.dark) }
    private var visible: [OrbitTask] { store.visibleTasks }

    var body: some View {
        GeometryReader { geometry in
        HStack(alignment: .top, spacing: 8) {
            SidebarView(expandedWidth: workspaceWidth >= 1600 ? 240 : 224).zIndex(1)
            VStack(spacing: 8) {
                overview
                if let error = store.errorMessage { errorBanner(error) }
                if !store.loaded {
                    ContentUnavailableView {
                        Label("无法读取本地任务", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("原文件保持不变。请重试读取，或在数据与设置中导入有效备份。")
                    } actions: {
                        Button("重新载入") { store.reload() }.help("从本地SQLite数据库重新读取任务")
                        Button("数据与设置") { store.showSettings = true }.help("打开备份、同步和外观设置")
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).glass(palette)
                } else {
                    Group {
                    switch store.viewMode {
                    case .board: board
                    case .list:
                        if visible.isEmpty { emptyView } else { TaskListView(tasks: visible) }
                    case .gantt: GanttView(tasks: visible)
                    case .calendar: TaskCalendarView(tasks: visible)
                    }
                    }.id(store.viewMode)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
                        .animation(SpaceMotion.animation(reduceMotion), value: store.viewMode)
                }

            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8).background { AmbientBackground(dark: store.dark) }
        .animation(SpaceMotion.animation(reduceMotion), value: store.viewMode)
        .animation(reduceMotion ? nil : SpaceMotion.animation(false), value: store.navCollapsed)
        .animation(reduceMotion ? nil : SpaceMotion.animation(false), value: store.overviewCollapsed)
        .foregroundStyle(palette.text).orbitFont()
        .tint(palette.accent)
        .overlay(alignment: .bottom) {
            if let notice = store.notice {
                HStack(spacing: 12) {
                    Text(notice).orbitFont(12)
                    if store.canUndo { Button("撤销") { store.undo() }.help("撤销最近一次任务或状态变更").buttonStyle(.plain).foregroundStyle(palette.accent) }
                }.padding(12).glass(palette).fixedSize().padding(.bottom, 16)
            }
        }
        .sheet(item: $store.editor, onDismiss: { store.hasUnsavedEdits = false }) { task in
            TaskEditorView(task: task).environmentObject(store)
                .preferredColorScheme(store.dark ? .dark : .light)
        }
        .sheet(isPresented: $store.showStatusEditor) {
            StatusEditorView().environmentObject(store).preferredColorScheme(store.dark ? .dark : .light)
        }
        .sheet(isPresented: $store.showSettings) {
            SettingsView().environmentObject(store).preferredColorScheme(store.dark ? .dark : .light)
        }
        .sheet(isPresented: $store.showHelp) {
            HelpView().environmentObject(store).preferredColorScheme(store.dark ? .dark : .light)
        }
        .onChange(of: store.searchRequested) { _, _ in
            if store.overviewCollapsed { filterPopover = true }
            else { searchFocused = true }
        }
        .onChange(of: store.overviewCollapsed) { _, _ in filterPopover = false }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in store.refreshDay() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refreshDay() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in store.boardDrag.reset() }
        .onAppear { workspaceWidth = geometry.size.width }
        .onChange(of: geometry.size.width) { _, width in workspaceWidth = width }
        }
    }

    private var board: some View {
        GeometryReader { geometry in
            let count = CGFloat(store.displayStatuses.count)
            let columnWidth = max(280, (geometry.size.width - 12 * (count - 1)) / count)
            let overflow = columnWidth * count + 12 * (count - 1) > geometry.size.width + 1
            let height = max(0, geometry.size.height - (overflow ? 16 : 0))
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(store.displayStatuses) { status in
                        BoardColumn(status: status, tasks: store.tasksByStatus[status] ?? [], drag: store.boardDrag)
                            .frame(width: columnWidth, height: height)
                    }
                }
            }.scrollIndicators(.automatic)
                .coordinateSpace(name: "orbit-board")
                .onDisappear { store.boardDrag.reset() }
                .onPreferenceChange(ColumnFramesKey.self) { if store.columnFrames != $0 { store.columnFrames = $0 } }
                .onAppear { store.boardViewport = CGRect(origin: .zero, size: geometry.size) }
                .onChange(of: geometry.size) { _, size in store.boardViewport = CGRect(origin: .zero, size: size) }
                .overlay(alignment: .topLeading) {
                    BoardDragPreview(drag: store.boardDrag, palette: palette)
                }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: store.overviewCollapsed ? 0 : 24) {
            HStack(spacing: 16) {
                breadcrumb
                Spacer(minLength: 8)
                if store.overviewCollapsed { compactActions }
                topActions
            }.frame(minHeight: 32)
            if !store.overviewCollapsed {
                if workspaceWidth <= 1180 {
                    HStack { heading; Spacer(); newTaskButton }
                    statistics
                } else {
                    GeometryReader { geometry in
                        HStack(spacing: 24) {
                            heading.frame(maxWidth: .infinity, alignment: .leading)
                            statistics.frame(width: max(320, (geometry.size.width - 64) * 0.60))
                            newTaskButton
                        }
                    }.frame(height: 64)
                }
                taskControls
            }
        }.padding(16)
            .padding(.leading, store.navCollapsed ? 16 : 0)
            .navigationGlass(palette, shape: SpaceOverviewShape(notched: store.navCollapsed))
    }

    private var newTaskButton: some View {
        OrbitIconButton(symbol: "plus", label: "新建任务（⌘N / N）", primary: true, compact: true) { store.create() }
            .disabled(!store.loaded)
    }

    private var heading: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.3x1").font(.system(size: 18))
                .foregroundStyle(palette.accent).frame(width: 32, height: 32)
                .background(palette.hover, in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("任务").orbitFont(24, weight: .semibold)
                Text("安排好每一步，留一点空间给生活。").orbitFont(12).foregroundStyle(palette.muted)
            }
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 12) {
            Text("我的空间").foregroundStyle(palette.muted)
            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(palette.muted)
            Text(store.overviewCollapsed ? "\(store.query.scope.title) · \(visible.count) 个任务" : "任务管理").lineLimit(1)
            ViewThatFits(in: .horizontal) { categoryCounts; Color.clear.frame(width: 0, height: 0) }
        }.orbitFont(12)
    }

    private var compactActions: some View {
        HStack(spacing: 8) {
            Button { filterPopover.toggle() } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 14)).frame(width: SpaceStyle.toolbarHeight, height: SpaceStyle.toolbarHeight)
                    .background(palette.hover, in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
            }.buttonStyle(.plain).help("筛选与排序：搜索任务并按状态、项目、优先级等筛选（/）").accessibilityLabel("筛选与排序")
                .popover(isPresented: $filterPopover, arrowEdge: .bottom) {
                    FilterPopover().environmentObject(store).padding(16).frame(width: 384)
                }
            viewSwitch
            OrbitIconButton(symbol: "plus", label: "新建任务（⌘N / N）", primary: true, compact: true) { store.create() }.disabled(!store.loaded)
        }.fixedSize()
    }

    private var topActions: some View {
        HStack(spacing: 8) {
            SpaceThemeToggle(dark: $store.dark)
            OrbitIconButton(symbol: "rectangle.badge.plus", label: "任务状态管理：新增、停用或删除任务状态", compact: true) { store.showStatusEditor = true }
                .disabled(!store.loaded)
            if store.canUndo {
                OrbitIconButton(symbol: "arrow.uturn.backward", label: "撤销最近一次更改（⌘Z）", compact: true) { store.undo() }
            }
            OrbitIconButton(symbol: "questionmark.circle", label: "使用帮助", compact: true) { store.showHelp = true }
            OrbitIconButton(symbol: "chevron.up",
                            label: store.overviewCollapsed ? "展开概览" : "收起概览", compact: true) { store.overviewCollapsed.toggle() }
                .rotationEffect(.degrees(store.overviewCollapsed ? 180 : 0))
        }.fixedSize()
    }

    private var statistics: some View {
        HStack(spacing: 8) {
            stat("全部任务", value: store.tasks.count, color: palette.blue)
            stat("进行中", value: store.tasks.filter { $0.status == .doing }.count, color: palette.purple)
            stat("已逾期", value: store.count(.overdue), color: palette.amber)
            stat("已完成", value: store.count(.done), color: palette.green)
        }
    }
    private func stat(_ label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).orbitFont(12).foregroundStyle(palette.secondary)
            Text(String(format: "%02d", value)).orbitFont(24, weight: .semibold).foregroundStyle(color).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(height: 64)
            .background(color.opacity(store.dark ? 0.12 : 0.08), in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous).strokeBorder(palette.border) }
    }

    private var taskControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(store.query.scope.title).orbitFont(14, weight: .semibold)
                Text("\(visible.count) 个任务").orbitFont(12).foregroundStyle(palette.muted)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(palette.hover, in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
                Spacer()
                viewSwitch
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { searchField; filterControls }
                VStack(spacing: 12) { searchField; filterControls }
            }
        }.padding(16).glass(palette)
    }
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(palette.muted)
            TextField("搜索任务标题与说明", text: $store.query.text).textFieldStyle(.plain)
                .focused($searchFocused).accessibilityLabel("搜索任务")
            if !store.query.text.isEmpty {
                OrbitIconButton(symbol: "xmark", label: "清除搜索") { store.query.text = "" }
            }
        }.orbitFont(12).padding(.horizontal, 12).frame(minWidth: 160, minHeight: 40)
            .background(palette.card.opacity(0.7), in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous).strokeBorder(searchFocused ? palette.accent : palette.border, lineWidth: searchFocused ? 2 : 1) }
    }
    private var filterControls: some View {
        HStack(spacing: 8) {
            SpaceSelect(label: "状态筛选", selection: $store.query.status, options: store.statusFilters, width: 120, active: store.query.status != nil)
            SpaceSelect(label: "优先级筛选", selection: $store.query.priority, options: TaskChoices.priorities, width: 136, active: store.query.priority != nil)
            Button { filterPopover.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Image(systemName: "chevron.down").font(.system(size: 9))
                }.foregroundStyle(store.query.category != nil || store.query.dueFilter != "all" ? palette.accent : palette.secondary)
                    .frame(width: 40, height: 40).background(palette.hover, in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
            }.buttonStyle(.plain).help("分类与日期筛选").accessibilityLabel("分类与日期筛选")
                .popover(isPresented: $filterPopover, arrowEdge: .bottom) {
                    FilterPopover().environmentObject(store).padding(16).frame(width: 384)
                }
            SpaceSelect(label: "任务排序", selection: $store.query.sort, options: TaskChoices.sorts, width: 160)
            if store.query.hasFilters { Button("清除") { store.clearFilters() }.help("清空当前筛选条件").buttonStyle(.plain).orbitFont(12).foregroundStyle(palette.accent) }
        }.fixedSize()
    }
    private var categoryCounts: some View {
        HStack(spacing: 8) {
            ForEach(TaskCategory.allCases) { category in
                Button {
                    store.query.category = store.query.category == category ? nil : category
                } label: {
                    CategoryBadge(category: category, count: store.tasks.filter { $0.category == category }.count)
                        .padding(4)
                        .background(store.query.category == category ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(store.query.category == category ? palette.accent : .clear) }
                }.buttonStyle(.plain).help("筛选" + category.title + "任务，再次点击取消")
                    .accessibilityLabel("快速筛选" + category.title)
                    .accessibilityAddTraits(store.query.category == category ? .isSelected : [])
            }
        }.fixedSize()
    }
    private var viewSwitch: some View {
        SpaceViewSwitch(selection: $store.viewMode)
    }
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: store.tasks.isEmpty ? "square.stack.3d.up" : "magnifyingglass")
                .font(.system(size: 36, weight: .light)).foregroundStyle(palette.accent)
            Text(store.tasks.isEmpty ? "让第一个行动，进入轨道。" : "没有符合条件的任务")
                .orbitFont(20, weight: .semibold)
            Text(store.tasks.isEmpty ? "从一项工作、一个想法，或一件生活小事开始。" : "调整筛选条件，或点击顶部分类。")
                .orbitFont(14).foregroundStyle(palette.secondary)
            HStack(spacing: 12) {
                if store.tasks.isEmpty {
                    Button("创建第一个任务") { store.create() }.help("打开表单，创建一项任务").buttonStyle(SpaceButtonStyle(primary: true))
                    Button("导入已有备份") { store.importBackup() }.help("导入SQLite或旧JSON任务备份")
                } else {
                    Button("显示所有任务") { store.query = TaskQuery() }.help("清空筛选并返回全部任务")
                    Button("新建任务") { store.create() }.help("打开任务表单").buttonStyle(SpaceButtonStyle(primary: true))
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).glass(palette)
    }
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(palette.red)
            Text(message).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button("重新载入") { store.reload() }.help("从本地SQLite数据库重新读取任务").disabled(store.editor != nil)
            Button("设置") { store.showSettings = true }.help("打开设置以处理数据错误")
        }.orbitFont(12).padding(12).background(palette.red.opacity(0.10), in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
    }

}

struct SidebarView: View {
    var expandedWidth: CGFloat = 224
    @EnvironmentObject private var store: AppStore
    private var palette: OrbitPalette { OrbitPalette(dark: store.dark) }
    var body: some View {
        VStack(spacing: 16) {
            if store.navCollapsed {
                OrbitMark()
            } else {
                HStack(spacing: 8) {
                    OrbitMark(); VStack(alignment: .leading, spacing: 0) {
                        Text("Space").orbitFont(24, weight: .semibold)
                        Text("个人工作台").orbitFont(12).foregroundStyle(palette.secondary)
                    }
                    Spacer()
                    OrbitIconButton(symbol: "chevron.left", label: "收起导航") { store.navCollapsed = true }
                }

            }
            VStack(spacing: 4) {
                if !store.navCollapsed { sectionLabel("工作空间") }
                navigation(.all)
            }
            Spacer(minLength: 8)
            OrbitIconButton(symbol: "gearshape", label: "数据与设置（⌘,）", compact: true) { store.showSettings = true }
                .frame(maxWidth: .infinity, alignment: store.navCollapsed ? .center : .leading)

        }.padding(.horizontal, store.navCollapsed ? 8 : 16).padding(.vertical, 16)
            .frame(width: store.navCollapsed ? 64 : expandedWidth)
            .frame(maxHeight: .infinity)
            .padding(.trailing, store.navCollapsed ? 16 : 0)
            .navigationGlass(palette, shape: SpaceSidebarShape(extended: store.navCollapsed))
            .frame(width: store.navCollapsed ? 64 : expandedWidth, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                if store.navCollapsed {
                    Button { store.navCollapsed = false } label: {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).help("展开导航").accessibilityLabel("展开导航")
                        .offset(x: 24, y: 16)
                }
            }
    }
    private func sectionLabel(_ value: String) -> some View {
        Text(value).orbitFont(12).foregroundStyle(palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.bottom, 8)
    }
    private func navigation(_ scope: TaskScope) -> some View {
        let selected = store.query.scope == scope
        return Button { store.query = TaskQuery() } label: {
            HStack(spacing: 12) {
                Image(systemName: scope.symbol).font(.system(size: 16))
                    .foregroundStyle(selected ? .white : scope.category.map { palette.category($0) } ?? palette.secondary)
                    .frame(width: 32, height: 32)
                    .background(selected ? palette.primary : palette.hover, in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
                if !store.navCollapsed {
                    Text(scope.title).orbitFont(14)
                    Spacer()
                    Text(store.count(scope).formatted()).orbitFont(12).foregroundStyle(palette.muted).monospacedDigit()
                }
            }.padding(.horizontal, store.navCollapsed ? 8 : 8).frame(height: 48)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected && !store.navCollapsed ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
        }.buttonStyle(.plain).help("\(scope.title) · \(store.count(scope)) 项")
            .accessibilityLabel("\(scope.title)，\(store.count(scope)) 项任务")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct FilterPopover: View {
    @EnvironmentObject private var store: AppStore
    @FocusState private var searchFocused: Bool
    private var palette: OrbitPalette { OrbitPalette(dark: store.dark) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("筛选与排序").orbitFont(16, weight: .semibold)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("关键词") {
                        TextField("搜索任务标题与说明", text: $store.query.text).textFieldStyle(.plain)
                            .padding(.horizontal, 12).frame(height: 40).glass(palette)
                            .focused($searchFocused).accessibilityLabel("浮动搜索任务")
                    }
                    field("任务状态") { SpaceSelect(label: "状态", selection: $store.query.status, options: store.statusFilters) }
                    field("优先级") { SpaceSelect(label: "优先级", selection: $store.query.priority, options: TaskChoices.priorities) }
                    field("所属分类") { SpaceSelect(label: "分类", selection: $store.query.category, options: TaskChoices.categories) }
                    field("截止日期") { SpaceSelect(label: "截止日期", selection: $store.query.dueFilter, options: TaskChoices.dates) }
                    field("项目") { SpaceSelect(label: "项目筛选", selection: $store.query.projectID, options: store.projectFilters) }
                    field("排序方式") { SpaceSelect(label: "排序", selection: $store.query.sort, options: TaskChoices.sorts) }
                }.padding(4)
            }.frame(height: 400)
            HStack {
                Text("\(store.visibleTasks.count) 个匹配任务").foregroundStyle(.secondary)
                Spacer(); Button("清除筛选") { store.clearFilters() }.help("清空搜索和全部筛选条件").disabled(!store.query.hasFilters)
            }.orbitFont(12)
        }.orbitFont(14).onAppear { searchFocused = true }
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).orbitFont(12, weight: .semibold).foregroundStyle(palette.secondary)
            content()
        }
    }

}

