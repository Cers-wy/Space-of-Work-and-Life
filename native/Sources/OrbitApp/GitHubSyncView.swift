import SwiftUI
import AppKit
import OrbitCore

struct GitHubSyncView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var sync: GitHubSyncController
    @State private var owner = ""
    @State private var repository = ""
    @State private var branch = ""
    @State private var path = ""
    @State private var token = ""
    @State private var recoveryKey = ""
    @State private var automatic = false
    private var palette: OrbitPalette { OrbitPalette(dark: store.dark) }
    private var configuration: GitHubSyncConfiguration { .init(owner: owner, repository: repository, branch: branch, path: path) }
    private var changed: Bool { configuration != sync.state.configuration || automatic != sync.state.automatic || !token.isEmpty || !recoveryKey.isEmpty }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("加密备份至你的GitHub私有仓库，支持手动同步与应用运行期间的自动同步。任务、排期、项目、状态和附件一起保留；本机外观与凭据不上传。")
            HStack(spacing: 12) {
                input("GitHub账号", text: $owner)
                input("私有仓库", text: $repository)
            }
            HStack(spacing: 12) {
                input("分支", text: $branch)
                input("备份文件路径", text: $path)
            }
            SecureField(sync.hasToken ? "访问令牌已存钥匙串，留空保留" : "GitHub细粒度访问令牌", text: $token)
                .textFieldStyle(.plain).padding(12).glass(palette).accessibilityLabel("GitHub访问令牌")
            SecureField(sync.hasKey ? "恢复密钥已存钥匙串，留空保留" : "首次生成或填写另一设备的恢复密钥", text: $recoveryKey)
                .textFieldStyle(.plain).padding(12).glass(palette).accessibilityLabel("GitHub备份恢复密钥")
            HStack(spacing: 8) {
                Button("创建访问令牌…") { openTokenPage() }.help("在GitHub创建仅授权本仓库Contents读写的细粒度令牌，完成后粘贴到上方")
                if !sync.hasKey {
                    Button("生成恢复密钥") { recoveryKey = GitHubSnapshotCodec.newKey() }.help("首次上传前生成随机256位密钥；已有云端备份时应填写原密钥")
                }
                Button("复制已存恢复密钥") { sync.copyRecoveryKey() }.help("复制钥匙串中的密钥，请妥善备份并在另一设备配置同一密钥").disabled(!sync.hasKey || changed)
            }
            Toggle("自动同步（运行期间，修改后30秒，定时检查间隔5分钟）", isOn: $automatic)
                .toggleStyle(.checkbox).help("先手动建立同步基线；两端都有修改时暂停覆盖，完全退出软件后不会同步")
            HStack(spacing: 8) {
                Button("保存GitHub配置") {
                    if sync.save(configuration: configuration, token: token, key: recoveryKey, automatic: automatic) {
                        token = ""; recoveryKey = ""
                    }
                }.help("将连接信息保存在本机，令牌和恢复密钥存入macOS钥匙串").disabled(sync.busy)
                Spacer()
                Text(sync.ready ? "凭据已保存到本机钥匙串" : "待配置令牌与恢复密钥").foregroundStyle(palette.muted)
            }
            Divider().overlay(palette.border)
            HStack(spacing: 8) {
                Button("检查并同步") { sync.synchronize() }.buttonStyle(SpaceButtonStyle(primary: true)).help("比较本地和云端版本，安全上传或下载，有冲突则暂停")
                Button("下载云端预览") { sync.synchronize(downloadOnly: true) }.help("解密并校验云端备份，预览后再确认恢复")
                Button("用本机覆盖云端…") { sync.synchronize(overwrite: true) }.help("明确确认后上传本机完整数据，云端历史提交保留")
            }.disabled(changed || !sync.ready || sync.busy || !store.loaded || store.syncBusy)
                .opacity(changed || !sync.ready || sync.busy || !store.loaded || store.syncBusy ? 0.5 : 1)
            if sync.busy {
                Text("正在同步，请稍候…").foregroundStyle(palette.accent)
                RoundedRectangle(cornerRadius: 4).fill(palette.hover).frame(height: 8)
            }
            if let pending = sync.pending {
                VStack(alignment: .leading, spacing: 8) {
                    Text("云端备份：\(pending.backup.tasks.count)项任务 · \(pending.backup.resolvedProjects.count)个项目 · \(pending.backup.resolvedStatuses.count)个状态").orbitFont(14, weight: .semibold)
                    Text("恢复会替换任务数据，先保存当前SQLite快照；本机外观与连接配置保留。")
                    HStack(spacing: 8) {
                        Button("取消") { sync.cancelRestore() }
                        Button("备份并恢复云端…") { sync.restoreDownloaded() }.buttonStyle(SpaceButtonStyle(primary: true))
                    }
                }.padding(12).glass(palette)
            }
            if changed { Text("配置有未保存的修改，请先保存。").foregroundStyle(palette.amber) }
            Text(sync.message).foregroundStyle(palette.secondary).textSelection(.enabled).accessibilityLabel("GitHub同步状态：" + sync.message)
            if let date = sync.state.lastSyncedAt { Text("最近同步：" + date.formatted(date: .numeric, time: .standard)).foregroundStyle(palette.muted) }
            Text("请妥善备份恢复密钥。GitHub中只有加密数据，丢失密钥无法恢复。加密包上限24MB；附件较多时可导出本地SQLite备份。")
                .foregroundStyle(palette.muted)
        }.disabled(sync.busy)
        .onAppear {
            let value = sync.state.configuration
            owner = value.owner; repository = value.repository; branch = value.branch; path = value.path; automatic = sync.state.automatic
        }
    }
    private func input(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).foregroundStyle(palette.muted)
            TextField(label, text: text).textFieldStyle(.plain).padding(12).glass(palette).accessibilityLabel(label)
        }.frame(maxWidth: .infinity)
    }
    private func openTokenPage() {
        var url = URLComponents(string: "https://github.com/settings/personal-access-tokens/new")!
        url.queryItems = [URLQueryItem(name: "name", value: "Space desktop sync"), URLQueryItem(name: "target_name", value: owner),
            URLQueryItem(name: "description", value: "Encrypted Space backups; select only " + repository),
            URLQueryItem(name: "expires_in", value: "90"), URLQueryItem(name: "contents", value: "write")]
        if let url = url.url { NSWorkspace.shared.open(url) }
    }
}
