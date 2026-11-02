import SwiftUI
import AppKit
import Security
import LocalAuthentication
import OrbitCore

private enum SyncCredentials {
    private static func account(_ location: String, _ username: String) -> String { DatabaseSync.sha256(Data((location + "\n" + username).utf8)) }
    static func read(location: String, username: String) -> String {
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.cers.space.sync", kSecAttrAccount as String: account(location, username),
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ password: String, location: String, username: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.cers.space.sync", kSecAttrAccount as String: account(location, username)]
        let value = [kSecValueData as String: Data(password.utf8)]
        var status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = Data(password.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw OrbitError.invalid("无法保存访问凭据，请重新输入后重试。") }
    }
}

struct SyncSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var location = ""
    @State private var username = ""
    @State private var password = ""
    @State private var downloadCode = ""
    @State private var credentialError: String?
    private var palette: OrbitPalette { OrbitPalette(dark: store.dark) }
    private var effectivePassword: String { password.isEmpty ? SyncCredentials.read(location: location, username: username) : password }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("先填写双方均可访问的HTTPS/WebDAV目录，或已挂载的网络共享文件夹。服务需支持文件上传和下载；目标位置可稍后配置。")
            VStack(alignment: .leading, spacing: 8) {
                Text("同步位置").orbitFont(12, weight: .semibold)
                HStack(spacing: 8) {
                    TextField("https://… 或 /Volumes/共享文件夹", text: $location).textFieldStyle(.plain)
                        .padding(.horizontal, 12).frame(height: 40).glass(palette).accessibilityLabel("同步网络位置")
                    Button("选择文件夹") { selectFolder() }.help("选择已经挂载的网络共享目录或本地测试目录")
                }
            }
            HStack(spacing: 12) {
                TextField("用户名（可选）", text: $username).textFieldStyle(.plain).padding(.horizontal, 12).frame(height: 40).glass(palette).accessibilityLabel("同步用户名")
                SecureField("密码，留空使用已存凭据", text: $password).textFieldStyle(.plain).padding(.horizontal, 12).frame(height: 40).glass(palette).accessibilityLabel("同步访问密码")
            }
            HStack {
                Button("保存同步配置") {
                    credentialError = nil
                    if store.saveSyncConfiguration(location: location, username: username), !password.isEmpty {
                        do { try SyncCredentials.save(password, location: location, username: username) }
                        catch { credentialError = error.localizedDescription }
                    }
                }.help("将同步地址与用户名保存到SQLite，密码保存到本机钥匙串")
                Text("凭据留在本机，验证码有效7天。").orbitFont(12).foregroundStyle(palette.muted)
            }
            Divider().overlay(palette.border)
            HStack(spacing: 12) {
                Button("上传数据库备份") { store.uploadSync(password: effectivePassword) }
                    .buttonStyle(SpaceButtonStyle(primary: true)).help("生成一致的SQLite快照，加密上传，并生成另一设备可用的验证码")
                    .disabled(store.syncConfiguration.location.isEmpty || !store.loaded || store.syncBusy || configurationChanged)
                if store.syncBusy {
                    Text("正在处理…").orbitFont(12).foregroundStyle(palette.accent)
                    RoundedRectangle(cornerRadius: 4).fill(palette.hover).frame(width: 64, height: 8)
                }
            }
            if let code = store.syncCode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("另一设备使用的验证码").orbitFont(12, weight: .semibold)
                    HStack(spacing: 12) {
                        Text(code).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).foregroundStyle(palette.accent)
                        Spacer(minLength: 0)
                        Button("复制") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) }.help("复制完整验证码，供另一设备下载此备份")
                    }
                }.padding(12).glass(palette)
            }
            HStack(spacing: 8) {
                TextField("输入另一设备提供的SP验证码", text: $downloadCode).textFieldStyle(.plain)
                    .padding(.horizontal, 12).frame(height: 40).glass(palette).accessibilityLabel("下载数据库验证码")
                Button("下载并校验") { store.downloadSync(code: downloadCode, password: effectivePassword) }
                    .help("下载并验证快照，先显示同步预览，不直接覆盖本地数据")
                    .disabled(downloadCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.syncBusy || configurationChanged || store.syncConfiguration.location.isEmpty)
            }
            if let incoming = store.pendingSync {
                VStack(alignment: .leading, spacing: 12) {
                    Text("下载：\(incoming.backup.tasks.count)项任务 / \(incoming.backup.resolvedProjects.count)个项目 / \(incoming.backup.resolvedStatuses.count)个状态").orbitFont(14, weight: .semibold)
                    Text("合并保留双方任务，同一任务保留修改时间较新的版本；整库替换以下载内容为准。两种方式均先备份本地数据库，并保留本机同步地址。")
                    HStack(spacing: 8) {
                        Button("取消") { store.pendingSync = nil; store.syncMessage = "已取消，本地数据库未改变" }.help("放弃此次下载，不修改本地数据")
                        Button("备份并合并") { store.applySync(replacing: false) }.buttonStyle(SpaceButtonStyle(primary: true)).help("确认合并策略后保存双方任务，先备份本地数据库")
                        Button("备份并替换") { store.applySync(replacing: true) }.buttonStyle(SpaceButtonStyle(danger: true)).help("再次确认后，以下载快照替换本地任务、项目、状态与界面设置")
                    }
                }.padding(16).glass(palette)
            }
            if configurationChanged { Text("同步地址有未保存的改动，请先保存配置。").foregroundStyle(palette.amber) }
            if let error = credentialError { Text(error).foregroundStyle(palette.red) }
            if let message = store.syncMessage { Text(message).foregroundStyle(palette.secondary).textSelection(.enabled) }
        }.onAppear { location = store.syncConfiguration.location; username = store.syncConfiguration.username }
            .onChange(of: location) { _, _ in password = "" }
            .onChange(of: username) { _, _ in password = "" }
    }
    private var configurationChanged: Bool { location != store.syncConfiguration.location || username != store.syncConfiguration.username }
    private func selectFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.title = "选择同步文件夹"; panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url { location = url.path }
    }
}
