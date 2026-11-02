import SwiftUI
import AppKit
import OrbitCore

struct TaskEditorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft: OrbitTask
    @State private var titleError: String?
    @State private var attachmentError: String?
    @State private var creatingProject = false
    @State private var newProjectName = ""
    @FocusState private var titleFocused: Bool
    private let initial: OrbitTask
    private var palette: OrbitPalette { OrbitPalette(dark: store.dark) }
    private var existing: Bool { store.tasks.contains { $0.id == draft.id } }
    private var isDirty: Bool { draft != initial || creatingProject && !newProjectName.isEmpty }

    init(task: OrbitTask) { _draft = State(initialValue: task); initial = task }

    var body: some View {
        VStack(spacing: 0) {
            SpaceSheetHeader(title: existing ? "任务详情" : "新建任务", closeLabel: "关闭任务详情") { close() }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("任务标题 *").orbitFont(14, weight: .semibold)
                            Spacer()
                            Text("\(draft.title.utf16.count)/100").orbitFont(12).foregroundStyle(palette.muted)
                        }
                        TextField("下一步要做什么？", text: $draft.title)
                            .textFieldStyle(.plain).padding(.horizontal, 12).frame(height: 40)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous).strokeBorder(titleError != nil ? palette.red : titleFocused ? palette.accent : palette.border, lineWidth: titleFocused || titleError != nil ? 2 : 1) }
                            .focused($titleFocused)
                            .accessibilityLabel("任务标题")
                        if let titleError { Text(titleError).orbitFont(12).foregroundStyle(palette.red) }
                    }
                    HStack(alignment: .top, spacing: 16) {
                        field("所属分类") {
                            SpaceSelect(label: "所属分类", selection: $draft.category,
                                        options: TaskCategory.allCases.map { SpaceOption($0, $0.title) })
                        }
                        field("任务状态") {
                            SpaceSelect(label: "任务状态", selection: $draft.status,
                                        options: store.statusOptions(including: draft.status))
                        }
                        field("优先级") {
                            SpaceSelect(label: "优先级", selection: $draft.priority,
                                        options: TaskPriority.allCases.map { SpaceOption($0, $0.title + "优先级") })
                        }
                    }
                    field("项目 / 可选") {
                        HStack(spacing: 12) {
                            if creatingProject {
                                TextField("输入项目名称，保存任务时一起新建", text: $newProjectName)
                                    .textFieldStyle(.plain).padding(.horizontal, 12).frame(height: 40).glass(palette)
                                    .accessibilityLabel("新项目名称")
                                Button("取消新建") { creatingProject = false; newProjectName = "" }
                                    .buttonStyle(SpaceButtonStyle()).help("放弃新项目，改为选择已有项目")
                            } else {
                                SpaceSelect(label: "选择所属项目，可沿用已有项目", selection: $draft.projectID, options: store.projectOptions)
                                Button("新建项目") { creatingProject = true }
                                    .buttonStyle(SpaceButtonStyle()).help("直接输入新项目，保存后可在后续任务中复用")
                            }
                        }
                    }
                    HStack(alignment: .top, spacing: 16) {
                        field("开始日期 / 可选") {
                            SpaceDatePicker(selection: Binding(get: { draft.startDate ?? "" },
                                set: { draft.startDate = $0.isEmpty ? nil : $0 }), fieldName: "开始日期")
                        }
                        field("截止日期") { SpaceDatePicker(selection: $draft.due) }
                    }
                    Text("北京时间；也可在甘特图拖动排期条或两端调整日期。").orbitFont(12).foregroundStyle(palette.muted)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("任务说明 / 可选").orbitFont(14, weight: .semibold)
                            Spacer()
                            Text("\(draft.description.utf16.count)/5,000").orbitFont(12).foregroundStyle(palette.muted)
                        }
                        HStack(spacing: 8) {
                            Button("加粗") { NSApp.sendAction(#selector(AttachmentPasteTextView.toggleBoldText(_:)), to: nil, from: nil) }
                                .help("切换所选文字加粗（⌘B）")
                            Button("下划线") { NSApp.sendAction(#selector(NSTextView.underline(_:)), to: nil, from: nil) }
                                .help("切换所选文字下划线（⌘U）")
                            Text("支持图文混排").orbitFont(12).foregroundStyle(palette.muted)
                        }.buttonStyle(SpaceButtonStyle(compact: true))
                        TaskDescriptionTextView(text: $draft.description, richText: $draft.richDescription, attachments: draft.attachments, dark: store.dark, attach: addAttachments,
                                                reportError: { attachmentError = $0 })
                            .frame(height: 192)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous).strokeBorder(palette.border) }
                            .accessibilityLabel("任务说明")
                        HStack(spacing: 8) {
                            Button { uploadAttachments() } label: { Label("上传附件", systemImage: "paperclip") }
                                .buttonStyle(SpaceButtonStyle()).help("选择图片或文件，随任务一起保存")
                            Text("说明中可直接粘贴图片或文件").orbitFont(12).foregroundStyle(palette.muted)
                            Spacer(minLength: 0)
                        }
                        Text("单个附件≤10 MB，每项任务≤20个、合计≤20 MB").orbitFont(12).foregroundStyle(palette.muted)
                        if let attachmentError { Text(attachmentError).orbitFont(12).foregroundStyle(palette.red).textSelection(.enabled) }
                        TaskAttachmentList(attachments: $draft.attachments, reportError: { attachmentError = $0 })
                    }
                    if existing {
                        VStack(spacing: 8) {
                            timestamp("创建时间", draft.createdAt)
                            timestamp("最近更新", draft.updatedAt)
                            if let date = draft.completedAt { timestamp("完成时间", date) }
                        }
                    }
                    if let error = store.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .orbitFont(12).foregroundStyle(palette.red).textSelection(.enabled)
                    }
                }.padding(24)
            }
            Divider()
            HStack(spacing: 12) {
                if existing { Button("删除任务", role: .destructive) { store.delete(draft.id) }.buttonStyle(SpaceButtonStyle(compact: true, danger: true)).help("删除此任务，确认后可撤销恢复") }
                Spacer()
                Button("取消") { close() }.buttonStyle(SpaceButtonStyle(compact: true)).help("关闭表单，未保存更改会先询问是否放弃")
                Button(existing ? "保存更改" : "创建任务") { save() }
                    .buttonStyle(SpaceButtonStyle(compact: true, primary: true)).help(existing ? "保存任务及项目更改（⌘Return）" : "创建任务，并保存新项目（⌘Return）").keyboardShortcut(.return, modifiers: .command)
            }.padding(.horizontal, 24).frame(height: 48)
        }.frame(width: 640, height: 680).orbitFont(14).foregroundStyle(palette.text)
            .background { AmbientBackground(dark: store.dark) }
            .interactiveDismissDisabled(true)
            .onExitCommand { close() }
            .onAppear { titleFocused = true }
            .onChange(of: draft) { _, _ in store.hasUnsavedEdits = isDirty; titleError = nil }
            .onChange(of: newProjectName) { _, _ in store.hasUnsavedEdits = isDirty }
            .onChange(of: creatingProject) { _, _ in store.hasUnsavedEdits = isDirty }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).orbitFont(14, weight: .semibold); content() }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func timestamp(_ title: String, _ raw: String) -> some View {
        HStack {
            Text(title); Spacer()
            Text(OrbitDate.parseTimestamp(raw)?.formatted(Date.FormatStyle(date: .numeric, time: .shortened, locale: Locale(identifier: "zh_CN"), calendar: OrbitDate.calendar, timeZone: OrbitDate.calendar.timeZone)) ?? raw)
        }.orbitFont(12).foregroundStyle(palette.muted)
    }
    private func addAttachments(_ attachments: [TaskAttachment]) {
        do {
            let candidate = draft.attachments + attachments
            try TaskAttachment.validate(candidate)
            draft.attachments = candidate; attachmentError = nil
        } catch { attachmentError = error.localizedDescription }
    }
    private func uploadAttachments() {
        let panel = NSOpenPanel(); panel.title = "上传任务图片或附件"; panel.prompt = "添加"
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        do { addAttachments(try TaskAttachmentFiles.read(panel.urls)) }
        catch { attachmentError = error.localizedDescription }
    }
    private func close() {
        if store.mayDiscardEdits() { store.hasUnsavedEdits = false; store.editor = nil }
    }
    private func save() {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { titleError = "请输入任务标题。"; titleFocused = true; return }
        guard draft.title.utf16.count <= 100 else { titleError = "任务标题最多 100 字。"; titleFocused = true; return }
        guard draft.description.utf16.count <= 5000 else { titleError = "任务说明最多 5,000 字。"; return }
        _ = store.save(draft, newProjectName: creatingProject ? newProjectName : nil)
    }
}
