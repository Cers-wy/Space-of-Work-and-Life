import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OrbitCore

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()
    @Published private(set) var tasks: [OrbitTask] = []
    @Published private(set) var statuses = TaskStatus.allCases
    @Published private(set) var projects: [TaskProject] = []
    @Published private(set) var disabledStatuses: [TaskStatus] = []
    @Published var query = TaskQuery() { didSet { rebuildVisibleTasks() } }
    @Published var today = OrbitDate.day() { didSet { rebuildVisibleTasks() } }
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var editor: OrbitTask?
    @Published var hasUnsavedEdits = false
    @Published var showSettings = false
    @Published var showStatusEditor = false
    @Published var showHelp = false
    @Published var searchRequested = 0
    @Published var dark = false { didSet { persistPreference("dark", dark); NSApp?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua) } }
    @Published var navCollapsed = true { didSet { persistPreference("navCollapsed", navCollapsed) } }
    @Published var overviewCollapsed = false { didSet { persistPreference("overviewCollapsed", overviewCollapsed) } }
    @Published var viewMode: WorkspaceMode = .board { didSet { persistPreference("viewMode", viewMode.rawValue) } }
    @Published var calendarMode: CalendarMode = .month { didSet { persistPreference("calendarMode", calendarMode.rawValue) } }
    var listMode: Bool {
        get { viewMode == .list }
        set { viewMode = newValue ? .list : .board }
    }
    @Published private(set) var loaded = false
    @Published private(set) var canUndo = false
    let boardDrag = BoardDragState()
    private(set) var visibleTasks: [OrbitTask] = []
    private(set) var tasksByStatus: [TaskStatus: [OrbitTask]] = [:]
    @Published var syncBusy = false
    @Published var syncMessage: String?
    @Published var syncCode: String?
    @Published var pendingSync: DownloadedSnapshot?
    var columnFrames: [TaskStatus: CGRect] = [:]
    var boardViewport: CGRect = .zero
    let repository: TaskRepository
    lazy var githubSync = GitHubSyncController(store: self)
    private var undoState: TaskBackup?
    private var noticeTask: Task<Void, Never>?
    private var editingExisting = false
    private var hydrating = true
    private var downloadBaseline: String?
    private let legacyDefaults: UserDefaults

    init() {
        let environment = ProcessInfo.processInfo.environment
        legacyDefaults = environment["ORBIT_DEFAULTS_SUITE"].flatMap(UserDefaults.init(suiteName:)) ?? .standard
        let directory = environment["ORBIT_DATA_DIRECTORY"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("com.cers.orbit", isDirectory: true)
        repository = TaskRepository(directory: directory)
        reload()
        if loaded && repository.settings["preferencesMigrated"] == nil {
            var preferences = repository.settings
            for key in ["dark", "navCollapsed", "overviewCollapsed", "listMode"] {
                preferences[key] = String(legacyDefaults.object(forKey: key) as? Bool ?? (key == "navCollapsed"))
            }
            preferences["preferencesMigrated"] = "true"
            do { try repository.savePreferences(preferences); hydratePreferences() }
            catch { errorMessage = "偏好迁移失败：\(error.localizedDescription)" }
        }
        hydrating = false
        NSApp?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if environment["ORBIT_DATA_DIRECTORY"] != nil, ProcessInfo.processInfo.arguments.contains("--demo"), loaded, tasks.isEmpty {
            _ = commit(SampleTasks.make(), message: "已载入独立演示数据")
        }
        githubSync.start()
    }
    private func rebuildVisibleTasks() {
        visibleTasks = query.apply(to: tasks, today: today,
                                  projectNames: Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) }))
        tasksByStatus = Dictionary(grouping: visibleTasks, by: \.status)
    }
    var activeStatuses: [TaskStatus] { statuses.filter { !disabledStatuses.contains($0) } }
    var displayStatuses: [TaskStatus] { statuses.filter { status in !disabledStatuses.contains(status) || tasks.contains(where: { $0.status == status }) } }
    var statusOptions: [SpaceOption<TaskStatus>] { activeStatuses.map { SpaceOption($0, $0.title) } }
    func statusOptions(including current: TaskStatus) -> [SpaceOption<TaskStatus>] {
        statuses.filter { !disabledStatuses.contains($0) || $0 == current }.map { SpaceOption($0, $0.title + (disabledStatuses.contains($0) ? "（已停用）" : "")) }
    }
    var statusFilters: [SpaceOption<TaskStatus?>] { [SpaceOption(nil, "所有状态")] + statuses.map { SpaceOption(Optional($0), $0.title + (disabledStatuses.contains($0) ? "（已停用）" : "")) } }
    var projectOptions: [SpaceOption<String?>] { [SpaceOption(nil, "无项目")] + projects.map { SpaceOption(Optional($0.id), $0.name) } }
    var projectFilters: [SpaceOption<String?>] { [SpaceOption(nil, "所有项目")] + projects.map { SpaceOption(Optional($0.id), $0.name) } }
    func projectName(_ id: String?) -> String? { projects.first { $0.id == id }?.name }
    func count(_ scope: TaskScope) -> Int { tasks.filter { scope.contains($0, today: today) }.count }
    func refreshDay() { let day = OrbitDate.day(); if today != day { today = day } }
    private func cache() { tasks = repository.state.tasks; statuses = repository.statuses; projects = repository.projects; disabledStatuses = repository.disabledStatuses; rebuildVisibleTasks() }
    private func hydratePreferences() {
        let wasHydrating = hydrating; hydrating = true
        defer { hydrating = wasHydrating }
        let values = repository.settings
        dark = values["dark"] == "true"
        navCollapsed = values["navCollapsed"].map { $0 == "true" } ?? true
        overviewCollapsed = values["overviewCollapsed"] == "true"
        viewMode = values["viewMode"].flatMap(WorkspaceMode.init(rawValue:)) ?? (values["listMode"] == "true" ? .list : .board)
        calendarMode = values["calendarMode"].flatMap(CalendarMode.init(rawValue:)) ?? .month
    }
    private func persistPreference(_ key: String, _ value: Bool) { persistPreference(key, String(value)) }
    private func persistPreference(_ key: String, _ value: String) {
        guard loaded, !hydrating, repository.settings[key] != String(value) else { return }
        var settings = repository.settings; settings[key] = String(value)
        do { try repository.savePreferences(settings) }
        catch { errorMessage = "偏好设置尚未保存：\(error.localizedDescription)" }
    }
    func reload() {
        do {
            _ = try repository.load(); cache(); loaded = true; hydratePreferences(); errorMessage = nil
            undoState = nil; canUndo = false; refreshDay()
            if let status = query.status, !statuses.contains(status) { query.status = nil }
        } catch { loaded = false; errorMessage = "读取任务失败：\(error.localizedDescription) 原文件已保留。" }
    }
    @discardableResult
    private func commit(_ candidate: [OrbitTask], message: String, allowRecovery: Bool = false,
                        statuses definitions: [TaskStatus]? = nil, projects projectDefinitions: [TaskProject]? = nil,
                        disabled: [TaskStatus]? = nil, settings: [String: String]? = nil, workspaceID: String? = nil) -> Bool {
        guard loaded || allowRecovery else { errorMessage = "数据库尚未成功载入，请重试或导入有效备份。"; return false }
        do {
            let previous = repository.state, hadData = loaded
            try repository.save(candidate, statuses: definitions ?? statuses, projects: projectDefinitions ?? projects,
                                disabledStatuses: disabled ?? disabledStatuses, settings: settings, allowRecovery: allowRecovery, workspaceID: workspaceID)
            undoState = previous; canUndo = hadData; cache(); loaded = true
            if let status = query.status, !statuses.contains(status) { query.status = nil }
            if let project = query.projectID, !projects.contains(where: { $0.id == project }) { query.projectID = nil }
            errorMessage = nil; announce(message); if !hydrating { githubSync.changed() }; return true
        } catch { errorMessage = "保存失败：\(error.localizedDescription) 此次更改尚未保存。"; return false }
    }
    @discardableResult
    func addStatus(_ name: String) -> Bool {
        do {
            guard statuses.count < 100 else { throw OrbitError.invalid("最多支持100个任务状态。") }
            let status = try TaskStatus.custom(title: name)
            guard !statuses.contains(where: { $0.title.localizedCaseInsensitiveCompare(status.title) == .orderedSame }) else { throw OrbitError.invalid("这个状态已存在，请换一个名称。") }
            var definitions = statuses; definitions.insert(status, at: definitions.firstIndex(of: .done) ?? definitions.endIndex)
            return commit(tasks, message: "已新增状态“\(status.title)”", statuses: definitions)
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func toggleStatus(_ status: TaskStatus) {
        guard status.isCustom else { return }
        var disabled = disabledStatuses
        if disabled.contains(status) { disabled.removeAll { $0 == status } } else { disabled.append(status) }
        _ = commit(tasks, message: disabled.contains(status) ? "状态已停用，历史任务保留" : "状态已启用", disabled: disabled)
    }
    @discardableResult
    func deleteStatus(_ status: TaskStatus, movingTo destination: TaskStatus) -> Bool {
        guard status.isCustom, status != destination, activeStatuses.contains(destination) else { return false }
        let affected = tasks.filter { $0.status == status }.count
        guard confirm(title: "删除状态“\(status.title)”？", message: affected == 0 ? "没有任务使用此状态。删除后可撤销。" : "其中\(affected)项任务将移至“\(destination.title)”，任务内容保持完整。此操作可撤销。", action: affected == 0 ? "删除状态" : "迁移并删除", destructive: true) else { return false }
        return commit(tasks.map { $0.status == status ? $0.changingStatus(to: destination) : $0 }, message: "状态已删除，任务已保留",
                      statuses: statuses.filter { $0 != status }, disabled: disabledStatuses.filter { $0 != status })
    }
    func moveStatus(_ source: TaskStatus, to target: TaskStatus) {
        guard let from = statuses.firstIndex(of: source), let to = statuses.firstIndex(of: target), from != to else { return }
        var order = statuses; order.remove(at: from); order.insert(source, at: min(to, order.count))
        _ = commit(tasks, message: "已调整看板状态顺序", statuses: order)
    }
    func create(status: TaskStatus = .todo, due: String? = nil) {
        guard editor == nil, !showSettings, !showHelp, !showStatusEditor else { return }
        guard activeStatuses.contains(status) else { announce("此状态已停用，请启用后再新建任务"); return }
        editor = OrbitTask(category: query.scope.category ?? .work, status: status, due: due ?? (query.scope == .today || query.scope == .overdue ? today : ""), projectID: query.projectID)
        editingExisting = false; hasUnsavedEdits = false
    }
    func edit(_ task: OrbitTask) { editingExisting = true; editor = task; hasUnsavedEdits = false }
    func save(_ draft: OrbitTask, newProjectName: String? = nil) -> Bool {
        do {
            var task = draft, candidate = tasks, projectDefinitions = projects
            if let name = newProjectName {
                let project = try TaskProject(name: name).validated()
                if let existing = projects.first(where: { $0.name.localizedCaseInsensitiveCompare(project.name) == .orderedSame }) { task.projectID = existing.id }
                else { projectDefinitions.append(project); task.projectID = project.id }
            }
            let now = OrbitDate.timestamp(Date())
            if let index = candidate.firstIndex(where: { $0.id == task.id }) {
                let old = candidate[index]
                guard old.updatedAt == draft.updatedAt else { throw OrbitError.conflict }
                guard activeStatuses.contains(task.status) || old.status == task.status else { throw OrbitError.invalid("不能移入已停用状态。") }
                task.createdAt = old.createdAt; task.updatedAt = now
                task.completedAt = task.status == .done ? (old.status == .done ? old.completedAt : now) : nil
                candidate[index] = try task.validated()
            } else {
                guard !editingExisting else { throw OrbitError.invalid("该任务已被删除，请复制内容后重新新建。") }
                guard activeStatuses.contains(task.status) else { throw OrbitError.invalid("请选择启用中的状态。") }
                task.createdAt = now; task.updatedAt = now; task.completedAt = task.status == .done ? now : nil
                candidate.append(try task.validated())
            }
            guard commit(candidate, message: "任务已保存", projects: projectDefinitions) else { return false }
            if !visibleTasks.contains(where: { $0.id == task.id }) { announce("任务已保存；当前筛选条件下不可见") }
            hasUnsavedEdits = false; editor = nil; return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func setStatus(_ id: String, to status: TaskStatus) {
        guard activeStatuses.contains(status), let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].status != status else { return }
        var candidate = tasks; candidate[index] = candidate[index].changingStatus(to: status)
        _ = commit(candidate, message: status == .done ? "任务已完成" : "任务已移至\(status.title)")
    }
    func finishDrag(_ id: String, at point: CGPoint) {
        let destination = boardViewport.contains(point) ? columnFrames.first { $0.value.contains(point) }?.key : nil
        boardDrag.reset()
        if let destination { setStatus(id, to: destination) }
    }
    func updateSchedule(_ original: OrbitTask, to schedule: TaskSchedule) {
        guard let index = tasks.firstIndex(where: { $0.id == original.id }), tasks[index] == original else {
            errorMessage = "任务已被更改，请重新拖动排期。"; return
        }
        do {
            var candidate = tasks; candidate[index] = try schedule.applying(to: original)
            _ = commit(candidate, message: "排期已更新：" + candidate[index].startDate! + " 至 " + candidate[index].due)
        } catch { errorMessage = error.localizedDescription }
    }
    @discardableResult
    func delete(_ id: String) -> Bool {
        guard let task = tasks.first(where: { $0.id == id }), confirm(title: "删除“\(task.title)”？", message: "删除后可以通过撤销恢复。", action: "删除", destructive: true) else { return false }
        guard commit(tasks.filter { $0.id != id }, message: "任务已删除") else { return false }
        hasUnsavedEdits = false; editor = nil; return true
    }
    func undo() {
        guard editor == nil, !showSettings, !showStatusEditor, let previous = undoState else { return }
        guard commit(previous.tasks, message: "已撤销上一次更改", statuses: previous.resolvedStatuses, projects: previous.resolvedProjects, disabled: previous.resolvedDisabledStatuses) else { return }
        undoState = nil; canUndo = false
    }
    func clearFilters() { let scope = query.scope, sort = query.sort; query = TaskQuery(); query.scope = scope; query.sort = sort }
    func exportBackup(json: Bool = false) {
        let panel = NSSavePanel(); panel.allowedContentTypes = json ? [.json] : [UTType(filenameExtension: "sqlite") ?? .data]
        panel.nameFieldStringValue = "Space-任务备份-\(today)." + (json ? "json" : "sqlite")
        panel.title = "导出Space备份"; panel.prompt = "导出"; panel.nameFieldLabel = "备份名称："
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if json { try repository.state.encoded().write(to: url, options: .atomic) }
            else { try repository.exportSnapshot(to: url) }
            announce("备份已导出")
        } catch { errorMessage = "导出失败：\(error.localizedDescription)" }
    }
    private func incomingSettings(_ backup: TaskBackup) -> [String: String] {
        var settings = repository.settings
        for (key, value) in backup.resolvedSettings where !key.hasPrefix("sync.") { settings[key] = value }
        return settings
    }
    func applyGitHubBackup(_ backup: TaskBackup) throws {
        guard loaded, editor == nil, !hasUnsavedEdits, !syncBusy else { throw OrbitError.invalid("请先结束本地编辑或其他同步。") }
        let validated = try TaskBackup.decode(backup.encoded())
        guard commit(validated.tasks, message: "已恢复GitHub数据库备份", statuses: validated.resolvedStatuses,
                     projects: validated.resolvedProjects, disabled: validated.resolvedDisabledStatuses,
                     settings: repository.settings) else { throw OrbitError.invalid(errorMessage ?? "数据库恢复失败。") }
        query = TaskQuery()
    }
    func importBackup() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json, UTType(filenameExtension: "sqlite") ?? .data]; panel.allowsMultipleSelection = false
        panel.title = "导入Space SQLite或JSON备份"; panel.prompt = "导入"; panel.message = "选择任务备份文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let backup = try TaskRepository.readBackup(at: url)
            guard confirm(title: "导入\(backup.tasks.count)项任务？", message: "将替换当前\(tasks.count)项任务、项目与状态。替换前自动保存上一份SQLite备份。", action: "确认替换", destructive: true) else { return }
            if commit(backup.tasks, message: "已导入备份", allowRecovery: true, statuses: backup.resolvedStatuses, projects: backup.resolvedProjects, disabled: backup.resolvedDisabledStatuses, settings: incomingSettings(backup)) { query = TaskQuery(); hydratePreferences() }
        } catch { errorMessage = "导入失败：\(error.localizedDescription) 当前数据未更改。" }
    }
    func restorePrevious() {
        do {
            let backup = try TaskRepository.readBackup(at: repository.previousURL)
            guard confirm(title: "恢复上一次保存前的数据？", message: "备份含\(backup.tasks.count)项任务，将替换当前任务、项目和状态。", action: "恢复备份", destructive: true) else { return }
            if commit(backup.tasks, message: "已恢复上一次备份", allowRecovery: true, statuses: backup.resolvedStatuses, projects: backup.resolvedProjects, disabled: backup.resolvedDisabledStatuses, settings: incomingSettings(backup)) { hydratePreferences() }
        } catch { errorMessage = "恢复失败：\(error.localizedDescription)" }
    }
    func replaceWithSamples() {
        guard confirm(title: "载入演示任务？", message: "将用10项演示任务替换当前任务，建议先导出备份。", action: "确认替换", destructive: true) else { return }
        if commit(SampleTasks.make(), message: "已载入演示任务") { query = TaskQuery() }
    }
    func clearAll() {
        guard confirm(title: "清空所有任务？", message: "将删除当前\(tasks.count)项任务，可撤销恢复。", action: "清空任务", destructive: true) else { return }
        _ = commit([], message: "所有任务已清空")
    }
    var syncConfiguration: SyncConfiguration { SyncConfiguration(location: repository.settings["sync.location"] ?? "", username: repository.settings["sync.username"] ?? "") }
    @discardableResult
    func saveSyncConfiguration(location: String, username: String) -> Bool {
        do {
            if !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { _ = try SyncConfiguration(location: location, username: username).baseURL() }
            var settings = repository.settings; settings["sync.location"] = location.trimmingCharacters(in: .whitespacesAndNewlines); settings["sync.username"] = username
            try repository.savePreferences(settings); syncMessage = "同步位置已保存"; return true
        } catch { syncMessage = error.localizedDescription; return false }
    }
    func uploadSync(password: String) {
        guard !syncBusy, !githubSync.busy, loaded else { return }; syncBusy = true; syncMessage = "正在生成并上传加密快照…"; syncCode = nil
        let snapshot = FileManager.default.temporaryDirectory.appendingPathComponent("space-upload-\(UUID().uuidString).sqlite")
        Task {
            defer { syncBusy = false; try? FileManager.default.removeItem(at: snapshot) }
            do {
                try repository.exportSnapshot(to: snapshot)
                let receipt = try await DatabaseSync.upload(snapshot: snapshot, configuration: syncConfiguration, password: password)
                syncCode = receipt.code; syncMessage = "上传完成。验证码有效7天，另一设备填写同一同步位置后输入此码。"
            } catch { syncMessage = "上传失败：\(error.localizedDescription)" }
        }
    }
    func downloadSync(code: String, password: String) {
        guard !syncBusy, !githubSync.busy, loaded else { return }; syncBusy = true; syncMessage = "正在下载并验证数据库…"; pendingSync = nil
        let baseline = repository.revision
        Task {
            defer { syncBusy = false }
            do {
                let snapshot = try await DatabaseSync.download(code: code, configuration: syncConfiguration, password: password)
                guard repository.revision == baseline else { throw OrbitError.invalid("下载期间本地数据已改变，请重新下载后查看合并预览。") }
                if repository.settings["sync.lastReceipt"] == snapshot.receiptID || (repository.settings["sync.appliedReceipts"] ?? "").split(separator: "|").contains(Substring(snapshot.receiptID)) { syncMessage = "这个备份已经同步，无需重复下载。"; return }
                pendingSync = snapshot; downloadBaseline = baseline; syncMessage = "验证通过，请选择合并或替换。应用前会自动备份本地数据库。"
            } catch { syncMessage = "下载失败：\(error.localizedDescription)" }
        }
    }
    func applySync(replacing: Bool) {
        guard !githubSync.busy, let incoming = pendingSync, repository.revision == downloadBaseline else { syncMessage = "本地数据已有变化，请重新下载后再同步。"; pendingSync = nil; return }
        do {
            let candidate = try replacing ? incoming.backup : DatabaseSync.merge(local: repository.state, remote: incoming.backup)
            guard confirm(title: replacing ? "使用下载快照替换本地？" : "合并下载的任务？", message: replacing ? "将替换为\(candidate.tasks.count)项任务、项目、状态和界面偏好；自动保留本地上一份数据库备份。" : "保留双方任务，同标识任务保留修改时间较新的版本；将得到\(candidate.tasks.count)项任务。项目同名复用，界面偏好使用下载版本，同步地址保持本机设置。", action: replacing ? "备份并替换" : "备份并合并", destructive: true) else { return }
            var settings = incomingSettings(candidate); settings["sync.lastReceipt"] = incoming.receiptID
            let history = (settings["sync.appliedReceipts"] ?? "").split(separator: "|").map(String.init) + [incoming.receiptID]
            settings["sync.appliedReceipts"] = history.suffix(64).joined(separator: "|")
            if commit(candidate.tasks, message: "数据库同步完成", statuses: candidate.resolvedStatuses, projects: candidate.resolvedProjects, disabled: candidate.resolvedDisabledStatuses, settings: settings) {
                hydratePreferences(); query = TaskQuery(); pendingSync = nil; syncMessage = "数据库同步完成，本地上一份快照可在备份区恢复。"
            } else { syncMessage = errorMessage }
        } catch { syncMessage = error.localizedDescription }
    }
    func announce(_ message: String) {
        noticeTask?.cancel(); notice = message
        noticeTask = Task { [weak self] in try? await Task.sleep(for: .seconds(6)); guard !Task.isCancelled else { return }; self?.notice = nil }
    }
    func confirm(title: String, message: String, action: String, destructive: Bool = false) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message; alert.alertStyle = .warning
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: action)
        if destructive { alert.buttons[1].hasDestructiveAction = true }
        return alert.runModal() == .alertSecondButtonReturn
    }
    func mayDiscardEdits() -> Bool { !hasUnsavedEdits || confirm(title: "放弃未保存的更改？", message: "保留编辑可继续完成当前任务。", action: "放弃更改", destructive: true) }
}
