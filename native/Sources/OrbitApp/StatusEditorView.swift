import SwiftUI
import OrbitCore

struct StatusEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    @State private var deleting: TaskStatus?
    @State private var destination: TaskStatus = .todo
    private var palette: OrbitPalette { OrbitPalette(dark: store.dark) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("任务状态管理").orbitFont(20, weight: .semibold)
                Spacer()
                OrbitIconButton(symbol: "xmark", label: "关闭状态管理") { dismiss() }
            }.padding(.horizontal, 24).padding(.vertical, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        TextField("新状态名称，1至20字", text: $name).textFieldStyle(.plain)
                            .padding(.horizontal, 12).frame(height: 40).glass(palette).accessibilityLabel("新状态名称")
                        Button("新增") {
                            let previous = store.errorMessage
                            if store.addStatus(name) { name = ""; error = nil } else { error = store.errorMessage; store.errorMessage = previous }
                        }.buttonStyle(SpaceButtonStyle(primary: true)).help("新增任务状态，并自动增加一个看板列")
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("拖动看板列头的手柄可调整顺序。停用后不能再添加或移入任务，历史任务继续保留；删除前可将任务迁移到其他状态。")
                        .orbitFont(12).foregroundStyle(palette.secondary)
                    if let error { Text(error).orbitFont(12).foregroundStyle(palette.red) }
                    ForEach(store.statuses) { status in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Circle().fill(palette.status(status)).frame(width: 7, height: 7)
                                Text(status.title).orbitFont(14, weight: .semibold)
                                Text("\(store.tasks.filter { $0.status == status }.count)项任务").orbitFont(12).foregroundStyle(palette.muted)
                                Spacer()
                                if status.isCustom {
                                    Button(store.disabledStatuses.contains(status) ? "启用" : "停用") { store.toggleStatus(status) }
                                        .buttonStyle(SpaceButtonStyle()).help(store.disabledStatuses.contains(status) ? "重新允许在此状态中新建和移动任务" : "停止在此状态中新建任务，历史任务仍保留")
                                    OrbitIconButton(symbol: "trash", label: "删除状态“\(status.title)”，先选择任务迁移位置") { deleting = deleting == status ? nil : status; destination = .todo }
                                } else { Text("内置状态").orbitFont(12).foregroundStyle(palette.muted).help("内置状态保持系统的完成与统计规则") }
                            }
                            if store.disabledStatuses.contains(status) { Text("已停用").orbitFont(12).foregroundStyle(palette.amber) }
                            if deleting == status {
                                HStack(spacing: 12) {
                                    SpaceSelect(label: "删除后任务迁移至", selection: $destination, options: store.activeStatuses.filter { $0 != status }.map { SpaceOption($0, "移至" + $0.title) })
                                    Button("取消") { deleting = nil }.buttonStyle(SpaceButtonStyle()).help("取消删除此状态")
                                    Button("迁移并删除") {
                                        if store.deleteStatus(status, movingTo: destination) { deleting = nil }
                                    }.buttonStyle(SpaceButtonStyle(danger: true)).help("将使用此状态的任务移到所选状态，然后删除当前状态")
                                }
                            }
                        }.padding(16).glass(palette)
                    }
                    if let message = store.errorMessage { Text(message).orbitFont(12).foregroundStyle(palette.red) }
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
            HStack { Spacer(); Button("完成") { dismiss() }.buttonStyle(SpaceButtonStyle(primary: true)).help("保存的状态立即生效，关闭此面板") }.padding(.horizontal, 24).padding(.vertical, 16)
        }.frame(width: 640, height: 640).foregroundStyle(palette.text)
            .background { AmbientBackground(dark: store.dark) }.onExitCommand { dismiss() }
    }
}
