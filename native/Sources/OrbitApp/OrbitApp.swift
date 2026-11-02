import SwiftUI
import AppKit

@main
struct OrbitApplication: App {
    @NSApplicationDelegateAdaptor(OrbitAppDelegate.self) private var delegate
    @StateObject private var store = AppStore.shared

    init() {
        // App-scoped language preference localizes AppKit panels even on an English Mac.
        UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
    }

    var body: some Scene {
        Window("Space", id: "main") {
            WorkspaceView().environmentObject(store)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .frame(minWidth: 1020, minHeight: 640)
                .preferredColorScheme(store.dark ? .dark : .light)
                .background(WindowDelegateBridge(dark: store.dark))
        }
        .defaultSize(width: 1380, height: 860)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建任务") { store.create() }.help("创建任务，可设置项目、状态与日期").keyboardShortcut("n", modifiers: .command)
                    .disabled(!store.loaded || store.editor != nil)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") {
                    if NSApp.keyWindow?.firstResponder is NSTextView {
                        NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                    } else { store.undo() }
                }.help("撤销文本或最近一次任务、状态变更").keyboardShortcut("z", modifiers: .command)
                    .disabled(store.editor == nil && !store.canUndo && !(NSApp.keyWindow?.firstResponder is NSTextView))
            }
            CommandGroup(after: .textEditing) {
                Button("搜索任务") { store.searchRequested += 1 }.help("搜索任务标题、说明与项目").keyboardShortcut("f", modifiers: .command)
                    .disabled(store.editor != nil || store.showSettings || store.showHelp)
            }
            CommandMenu("工作台") {
                Button("任务状态管理…") { store.showStatusEditor = true }.help("新增、停用或迁移后删除自定义任务状态").disabled(!store.loaded || store.editor != nil || store.showSettings || store.showHelp || store.showStatusEditor)
                Button("看板视图") { store.listMode = false }.help("按状态分列展示任务").keyboardShortcut("1", modifiers: .command)
                Button("列表视图") { store.viewMode = .list }.help("以列表整理和修改任务").keyboardShortcut("2", modifiers: .command)
                Button("甘特图视图") { store.viewMode = .gantt }.help("查看任务排期与默认截止日期").keyboardShortcut("3", modifiers: .command)
                Button("日历视图") { store.viewMode = .calendar }.help("按日、周、月查看事项").keyboardShortcut("4", modifiers: .command)
                Divider()
                Button(store.navCollapsed ? "展开导航" : "收起导航") { store.navCollapsed.toggle() }.help("切换左侧导航的图标与完整布局")
                Button(store.overviewCollapsed ? "展开概览" : "收起概览") { store.overviewCollapsed.toggle() }.help("切换顶部概览与紧凑工具栏")
                Button(store.dark ? "切换明亮主题" : "切换暗色主题") { store.dark.toggle() }.help("在明亮与暗色毛玻璃主题间切换")
                Divider()
                Button("重新载入任务") { store.reload() }.help("重新读取SQLite，避免使用过期数据覆盖本地更改").disabled(store.editor != nil)
            }
            CommandGroup(replacing: .appSettings) {
                Button("数据与设置…") { store.showSettings = true }.help("管理SQLite备份、同步配置与外观").keyboardShortcut(",", modifiers: .command)
                    .disabled(store.editor != nil)
            }
            CommandGroup(replacing: .help) { Button("Space 使用帮助") { store.showHelp = true }.help("查看项目、状态拖拽、同步和快捷键说明").disabled(store.editor != nil) }
        }
    }
}

@MainActor
final class OrbitAppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { self.localizeMenus() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  !(NSApp.keyWindow?.firstResponder is NSTextView),
                  AppStore.shared.editor == nil, !AppStore.shared.showSettings, !AppStore.shared.showHelp, !AppStore.shared.showStatusEditor,
                  NSApp.modalWindow == nil else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "n": AppStore.shared.create(); return nil
            case "/": AppStore.shared.searchRequested += 1; return nil
            case "1": AppStore.shared.listMode = false; return nil
            case "2": AppStore.shared.viewMode = .list; return nil
            case "3": AppStore.shared.viewMode = .gantt; return nil
            case "4": AppStore.shared.viewMode = .calendar; return nil
            default: return event
            }
        }
    }
    func applicationDidUpdate(_ notification: Notification) { localizeMenus() }
    func applicationDidBecomeActive(_ notification: Notification) { AppStore.shared.githubSync.wake() }

    private func localizeMenus() {
        let translations = [
            "File": "文件", "Edit": "编辑", "View": "显示", "Window": "窗口", "Help": "帮助",
            "About Space": "关于 Space", "Settings…": "设置…", "Preferences…": "偏好设置…",
            "Hide Space": "隐藏 Space", "Hide Others": "隐藏其他", "Show All": "显示全部", "Quit Space": "退出 Space",
            "Services": "服务", "Close Window": "关闭窗口", "Close": "关闭窗口", "New Window": "新建窗口",
            "Undo": "撤销", "Redo": "重做", "Cut": "剪切", "Copy": "复制", "Paste": "粘贴",
            "Paste and Match Style": "粘贴并匹配样式", "Delete": "删除", "Select All": "全选",
            "Find": "查找", "Find…": "查找…", "Find Next": "查找下一个", "Find Previous": "查找上一个",
            "Use Selection for Find": "使用所选内容查找", "Jump to Selection": "跳到所选内容",
            "Spelling and Grammar": "拼写和语法", "Substitutions": "替换", "Transformations": "转换",
            "Start Dictation…": "开始听写…", "Emoji & Symbols": "表情与符号",
            "Show Toolbar": "显示工具栏", "Hide Toolbar": "隐藏工具栏", "Customize Toolbar…": "自定工具栏…",
            "Show Sidebar": "显示侧栏", "Hide Sidebar": "隐藏侧栏", "Enter Full Screen": "进入全屏幕",
            "Exit Full Screen": "退出全屏幕", "Minimize": "最小化", "Zoom": "缩放",
            "Move Window to Left Side of Screen": "将窗口移到屏幕左侧", "Move Window to Right Side of Screen": "将窗口移到屏幕右侧",
            "Bring All to Front": "前置全部窗口", "Move & Resize": "移动与调整大小", "Center": "居中",
            "Fill": "填充", "Arrange": "排列", "Move to iPad": "移到 iPad",
            "Show Previous Tab": "显示上一个标签页", "Show Next Tab": "显示下一个标签页",
            "Move Tab to New Window": "将标签页移到新窗口", "Merge All Windows": "合并所有窗口",
            "Show Tab Bar": "显示标签页栏", "Hide Tab Bar": "隐藏标签页栏", "Show All Tabs": "显示所有标签页"
        ]
        func translate(_ menu: NSMenu) {
            for item in menu.items {
                if let localized = translations[item.title] { item.title = localized }
                if let submenu = item.submenu { translate(submenu) }
            }
        }
        if let menu = NSApp.mainMenu { translate(menu) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppStore.shared.mayDiscardEdits() ? .terminateNow : .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}

struct WindowDelegateBridge: NSViewRepresentable {
    let dark: Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.previousDelegate = window.delegate
            window.delegate = context.coordinator
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.titlebarAppearsTransparent = true
            nsView.window?.backgroundColor = dark ? .black : .windowBackgroundColor
        }
    }
    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        weak var previousDelegate: NSWindowDelegate?
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || previousDelegate?.responds(to: selector) == true
        }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            previousDelegate?.responds(to: selector) == true ? previousDelegate : super.forwardingTarget(for: selector)
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool { AppStore.shared.mayDiscardEdits() }
    }
}
