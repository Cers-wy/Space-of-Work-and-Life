import Foundation
import CryptoKit
import Security

public struct SyncConfiguration {
    public var location: String
    public var username: String
    public init(location: String, username: String = "") { self.location = location; self.username = username }
    public func baseURL() throws -> URL {
        let value = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw OrbitError.invalid("请先配置同步网络位置。") }
        if value.hasPrefix("/") { return URL(fileURLWithPath: value, isDirectory: true) }
        guard let url = URL(string: value), url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.isFileURL || (url.scheme == "https" && url.host?.isEmpty == false) else {
            throw OrbitError.invalid("请输入HTTPS/WebDAV目录地址，或已挂载网络文件夹的绝对路径。凭据请单独填写。")
        }
        return url
    }
}

public struct SyncReceipt {
    public let code: String
    public let expiresAt: Date
}
public struct DownloadedSnapshot {
    public let backup: TaskBackup
    public let receiptID: String
    public let expiresAt: Date
}
private struct EncryptedSnapshot: Codable { var format = 1; let sealed: Data }
private struct SnapshotContents: Codable {
    let database: Data
    let digest: String
    let expiresAt: Date
    let createdAt: Date
}

public enum DatabaseSync {
    public static func normalizeCode(_ code: String) throws -> String {
        var clean = code.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        if clean.hasPrefix("SP") { clean = String(clean.dropFirst(2)) }
        guard clean.count == 32, clean.allSatisfy({ "0123456789ABCDEF".contains($0) }) else {
            throw OrbitError.invalid("验证码格式无效，请粘贴另一设备生成的完整SP验证码。")
        }
        return clean
    }
    public static func generateCode() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw OrbitError.invalid("无法生成验证码，请重试。") }
        let hex = bytes.map { String(format: "%02X", $0) }.joined()
        let groups = stride(from: 0, to: hex.count, by: 4).map { offset -> String in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return String(hex[start..<hex.index(start, offsetBy: 4)])
        }
        return "SP-" + groups.joined(separator: "-")
    }
    private static func key(_ code: String) throws -> SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data(("Space encrypted SQLite backup v1:" + (try normalizeCode(code))).utf8)))
    }
    public static func receiptID(_ code: String) throws -> String { sha256(Data((try normalizeCode(code)).utf8)) }
    public static func sha256(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    public static func seal(_ database: Data, code: String, now: Date = Date(), lifetime: TimeInterval = 7 * 86400) throws -> Data {
        guard database.count <= 32 * 1024 * 1024, lifetime > 0 else { throw OrbitError.invalid("同步快照超过32MB或有效期无效。") }
        let content = SnapshotContents(database: database, digest: sha256(database), expiresAt: now.addingTimeInterval(lifetime), createdAt: now)
        let encoded = try JSONEncoder().encode(content)
        let box = try AES.GCM.seal(encoded, using: key(code))
        guard let combined = box.combined else { throw OrbitError.invalid("无法加密同步备份。") }
        return try JSONEncoder().encode(EncryptedSnapshot(sealed: combined))
    }
    public static func unseal(_ packet: Data, code: String, now: Date = Date()) throws -> Data {
        guard packet.count <= 64 * 1024 * 1024 else { throw OrbitError.tooLarge }
        let clean = try normalizeCode(code)
        do {
            let envelope = try JSONDecoder().decode(EncryptedSnapshot.self, from: packet)
            guard envelope.format == 1 else { throw OrbitError.unsupportedVersion }
            let bytes = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.sealed), using: key(clean))
            let content = try JSONDecoder().decode(SnapshotContents.self, from: bytes)
            guard content.expiresAt > now else { throw OrbitError.invalid("验证码已过期，请在来源设备重新上传备份。") }
            guard content.createdAt <= now.addingTimeInterval(300), content.database.count <= 32 * 1024 * 1024,
                  sha256(content.database) == content.digest else { throw OrbitError.invalid("备份校验失败。") }
            return content.database
        } catch let error as OrbitError { throw error }
        catch { throw OrbitError.invalid("验证码不匹配，或同步备份已损坏。") }
    }
    private static func artifactURL(_ code: String, configuration: SyncConfiguration) throws -> URL {
        try configuration.baseURL().appendingPathComponent("space-" + receiptID(code) + ".spacesync")
    }
    private static func request(_ url: URL, method: String, configuration: SyncConfiguration, password: String) -> URLRequest {
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 45
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if !configuration.username.isEmpty {
            request.setValue("Basic " + Data((configuration.username + ":" + password).utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        }
        return request
    }
    private static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.timeoutIntervalForResource = 90
        return URLSession(configuration: config)
    }
    public static func upload(snapshot: URL, configuration: SyncConfiguration, password: String = "", now: Date = Date()) async throws -> SyncReceipt {
        _ = try TaskRepository.readBackup(at: snapshot)
        let bytes = try Data(contentsOf: snapshot)
        let code = try generateCode(), url = try artifactURL(code, configuration: configuration)
        let packet = try seal(bytes, code: code, now: now)
        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else { throw OrbitError.invalid("同步文件夹不存在或尚未挂载。") }
            try packet.write(to: url, options: .atomic)
        } else {
            var req = request(url, method: "PUT", configuration: configuration, password: password)
            req.setValue("*", forHTTPHeaderField: "If-None-Match")
            let client = session(); defer { client.invalidateAndCancel() }
            let (_, response) = try await client.upload(for: req, from: packet)
            guard let http = response as? HTTPURLResponse, [200, 201, 204].contains(http.statusCode) else { throw OrbitError.invalid("上传失败，请检查目录地址、写入权限和访问凭据。") }
        }
        return SyncReceipt(code: code, expiresAt: now.addingTimeInterval(7 * 86400))
    }
    public static func download(code: String, configuration: SyncConfiguration, password: String = "", now: Date = Date()) async throws -> DownloadedSnapshot {
        let url = try artifactURL(code, configuration: configuration)
        let packet: Data
        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else { throw OrbitError.invalid("没有找到这个验证码对应的备份。") }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 64 * 1024 * 1024 else { throw OrbitError.tooLarge }
            packet = try Data(contentsOf: url)
        } else {
            let client = session(); defer { client.invalidateAndCancel() }
            let (temporary, response) = try await client.download(for: request(url, method: "GET", configuration: configuration, password: password))
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw OrbitError.invalid("下载失败：验证码不存在、目录不可访问或凭据不正确。") }
            let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 64 * 1024 * 1024 else { throw OrbitError.tooLarge }
            packet = try Data(contentsOf: temporary)
        }
        let bytes = try unseal(packet, code: code, now: now)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("space-download-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: file) }
        try bytes.write(to: file, options: .atomic)
        let backup = try TaskRepository.readBackup(at: file)
        return DownloadedSnapshot(backup: backup, receiptID: try receiptID(code), expiresAt: now.addingTimeInterval(7 * 86400))
    }
    /// Called only after the user previews the merge policy; equal-time divergent versions require explicit replacement instead.
    public static func merge(local: TaskBackup, remote: TaskBackup) throws -> TaskBackup {
        let local = try TaskBackup.decode(local.encoded()), remote = try TaskBackup.decode(remote.encoded())
        var projects = local.resolvedProjects
        var mapping: [String: String] = [:]
        for project in remote.resolvedProjects {
            if let match = projects.first(where: { $0.name.localizedCaseInsensitiveCompare(project.name) == .orderedSame }) { mapping[project.id] = match.id }
            else if let existing = projects.first(where: { $0.id == project.id }) {
                guard existing == project else { throw OrbitError.invalid("项目标识发生冲突，请先导出本地备份后选择整库替换。") }
            } else { projects.append(project) }
        }
        var tasks = Dictionary(uniqueKeysWithValues: local.tasks.map { ($0.id, $0) })
        for var task in remote.tasks {
            if let id = task.projectID, let replacement = mapping[id] { task.projectID = replacement }
            if let current = tasks[task.id], current != task {
                let left = OrbitDate.parseTimestamp(current.updatedAt)!, right = OrbitDate.parseTimestamp(task.updatedAt)!
                if left == right { throw OrbitError.invalid("任务“\(task.title)”的修改时间相同但内容不同。请先备份，再明确选择整库替换。") }
                if left > right { continue }
            }
            tasks[task.id] = task
        }
        var statuses = local.resolvedStatuses
        for status in remote.resolvedStatuses where !statuses.contains(status) { statuses.insert(status, at: statuses.firstIndex(of: .done) ?? statuses.endIndex) }
        let disabled = local.resolvedDisabledStatuses + remote.resolvedDisabledStatuses.filter { !local.resolvedDisabledStatuses.contains($0) && !local.resolvedStatuses.contains($0) }
        var settings = local.resolvedSettings
        for (key, value) in remote.resolvedSettings where !key.hasPrefix("sync.") { settings[key] = value }
        return TaskBackup(tasks: tasks.values.sorted { $0.id < $1.id }, statuses: statuses, projects: projects,
                          disabledStatuses: disabled, settings: settings, workspaceID: local.workspaceID)
    }
}
