import XCTest
import Foundation
import CryptoKit
@testable import OrbitCore

private final class GitHubMockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (status, headers, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class GitHubSyncTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1793232000)
    private func client(configuration: GitHubSyncConfiguration = .init()) throws -> GitHubDatabaseClient {
        let configurationForSession = URLSessionConfiguration.ephemeral
        configurationForSession.protocolClasses = [GitHubMockProtocol.self]
        return try GitHubDatabaseClient(configuration: configuration, token: "unit-test-token", session: URLSession(configuration: configurationForSession))
    }
    override func tearDown() { GitHubMockProtocol.handler = nil; super.tearDown() }
    private func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    private func content(_ bytes: Data, embedded: Bool = true) throws -> Data {
        try json(["sha": GitHubDatabaseClient.blobSHA(bytes), "size": bytes.count,
                  "encoding": embedded ? "base64" : "none", "content": embedded ? bytes.base64EncodedString() : ""])
    }
    func testConfigurationRejectsTraversalAndCredentialInjectionAndSeparatesBranches() throws {
        for path in ["../backup", "/backup", "backup//data", "backup/./data", "backup\\data", "data\nsecret"] {
            XCTAssertThrowsError(try GitHubSyncConfiguration(path: path).validated())
        }
        XCTAssertThrowsError(try GitHubSyncConfiguration(owner: "user/token").validated())
        XCTAssertThrowsError(try GitHubSyncConfiguration(branch: "main\rheader").validated())
        XCTAssertNotEqual(GitHubSyncConfiguration().identity, GitHubSyncConfiguration(branch: "backup").identity)
        XCTAssertThrowsError(try GitHubDatabaseClient(configuration: .init(), token: "token\r\nsecret"))
    }
    func testBlobSHAMatchesKnownGitObjectHashes() {
        XCTAssertEqual(GitHubDatabaseClient.blobSHA(Data()), "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391")
        XCTAssertEqual(GitHubDatabaseClient.blobSHA(Data("hello\n".utf8)), "ce013625030ba8dba906f756967f9e9ca394464a")
    }
    func testBothSidesChangedAndDeletedCloudFileNeverChooseUpload() {
        XCTAssertEqual(GitHubSyncDecision.resolve(local: "modified", remoteSHA: "new", baselineSHA: "old", baselineFingerprint: "base"), .conflict)
        XCTAssertEqual(GitHubSyncDecision.resolve(local: "base", remoteSHA: nil, baselineSHA: "old", baselineFingerprint: "base"), .conflict)
        XCTAssertEqual(GitHubSyncDecision.resolve(local: "modified", remoteSHA: "old", baselineSHA: "old", baselineFingerprint: "base"), .upload)
        XCTAssertEqual(GitHubSyncDecision.resolve(local: "base", remoteSHA: "new", baselineSHA: "old", baselineFingerprint: "base"), .download)
        XCTAssertEqual(GitHubSyncDecision.resolve(local: "base", remoteSHA: "old", baselineSHA: "old", baselineFingerprint: "base"), .unchanged)
        XCTAssertEqual(GitHubSyncDecision.resolve(local: "base", remoteSHA: "new", baselineSHA: nil, baselineFingerprint: nil), .connect)
        XCTAssertEqual(GitHubSyncDecision.resolve(local: "base", remoteSHA: nil, baselineSHA: nil, baselineFingerprint: nil), .initialize)
    }
    func testFingerprintIgnoresDevicePreferencesButDetectsDeletionAttachmentsAndScheduleChanges() throws {
        let task = OrbitTask(id: "a", title: "版本比较", now: now)
        let first = TaskBackup(tasks: [task], settings: ["dark": "true", "sync.location": "secret-location"], workspaceID: "device-a", revision: "a", now: now)
        let otherDevice = TaskBackup(tasks: [task], settings: ["dark": "false"], workspaceID: "device-b", revision: "b", now: now.addingTimeInterval(60))
        XCTAssertEqual(try GitHubSnapshotCodec.fingerprint(first), try GitHubSnapshotCodec.fingerprint(otherDevice))
        XCTAssertNotEqual(try GitHubSnapshotCodec.fingerprint(first), try GitHubSnapshotCodec.fingerprint(TaskBackup(tasks: [])))
        var updated = task; updated.startDate = "2026-10-29"; updated.due = "2026-10-30"
        XCTAssertNotEqual(try GitHubSnapshotCodec.fingerprint(first), try GitHubSnapshotCodec.fingerprint(TaskBackup(tasks: [updated])))
        updated = task; updated.attachments = [.init(name: "proof.txt", typeIdentifier: "public.plain-text", data: Data("new bytes".utf8))]
        XCTAssertNotEqual(try GitHubSnapshotCodec.fingerprint(first), try GitHubSnapshotCodec.fingerprint(TaskBackup(tasks: [updated])))
    }
    func testEncryptedBackupPreservesLatestSchemaAndRoundTripsAcrossTwoSQLiteDatabases() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = TaskRepository(directory: directory.appendingPathComponent("source")); _ = try source.load()
        let target = TaskRepository(directory: directory.appendingPathComponent("target")); _ = try target.load()
        let project = TaskProject(name: "同步验证"), status = try TaskStatus.custom(title: "等待反馈")
        let statuses = [TaskStatus.todo, status, .doing, .done]
        var task = OrbitTask(title: "排期和附件", status: status, due: "2026-11-03", projectID: project.id, now: now)
        task.startDate = "2026-10-29"
        task.attachments = [.init(name: "附件.txt", typeIdentifier: "public.plain-text", data: Data("原始附件字节".utf8))]
        try source.save([task], statuses: statuses, projects: [project], disabledStatuses: [status], settings: ["sync.location": "private-url", "github.token": "must-not-leak"])
        let key = GitHubSnapshotCodec.newKey(), packet = try GitHubSnapshotCodec.seal(source.state, recoveryKey: key)
        XCTAssertFalse(String(decoding: packet, as: UTF8.self).contains("must-not-leak"))
        let backup = try GitHubSnapshotCodec.unseal(packet, recoveryKey: key)
        XCTAssertEqual(backup.version, 5); XCTAssertTrue(backup.resolvedSettings.isEmpty)
        XCTAssertNil(backup.workspaceID); XCTAssertNil(backup.revision)
        try target.save(backup.tasks, statuses: backup.resolvedStatuses, projects: backup.resolvedProjects, disabledStatuses: backup.resolvedDisabledStatuses)
        let reopened = TaskRepository(directory: target.directory); _ = try reopened.load()
        XCTAssertEqual(reopened.state.tasks, [task]); XCTAssertEqual(reopened.statuses, statuses)
        XCTAssertEqual(reopened.disabledStatuses, [status]); XCTAssertEqual(reopened.projects, [project])
        XCTAssertEqual(try GitHubSnapshotCodec.fingerprint(source.state), try GitHubSnapshotCodec.fingerprint(reopened.state))
    }
    func testProjectOrderingRemainsStableInGanttAfterEncryptedRestore() throws {
        let first = TaskProject(id: "z", name: "先建项目"), second = TaskProject(id: "a", name: "后建项目")
        let source = TaskBackup(tasks: [], projects: [first, second])
        let key = GitHubSnapshotCodec.newKey()
        let restored = try GitHubSnapshotCodec.unseal(GitHubSnapshotCodec.seal(source, recoveryKey: key), recoveryKey: key)
        XCTAssertEqual(restored.resolvedProjects, [first, second])
        XCTAssertNotEqual(try GitHubSnapshotCodec.fingerprint(source), try GitHubSnapshotCodec.fingerprint(TaskBackup(tasks: [], projects: [second, first])))
    }
    func testCipherRejectsWrongKeyAndTamperingAndUsesDifferentNonceEachTime() throws {
        let key = GitHubSnapshotCodec.newKey(), backup = TaskBackup(tasks: [OrbitTask(title: "不能明文上传", now: now)])
        let first = try GitHubSnapshotCodec.seal(backup, recoveryKey: key), second = try GitHubSnapshotCodec.seal(backup, recoveryKey: key)
        XCTAssertNotEqual(first, second)
        XCTAssertThrowsError(try GitHubSnapshotCodec.unseal(first, recoveryKey: GitHubSnapshotCodec.newKey()))
        var damaged = first; damaged[damaged.count - 1] ^= 1
        XCTAssertThrowsError(try GitHubSnapshotCodec.unseal(damaged, recoveryKey: key))
        XCTAssertThrowsError(try GitHubSnapshotCodec.validateKey("short"))
        XCTAssertThrowsError(try GitHubSnapshotCodec.unseal(Data("plaintext".utf8), recoveryKey: key))
    }
    func testPrivateRepositoryAndExistingBranchAreCheckedBeforeMissingFileIsAccepted() async throws {
        let mock = try client(); var requests: [String] = []
        GitHubMockProtocol.handler = { request in
            let path = request.url!.path; requests.append(path)
            XCTAssertEqual(request.url!.host, "api.github.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-token")
            if path.hasSuffix("/space-sync-data") { return (200, [:], try self.json(["private": true])) }
            if path.hasSuffix("/branches/main") { return (200, [:], try self.json(["name": "main"])) }
            return (404, [:], Data())
        }
        try await mock.verifyPrivateRepository()
        let remote = try await mock.readFile(); XCTAssertNil(remote); XCTAssertEqual(requests.count, 3)
    }
    func testPublicRepositoryAndMissingRepositoryAreRejected() async throws {
        let mock = try client()
        GitHubMockProtocol.handler = { _ in (200, [:], try self.json(["private": false])) }
        do { try await mock.verifyPrivateRepository(); XCTFail("public repository must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("公开")) }
        GitHubMockProtocol.handler = { _ in (404, [:], Data()) }
        do { try await mock.verifyPrivateRepository(); XCTFail("missing repository must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("授权")) }
    }
    func testRawBlobDownloadPinsExactContentSHAForFilesWithoutEmbeddedContent() async throws {
        let bytes = Data("larger encrypted packet".utf8), mock = try client()
        let sha = GitHubDatabaseClient.blobSHA(bytes)
        GitHubMockProtocol.handler = { request in
            if request.url!.path.contains("/contents/") { return (200, [:], try self.content(bytes, embedded: false)) }
            XCTAssertTrue(request.url!.path.hasSuffix("/git/blobs/" + sha))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github.raw+json")
            return (200, [:], bytes)
        }
        let remote = try await mock.readFile(); let restored = try await mock.download(XCTUnwrap(remote))
        XCTAssertEqual(restored, bytes)
    }
    func testEmbeddedContentMismatchIsRejectedRatherThanApplied() async throws {
        let mock = try client()
        GitHubMockProtocol.handler = { _ in (200, [:], try self.json(["sha": String(repeating: "0", count: 40), "size": 3, "encoding": "base64", "content": Data("bad".utf8).base64EncodedString()])) }
        let remote = try await mock.readFile()
        do { _ = try await mock.download(XCTUnwrap(remote)); XCTFail("invalid hash must fail") }
        catch { XCTAssertTrue(error is GitHubAPIError) }
    }
    func testUpdateIncludesExpectedSHAAndConflictIsNotRetriedWithNewestSHA() async throws {
        let mock = try client(), bytes = Data("encrypted payload".utf8), sha = String(repeating: "a", count: 40)
        var calls = 0
        GitHubMockProtocol.handler = { request in
            calls += 1; XCTAssertEqual(request.httpMethod, "PUT")
            // URLSession may expose the body as a stream when custom URLProtocol intercepts it.
            let body: Data
            if let data = request.httpBody { body = data }
            else if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }; var result = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; result.append(contentsOf: buffer.prefix(count)) }
                body = result
            } else { throw URLError(.badServerResponse) }
            let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
            XCTAssertEqual(json["sha"] as? String, sha); XCTAssertEqual(json["branch"] as? String, "main")
            XCTAssertEqual(json["content"] as? String, bytes.base64EncodedString())
            return (409, [:], Data())
        }
        do { _ = try await mock.upload(bytes, replacing: sha); XCTFail("stale SHA must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("发生变化")) }
        XCTAssertEqual(calls, 1)
    }
    func testCreateOmitsSHAAndAcceptsOnlyReturnedContentHash() async throws {
        let mock = try client(), bytes = Data("encrypted payload".utf8), sha = GitHubDatabaseClient.blobSHA(Data("encrypted payload".utf8))
        GitHubMockProtocol.handler = { request in
            if let data = request.httpBody {
                let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                XCTAssertNil(body["sha"])
            }
            return (201, [:], try self.json(["content": ["sha": sha]]))
        }
        let result = try await mock.upload(bytes, replacing: nil); XCTAssertEqual(result, sha)
        GitHubMockProtocol.handler = { _ in (201, [:], try self.json(["content": ["sha": String(repeating: "f", count: 40)]])) }
        do { _ = try await mock.upload(bytes, replacing: nil); XCTFail("wrong returned hash must fail") }
        catch { XCTAssertTrue(error is GitHubAPIError) }
    }
    func testRateLimitAndAuthenticationFailuresDoNotExposeToken() async throws {
        let mock = try client()
        for status in [401, 403, 429] {
            GitHubMockProtocol.handler = { _ in (status, status == 429 ? ["retry-after": "900"] : [:], Data("unit-test-token".utf8)) }
            do { _ = try await mock.readFile(); XCTFail("error status must fail") }
            catch { XCTAssertFalse(error.localizedDescription.contains("unit-test-token")); XCTAssertTrue(error is GitHubAPIError) }
        }
    }
}
