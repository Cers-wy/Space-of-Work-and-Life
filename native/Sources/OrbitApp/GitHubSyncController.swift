import Foundation
import AppKit
import Security
import LocalAuthentication
import OrbitCore

/// Credentials never enter SQLite, backups, log messages or the sync-state file.
enum GitHubCredentials {
    static func read(_ kind: String, identity: String) throws -> String? {
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.cers.space.github", kSecAttrAccount as String: identity + ":" + kind,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw OrbitError.invalid("无法读取钥匙串凭据，请在GitHub同步设置中重新保存令牌和恢复密钥。")
        }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ value: String, kind: String, identity: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.cers.space.github", kSecAttrAccount as String: identity + ":" + kind]
        let bytes = Data(value.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = bytes
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw OrbitError.invalid("无法保存到macOS钥匙串，请重试。") }
    }
}

struct GitHubPendingRestore {
    let backup: TaskBackup
    let sha: String
    let localFingerprint: String
}

@MainActor
final class GitHubSyncController: ObservableObject {
    @Published private(set) var state: GitHubSyncLocalState
    @Published private(set) var busy = false
    @Published private(set) var message = "尚未配置GitHub同步。"
    @Published private(set) var hasToken = false
    @Published private(set) var hasKey = false
    @Published private(set) var pending: GitHubPendingRestore?
    private unowned let store: AppStore
    private let stateURL: URL
    private var timer: Timer?
    private var delayed: Task<Void, Never>?
    private var failureCount = 0
    private var nextAttempt = Date.distantPast
    private var observing = false
    private(set) var applying = false
    var ready: Bool { hasToken && hasKey }

