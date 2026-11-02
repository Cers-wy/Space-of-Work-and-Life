import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    private var palette: OrbitPalette { OrbitPalette(dark: store.dark) }
    var body: some View {
        VStack(spacing: 0) {
            SpaceSheetHeader(title: "数据与设置", closeLabel: "关闭数据与设置") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("本地数据库", symbol: "externaldrive") {
                        Text("\(store.tasks.count)项任务 · \(store.projects.count)个项目 · \(store.statuses.count)个状态").orbitFont(14)
                        Text("任务、项目、状态顺序与界面设置统一保存在本地SQLite。旧JSON保留在原位置，更新不会清空任务。")
                        Text(store.repository.fileURL.path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).foregroundStyle(palette.muted)
                        Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([store.repository.fileURL]) }
                            .help("在访达中定位本地SQLite数据库及恢复备份")
                    }
                    section("界面外观", symbol: "circle.lefthalf.filled") {
                        SpaceThemeToggle(dark: $store.dark)
                        Text("蓝色奶白 / 亮紫黑色毛玻璃 · 苹方字体。界面偏好写入SQLite并随数据库快照保留。")
                    }
                    section("备份与恢复", symbol: "arrow.up.arrow.down") {
                        HStack(spacing: 8) {
                            Button("导出SQLite") { store.exportBackup() }.help("导出包含任务、项目、状态与设置的一致数据库快照").disabled(!store.loaded)
                            Button("导出JSON") { store.exportBackup(json: true) }.help("导出可迁移的JSON任务备份").disabled(!store.loaded)
                            Button("导入备份") { store.importBackup() }.help("导入SQLite或旧JSON，验证后询问是否替换本地数据")
                            Button("恢复上次备份") { store.restorePrevious() }.help("恢复最近一次数据库写入前的快照")
                                .disabled(!FileManager.default.fileExists(atPath: store.repository.previousURL.path))
                        }
                        Text("写入前自动保留space.previous.sqlite。导入会先校验并询问，原JSON不会被覆盖。")
                    }
                    section("GitHub私有仓库同步", symbol: "externaldrive.badge.icloud") { GitHubSyncView(sync: store.githubSync).environmentObject(store) }
                    section("其他位置的手动快照同步", symbol: "arrow.triangle.2.circlepath") { SyncSettingsView().environmentObject(store) }
                    section("数据整理", symbol: "square.stack") {
                        HStack(spacing: 12) {
                            Button("载入演示任务") { store.replaceWithSamples() }.help("确认后用演示任务替换当前任务，可撤销").disabled(!store.loaded)
                            Button("清空所有任务", role: .destructive) { store.clearAll() }.help("确认后清空任务，保留项目与状态，可撤销")
                                .foregroundStyle(palette.red).disabled(!store.loaded || store.tasks.isEmpty)
                        }
                    }
                    if let error = store.errorMessage { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(palette.red).textSelection(.enabled) }
                    if let notice = store.notice { Text(notice).foregroundStyle(palette.green) }
                }.orbitFont(12).padding(24)
            }
            HStack {
                Text("Space · 原生版 1.6.0").orbitFont(12).foregroundStyle(palette.muted)
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(SpaceButtonStyle(compact: true, primary: true)).help("关闭设置，已保存的配置会立即生效").keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 24).frame(height: 48)
        }.frame(width: 760, height: 760).foregroundStyle(palette.text).buttonStyle(SpaceButtonStyle())
            .background { AmbientBackground(dark: store.dark) }.onExitCommand { dismiss() }
    }
    private func section<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).orbitFont(16, weight: .semibold).foregroundStyle(palette.text)
            content()
        }.foregroundStyle(palette.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(16).glass(palette)
    }
}

struct HelpView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    private var palette: OrbitPalette { OrbitPalette(dark: store.dark) }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { OrbitMark(size: 32); Text("让每个行动，进入轨道。").orbitFont(20, weight: .semibold) }
            Text("点击任务标题编辑项目、日期与内容；点击圆圈完成任务。拖动任务跨列移动，拖动列头手柄排序。状态管理支持新增、停用和迁移后删除。悬停按钮可查看功能提示。")
            Grid(alignment: .leading, horizontalSpacing: 64, verticalSpacing: 12) {
                shortcut("新建任务", "⌘N / N"); shortcut("搜索任务", "⌘F / /")
                shortcut("看板 / 列表", "⌘1 / ⌘2 或 1 / 2")
                shortcut("甘特图 / 日历", "⌘3 / ⌘4 或 3 / 4")
                shortcut("保存任务", "⌘Return"); shortcut("撤销最近一次任务更改", "⌘Z")
                shortcut("数据与设置", "⌘,"); shortcut("关闭面板", "Esc")
            }
            Text("单键快捷键在文本输入时暂停。所有任务日期按北京时间计算，逾期表示截止日期早于今天且尚未完成。甘特图与日历共用任务筛选；未设截止日期时按今天起5天展示默认排期，不改写任务日期。设置开始日期后从该日起默认排5天。甘特图按项目展开或收起任务；拖动条中部平移，两端调整时长，松开保存，⌘Z可撤销。日历支持日、周、月切换。主题、导航、概览与视图选择会保存。")
                .foregroundStyle(.secondary).orbitFont(12)
            Text("任务与设置保存在本地SQLite。GitHub私有仓库同步支持加密备份、下载预览及可选自动同步；两端都有修改时暂停覆盖，完全退出软件后不运行。其他HTTPS/WebDAV位置仍使用手动快照和验证码。")
                .foregroundStyle(.secondary).orbitFont(12)
            HStack { Spacer(); Button("开始使用") { dismiss() }.buttonStyle(SpaceButtonStyle(primary: true)).help("关闭帮助并返回工作台").keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 640).orbitFont(14).foregroundStyle(palette.text).background { AmbientBackground(dark: store.dark) }.onExitCommand { dismiss() }
    }
    private func shortcut(_ title: String, _ keys: String) -> some View {
        GridRow { Text(title); Text(keys).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary) }
    }
}
