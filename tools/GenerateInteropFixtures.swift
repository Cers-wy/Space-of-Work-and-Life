import Foundation
import AppKit

// Synthetic interoperability fixtures only. The deterministic key/code below are public test data.
@main
struct GenerateInteropFixtures {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Usage: generator <fixture-directory>") }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = OrbitDate.parseTimestamp("2026-11-02T00:00:00.000Z")!
        func write(_ data: Data, _ name: String) throws {
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        }
        var task = OrbitTask(id: "fixture-task-1", title: "合成样本：整理资料", description: "不是个人任务。用于复刻互通测试。", now: now)
        let v1 = TaskBackup(tasks: [task], now: now)
        try write(v1.encoded(), "01-json-v1.json")
        let project = TaskProject(id: "fixture-project-1", name: "合成示例项目")
        let custom = try TaskStatus.custom(title: "等待反馈")
        let statuses = [TaskStatus.todo, custom, .doing, .done]
        var taskV2 = task; taskV2.status = custom; taskV2.projectID = nil
        let v2 = TaskBackup(tasks: [taskV2], statuses: statuses, now: now)
        try write(v2.encoded(), "01b-json-v2.json")
        task.projectID = project.id
        task.status = custom
        let v3 = TaskBackup(tasks: [task], statuses: statuses, projects: [project], disabledStatuses: [custom],
                            settings: ["dark": "true", "viewMode": "calendar"], workspaceID: "fixture-workspace", now: now)
        try write(v3.encoded(), "02-json-v3.json")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        task.attachments = [TaskAttachment(id: "fixture-file-1", name: "示例.txt", typeIdentifier: "public.plain-text", data: Data("合成附件\n".utf8)),
                            TaskAttachment(id: "fixture-image-1", name: "示例.png", typeIdentifier: "public.png", data: png)]
        let v4 = TaskBackup(tasks: [task], statuses: statuses, projects: [project], now: now)
        try write(v4.encoded(), "03-json-v4.json")
        task.startDate = "2026-11-02"; task.due = "2026-11-07"
        let v5 = TaskBackup(tasks: [task], statuses: statuses, projects: [project], now: now)
        try write(v5.encoded(), "04-json-v5.json")
        let content = NSMutableAttributedString(string: "合成图文样本：加粗与下划线\n", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        content.addAttributes([.font: NSFont.boldSystemFont(ofSize: 14), .underlineStyle: NSUnderlineStyle.single.rawValue], range: NSRange(location: 0, length: 6))
        let wrapper = FileWrapper(regularFileWithContents: png); wrapper.preferredFilename = "示例.png"
        let image = NSTextAttachment(fileWrapper: wrapper)
        content.append(NSAttributedString(attachment: image))
        content.append(NSAttributedString(string: "\n图片后文字"))
        task.richDescription = try content.data(from: NSRange(location: 0, length: content.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        task.description = content.string
        guard let reread = NSAttributedString(rtfd: task.richDescription!, documentAttributes: nil) else {
            fatalError("Generated rich text cannot be decoded by AppKit")
        }
        precondition(reread.string == task.description)
        precondition(reread.attribute(.underlineStyle, at: 0, effectiveRange: nil) != nil)
        var imageCount = 0
        reread.enumerateAttribute(.attachment, in: NSRange(location: 0, length: reread.length)) { value, _, _ in
            if value != nil { imageCount += 1 }
        }
        precondition(imageCount == 1)
        let v6 = TaskBackup(tasks: [task], statuses: statuses, projects: [project], disabledStatuses: [custom],
                            settings: ["dark": "true", "viewMode": "calendar"], workspaceID: "fixture-workspace", now: now)
        try write(v6.encoded(), "05-json-v6.json")
        for (backup, version) in [(v1, 1), (v2, 2), (v3, 3), (v4, 4), (v5, 5), (v6, 6)] {
            let decoded = try TaskBackup.decode(backup.encoded())
            precondition(decoded.version == version)
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Space-Interop-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let repository = TaskRepository(directory: temporary)
        _ = try repository.load()
        try repository.save(v6.tasks, statuses: v6.resolvedStatuses, projects: v6.resolvedProjects,
                            disabledStatuses: v6.resolvedDisabledStatuses, settings: v6.resolvedSettings)
        let snapshot = temporary.appendingPathComponent("synthetic-export.sqlite")
        try repository.exportSnapshot(to: snapshot)
        let database = try Data(contentsOf: snapshot)
        try write(Data(database.base64EncodedString().utf8), "06-synthetic-sqlite.base64.txt")
        let key = Data((0..<32).map { UInt8($0) }).base64EncodedString()
        let githubPacket = try GitHubSnapshotCodec.seal(v6, recoveryKey: key)
        let decodedGitHub = try GitHubSnapshotCodec.unseal(githubPacket, recoveryKey: key)
        precondition(decodedGitHub.tasks == v6.tasks)
        try write(Data(githubPacket.base64EncodedString().utf8), "07-github-packet.base64.txt")
        let code = "SP-0011-2233-4455-6677-8899-AABB-CCDD-EEFF"
        let spPacket = try DatabaseSync.seal(database, code: code, now: now)
        let decodedSP = try DatabaseSync.unseal(spPacket, code: code, now: now)
        precondition(decodedSP == database)
        try write(spPacket, "08-sp-envelope.json")
        try write(GitHubSnapshotCodec.portable(v6).encoded(), "09-github-portable.json")
        let facts: [String: Any] = [
            "syntheticOnly": true, "generatedBy": "actual OrbitCore 1.6.0 build10 + AppKit",
            "fixedNow": "2026-11-02T00:00:00.000Z", "testRecoveryKeyBase64": key, "testSPCode": code,
            "spExpiresAt": "2026-11-09T00:00:00.000Z", "spReceiptID": try DatabaseSync.receiptID(code),
            "githubFingerprint": try GitHubSnapshotCodec.fingerprint(v6), "sqliteSHA256": DatabaseSync.sha256(database),
            "sqliteBytes": database.count, "jsonV6TaskCount": 1, "jsonV6AttachmentCount": 2,
            "warning": "Public deterministic test key/code. Never use for real backups. SP vector must be verified at fixedNow because it expires."
        ]
        try write(JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), "EXPECTED.json")
        print("Generated and verified JSON 1/2/3/4/5/6, rich text, SQLite, GitHub and SP fixtures.")
    }
}
