import Foundation
import CryptoKit

public struct GitHubSyncConfiguration: Codable, Equatable {
    public var owner: String
    public var repository: String
    public var branch: String
    public var path: String
    public init(owner: String = "18390208101", repository: String = "space-sync-data", branch: String = "main", path: String = "backups/latest.space") {
        self.owner = owner; self.repository = repository; self.branch = branch; self.path = path
    }
    public func validated() throws -> Self {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard [owner, repository].allSatisfy({ !$0.isEmpty && $0.utf8.count <= 100 && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(allowed.contains) }),
              !branch.isEmpty, branch.utf8.count <= 255, !branch.unicodeScalars.contains(where: { CharacterSet.controlCharacters.union(.whitespacesAndNewlines).contains($0) }),
              !path.isEmpty, path.utf8.count <= 512,
              path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0.utf8.count <= 100 && $0 != "." && $0 != ".." }),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), !path.contains("\\") else {
            throw OrbitError.invalid("GitHub仓库、分支或备份路径无效。")
        }
        return self
    }
    public var identity: String { DatabaseSync.sha256(Data((owner.lowercased() + "/" + repository.lowercased() + "\n" + branch + "\n" + path).utf8)) }
}

public struct GitHubSyncLocalState: Codable {
    public var configuration: GitHubSyncConfiguration
    public var automatic = false
    public var baseSHA: String?
    public var baseFingerprint: String?
    public var lastSyncedAt: Date?
    public init(configuration: GitHubSyncConfiguration = .init()) { self.configuration = configuration }
}

public enum GitHubSyncDecision: Equatable {
    case unchanged, upload, download, conflict, initialize, connect
    public static func resolve(local: String, remoteSHA: String?, baselineSHA: String?, baselineFingerprint: String?) -> Self {
        guard let remoteSHA else { return baselineSHA == nil ? .initialize : .conflict }
        guard let baselineSHA, let baselineFingerprint else { return .connect }
        let localChanged = local != baselineFingerprint, remoteChanged = remoteSHA != baselineSHA
        if localChanged && remoteChanged { return .conflict }
        if localChanged { return .upload }
        return remoteChanged ? .download : .unchanged
    }
}

public enum GitHubSnapshotCodec {
    // A logical database snapshot retains every task/attachment/status/project, but excludes device settings and credentials.
    public static func portable(_ backup: TaskBackup) -> TaskBackup {
        TaskBackup(tasks: backup.tasks.sorted { $0.id < $1.id }, statuses: backup.resolvedStatuses,
                   projects: backup.resolvedProjects,
                   disabledStatuses: backup.resolvedDisabledStatuses.sorted { $0.rawValue < $1.rawValue },
                   now: Date(timeIntervalSince1970: 0))
    }
    public static func fingerprint(_ backup: TaskBackup) throws -> String { DatabaseSync.sha256(try portable(backup).encoded()) }
    public static func newKey() -> String { SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() } }
    private static func key(_ string: String) throws -> SymmetricKey {
        guard let bytes = Data(base64Encoded: string.trimmingCharacters(in: .whitespacesAndNewlines)), bytes.count == 32 else {
            throw OrbitError.invalid("恢复密钥无效，需要32字节密钥的Base64文本。")
        }
        return SymmetricKey(data: bytes)
    }
    public static func validateKey(_ string: String) throws { _ = try key(string) }
    public static let maximumPacketBytes = 24 * 1024 * 1024
    private static let header = Data("SPACE-GITHUB-1\n".utf8)
    public static func seal(_ backup: TaskBackup, recoveryKey: String) throws -> Data {
        let backup = try TaskBackup.decode(portable(backup).encoded())
        let box = try AES.GCM.seal(backup.encoded(), using: key(recoveryKey), authenticating: header)
        guard let bytes = box.combined else { throw OrbitError.invalid("无法加密数据库备份。") }
        let packet = header + bytes
        guard packet.count <= maximumPacketBytes else { throw OrbitError.invalid("GitHub备份超过24MB，请减少附件或使用本地SQLite导出。") }
        return packet
    }
    public static func unseal(_ packet: Data, recoveryKey: String) throws -> TaskBackup {
        guard packet.count <= maximumPacketBytes, packet.starts(with: header) else { throw OrbitError.invalid("GitHub备份格式无效或超过24MB。") }
        do {
            let box = try AES.GCM.SealedBox(combined: packet.dropFirst(header.count))
            return try TaskBackup.decode(AES.GCM.open(box, using: key(recoveryKey), authenticating: header))
        } catch { throw OrbitError.invalid("无法解密或校验备份，请检查恢复密钥；本地数据未改变。") }
    }
}

public struct GitHubRemoteFile {
    public let sha: String
    public let content: Data?
    public let size: Int
}

public enum GitHubAPIError: LocalizedError {
    case authentication, forbidden, notFound, conflict, limited, invalid, network(Int)
    public var errorDescription: String? {
        switch self {
        case .authentication: return "GitHub令牌无效或已过期，请重新配置。"
        case .forbidden: return "GitHub访问被拒绝，请检查仓库权限或组织授权。"
        case .notFound: return "找不到仓库或分支，也可能是令牌未获授权；请检查配置。"
        case .conflict: return "云端备份在操作期间发生变化，已停止覆盖，请重新检查并同步。"
        case .limited: return "GitHub请求受限，自动同步暂停15分钟；请稍后再试。"
        case .invalid: return "GitHub返回了无法识别的数据，已停止同步。"
        case .network(let code): return "GitHub请求失败（HTTP \(code)），本地数据已保留。"
        }
    }
}