    init(store: AppStore) {
        self.store = store
        stateURL = store.repository.directory.appendingPathComponent("github-sync.json")
        if FileManager.default.fileExists(atPath: stateURL.path) {
            do {
                let data = try Data(contentsOf: stateURL)
                guard data.count <= 16384 else { throw GitHubAPIError.invalid }
                let loaded = try JSONDecoder().decode(GitHubSyncLocalState.self, from: data)
                _ = try loaded.configuration.validated()
                state = loaded; message = "GitHub同步配置已载入。"
            } catch {
                state = .init(); message = "本机GitHub同步记录损坏，原文件已保留；请重新保存配置，首次连接会要求确认。"
            }
        } else { state = .init() }
        refreshCredentials()
    }
    private func refreshCredentials() {
        do {
            hasToken = try GitHubCredentials.read("token", identity: state.configuration.identity) != nil
            hasKey = try GitHubCredentials.read("key", identity: state.configuration.identity) != nil
        } catch { hasToken = false; hasKey = false; message = error.localizedDescription }
    }
    private func persist(_ candidate: GitHubSyncLocalState) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(candidate).write(to: stateURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
        state = candidate
    }
    @discardableResult
    func save(configuration: GitHubSyncConfiguration, token: String, key: String, automatic: Bool) -> Bool {
        guard !busy else { return false }
        do {
            let configuration = try configuration.validated()
            var candidate = state
            if configuration.identity != candidate.configuration.identity {
                candidate = .init(configuration: configuration)
            }
            let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                guard !token.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw GitHubAPIError.authentication }
                try GitHubCredentials.save(token, kind: "token", identity: configuration.identity)
            }
            if !key.isEmpty {
                try GitHubSnapshotCodec.validateKey(key)
                let previous = try GitHubCredentials.read("key", identity: configuration.identity)
                // A changed key invalidates the baseline, so it cannot silently encrypt over an existing cloud backup.
                if previous != key { candidate.baseSHA = nil; candidate.baseFingerprint = nil; candidate.lastSyncedAt = nil }
                try GitHubCredentials.save(key, kind: "key", identity: configuration.identity)
            }
            candidate.configuration = configuration; candidate.automatic = automatic
            try persist(candidate); pending = nil; refreshCredentials()
            nextAttempt = .distantPast; failureCount = 0
            message = ready ? "配置已保存。点击检查并同步，首次上传或恢复需确认。" : "连接信息已保存，请补充访问令牌和恢复密钥。"
            return true
        } catch { message = "保存配置失败：" + error.localizedDescription; return false }
    }
    func copyRecoveryKey() {
        do {
            guard let key = try GitHubCredentials.read("key", identity: state.configuration.identity) else { return }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(key, forType: .string)
            message = "恢复密钥已复制。请存入密码管理器，另一设备需要同一密钥；不要提交到GitHub。"
        } catch { message = error.localizedDescription }
    }
    func start() {
        guard !observing else { return }; observing = true
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.wake() }
        }
        wake()
    }
    func changed() {
        guard state.automatic, ready, !applying else { return }
        delayed?.cancel()
        delayed = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            self?.wake()
        }
    }
    func wake() {
        // Auto-sync starts only after an explicit first connection has established a baseline.
        guard state.automatic, state.baseSHA != nil, ready, !busy, pending == nil,
              store.loaded, store.editor == nil, !store.hasUnsavedEdits, !store.syncBusy, Date() >= nextAttempt else { return }
        synchronize(automatic: true)
    }
    private func checkedSnapshot() throws -> TaskBackup {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("space-github-" + UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        try store.repository.exportSnapshot(to: url)
        return try TaskRepository.readBackup(at: url)
    }
    func cancelRestore() { pending = nil; message = "已取消恢复，本地数据未改变。" }
    private func confirm(_ title: String, _ detail: String, action: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail; alert.alertStyle = .warning
        alert.addButton(withTitle: action); alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
    func synchronize(automatic: Bool = false, downloadOnly: Bool = false, overwrite: Bool = false) {
        guard !busy, store.loaded, !store.syncBusy else { return }
        guard store.editor == nil, !store.hasUnsavedEdits else { message = "请先保存或取消正在编辑的任务，再同步。"; return }
        guard Date() >= nextAttempt else { message = "正在等待网络或限流退避，请稍后重试。"; return }
        busy = true; pending = nil; message = "正在检查GitHub私有仓库与备份版本…"
        let configuration = state.configuration
        Task {
            defer { busy = false }
            do {
                guard let token = try GitHubCredentials.read("token", identity: configuration.identity),
                      let key = try GitHubCredentials.read("key", identity: configuration.identity) else {
                    throw OrbitError.invalid("请先在设置中保存GitHub访问令牌和恢复密钥。")
                }
                let client = try GitHubDatabaseClient(configuration: configuration, token: token)
                try await client.verifyPrivateRepository()
                let remote = try await client.readFile()
                // Read the current database only after the network check; it may have changed while awaiting the response.
                guard store.loaded, store.editor == nil, !store.syncBusy else { throw OrbitError.invalid("本地数据正在编辑或同步，请稍后重试。") }
                let snapshot = try checkedSnapshot()
                let localFingerprint = try GitHubSnapshotCodec.fingerprint(snapshot)
                var decision = GitHubSyncDecision.resolve(local: localFingerprint, remoteSHA: remote?.sha,
                    baselineSHA: state.baseSHA, baselineFingerprint: state.baseFingerprint)
                if downloadOnly { decision = .download }
                if overwrite { decision = .upload }
                switch decision {
                case .unchanged:
                    message = "本地与GitHub备份一致，无需上传。"
                case .conflict:
                    message = "本地和云端都有变化，已暂停自动覆盖。可下载预览后恢复云端，或明确选择用本机覆盖云端。"
                case .initialize, .upload:
                    if decision == .initialize && automatic { message = "云端尚无备份，请手动完成首次上传。"; return }
                    if overwrite || decision == .initialize {
                        let title = overwrite ? "用本机数据覆盖云端备份？" : "首次上传加密数据库备份？"
                        guard !automatic, confirm(title,
                            "将把当前\(snapshot.tasks.count)项任务、项目、状态、排期和附件加密上传至\(configuration.owner)/\(configuration.repository)。云端历史提交保留；恢复密钥只留在钥匙串，请另行妥善备份。", action: "确认上传") else { message = "已取消上传。"; return }
                    }
                    // Validate the key against the existing cloud packet before overwriting it.
                    if let remote { _ = try GitHubSnapshotCodec.unseal(try await client.download(remote), recoveryKey: key) }
                    let packet = try GitHubSnapshotCodec.seal(snapshot, recoveryKey: key)
                    let sha = try await client.upload(packet, replacing: remote?.sha)
                    var accepted = state; accepted.baseSHA = sha; accepted.baseFingerprint = localFingerprint; accepted.lastSyncedAt = Date()
                    try persist(accepted)
                    let stillCurrent = try GitHubSnapshotCodec.fingerprint(store.repository.state) == localFingerprint
                    message = stillCurrent ? "加密数据库备份已上传至GitHub。" : "快照已上传；上传期间有新修改，仍待下一次同步。"
                    if !stillCurrent { changed() }
                case .connect, .download:
                    guard let remote else { throw OrbitError.invalid("云端尚无数据库备份，请先上传。") }
                    let backup = try GitHubSnapshotCodec.unseal(try await client.download(remote), recoveryKey: key)
                    guard try GitHubSnapshotCodec.fingerprint(store.repository.state) == localFingerprint,
                          store.editor == nil, !store.syncBusy else { throw OrbitError.invalid("下载期间本地数据已变化，已停止恢复，请重新检查。") }
                    let fingerprint = try GitHubSnapshotCodec.fingerprint(backup)
                    if fingerprint == localFingerprint {
                        var accepted = state; accepted.baseSHA = remote.sha; accepted.baseFingerprint = fingerprint; accepted.lastSyncedAt = Date()
                        try persist(accepted); message = "已连接GitHub，双方数据一致。"
                    } else if automatic && decision == .download && localFingerprint == state.baseFingerprint {
                        try apply(backup, sha: remote.sha, expectedLocalFingerprint: localFingerprint)
                    } else {
                        pending = GitHubPendingRestore(backup: backup, sha: remote.sha, localFingerprint: localFingerprint)
                        message = "备份已下载并校验，请预览后确认恢复。本地数据尚未改变。"
                    }
                }
                failureCount = 0; nextAttempt = .distantPast
            } catch {
                failureCount += 1
                let limited = (error as? GitHubAPIError).map { if case .limited = $0 { return true }; return false } ?? false
                nextAttempt = Date().addingTimeInterval(limited ? 900 : min(900, 60 * pow(2, Double(min(failureCount - 1, 4)))))
                message = "同步未完成：" + error.localizedDescription
            }
        }
    }
    func restoreDownloaded() {
        guard !busy, let pending else { return }
        guard confirm("备份并恢复云端数据？", "将用云端\(pending.backup.tasks.count)项任务替换本地任务、项目、状态和附件。恢复前自动保留本地上一份SQLite快照；本机外观和连接配置保留。", action: "备份并恢复") else { return }
        do { try apply(pending.backup, sha: pending.sha, expectedLocalFingerprint: pending.localFingerprint) }
        catch { message = "恢复未完成：" + error.localizedDescription; self.pending = nil }
    }
    private func apply(_ backup: TaskBackup, sha: String, expectedLocalFingerprint: String) throws {
        guard try GitHubSnapshotCodec.fingerprint(store.repository.state) == expectedLocalFingerprint,
              store.editor == nil, !store.syncBusy else { throw OrbitError.invalid("本地数据已变化，请重新下载后再恢复。") }
        applying = true; defer { applying = false }
        try store.applyGitHubBackup(backup)
        var accepted = state; accepted.baseSHA = sha; accepted.baseFingerprint = try GitHubSnapshotCodec.fingerprint(backup); accepted.lastSyncedAt = Date()
        try persist(accepted); pending = nil
        message = "已恢复GitHub备份，原本地数据保留在上一份SQLite快照中。"
    }
}