private final class GitHubRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct GitHubDatabaseClient {
    private static let secureSession = URLSession(configuration: .ephemeral, delegate: GitHubRedirectPolicy(), delegateQueue: nil)
    private let configuration: GitHubSyncConfiguration
    private let token: String
    private let session: URLSession
    public init(configuration: GitHubSyncConfiguration, token: String, session: URLSession? = nil) throws {
        self.configuration = try configuration.validated()
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw GitHubAPIError.authentication }
        self.token = value; self.session = session ?? Self.secureSession
    }
    private func url(_ suffix: [String], query: [URLQueryItem] = []) -> URL {
        var parts = URLComponents(); parts.scheme = "https"; parts.host = "api.github.com"
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        parts.percentEncodedPath = "/" + (["repos", configuration.owner, configuration.repository] + suffix)
            .map { $0.addingPercentEncoding(withAllowedCharacters: safe)! }.joined(separator: "/")
        parts.queryItems = query.isEmpty ? nil : query
        return parts.url!
    }
    private func request(_ suffix: [String], method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil, raw: Bool = false, object: Bool = false, missingOK: Bool = false) async throws -> Data? {
        var request = URLRequest(url: url(suffix, query: query)); request.httpMethod = method; request.httpBody = body
        request.timeoutInterval = 45
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(raw ? "application/vnd.github.raw+json" : (object ? "application/vnd.github.object+json" : "application/vnd.github+json"), forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Space-macOS", forHTTPHeaderField: "User-Agent")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        // Redirects must not carry the user's token outside api.github.com.
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url?.host == "api.github.com", http.url?.scheme == "https" else { throw GitHubAPIError.invalid }
        if (200..<300).contains(http.statusCode) { return bytes }
        if http.statusCode == 401 { throw GitHubAPIError.authentication }
        if http.statusCode == 429 || (http.statusCode == 403 && (http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" || http.value(forHTTPHeaderField: "retry-after") != nil)) { throw GitHubAPIError.limited }
        if http.statusCode == 403 { throw GitHubAPIError.forbidden }
        if http.statusCode == 404 { if missingOK { return nil }; throw GitHubAPIError.notFound }
        if http.statusCode == 409 || http.statusCode == 422 { throw GitHubAPIError.conflict }
        throw GitHubAPIError.network(http.statusCode)
    }
    public func verifyPrivateRepository() async throws {
        struct Repository: Decodable { let `private`: Bool }
        guard let data = try await request([]), let repository = try? JSONDecoder().decode(Repository.self, from: data) else { throw GitHubAPIError.invalid }
        guard repository.private else { throw OrbitError.invalid("请使用私有GitHub仓库；当前仓库为公开仓库，已停止上传。") }
        _ = try await request(["branches", configuration.branch])
    }
    public func readFile() async throws -> GitHubRemoteFile? {
        struct Contents: Decodable { let sha: String; let size: Int; let content: String?; let encoding: String? }
        guard let data = try await request(["contents"] + configuration.path.split(separator: "/").map(String.init), query: [URLQueryItem(name: "ref", value: configuration.branch)], object: true, missingOK: true) else { return nil }
        guard let item = try? JSONDecoder().decode(Contents.self, from: data), item.sha.count == 40,
              item.sha.allSatisfy({ $0.isHexDigit }), item.size >= 0, item.size <= GitHubSnapshotCodec.maximumPacketBytes else { throw GitHubAPIError.invalid }
        let content = item.encoding == "base64" ? item.content.flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) } : nil
        return GitHubRemoteFile(sha: item.sha, content: content, size: item.size)
    }
    public func download(_ file: GitHubRemoteFile) async throws -> Data {
        let data: Data
        if let content = file.content { data = content }
        else {
            guard let content = try await request(["git", "blobs", file.sha], raw: true) else { throw GitHubAPIError.invalid }
            data = content
        }
        guard data.count == file.size, data.count <= GitHubSnapshotCodec.maximumPacketBytes, Self.blobSHA(data) == file.sha else { throw GitHubAPIError.invalid }
        return data
    }
    static func blobSHA(_ bytes: Data) -> String {
        Insecure.SHA1.hash(data: Data(("blob " + String(bytes.count) + "\0").utf8) + bytes)
            .map { String(format: "%02x", $0) }.joined()
    }
    public func upload(_ bytes: Data, replacing sha: String?) async throws -> String {
        guard bytes.count <= GitHubSnapshotCodec.maximumPacketBytes else { throw OrbitError.tooLarge }
        struct Upload: Encodable { let message: String; let content: String; let branch: String; let sha: String? }
        struct Result: Decodable { struct Content: Decodable { let sha: String }; let content: Content }
        let body = try JSONEncoder().encode(Upload(message: "Space: encrypted database backup", content: bytes.base64EncodedString(), branch: configuration.branch, sha: sha))
        guard let data = try await request(["contents"] + configuration.path.split(separator: "/").map(String.init), method: "PUT", body: body),
              let result = try? JSONDecoder().decode(Result.self, from: data), result.content.sha == Self.blobSHA(bytes) else { throw GitHubAPIError.invalid }
        return result.content.sha
    }
}
