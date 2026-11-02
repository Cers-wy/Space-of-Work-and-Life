import XCTest
@testable import OrbitCore

final class AttachmentTests: XCTestCase {
    private func folder() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    private let image = TaskAttachment(name: "截图.png", typeIdentifier: "public.png", data: Data([137, 80, 78, 71, 0, 255]))
    private let file = TaskAttachment(name: "需求说明.txt", typeIdentifier: "public.plain-text", data: Data("中文附件\n具体要求".utf8))

    func testLegacyTasksWithoutAttachmentsStillDecodeAndExportAsV1() throws {
        let task = OrbitTask(title: "原有任务")
        let data = try TaskBackup(tasks: [task]).encoded()
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("attachments"))
        let backup = try TaskBackup.decode(data)
        XCTAssertEqual(backup.version, 1)
        XCTAssertEqual(backup.tasks[0].attachments, [])
    }
    func testV4RoundTripPreservesAttachmentBytesAndRefusesVersionDowngrade() throws {
        let task = OrbitTask(title: "含图与附件", description: "正文", attachments: [image, file])
        let backup = TaskBackup(tasks: [task])
        XCTAssertEqual(backup.version, 4)
        XCTAssertEqual(try TaskBackup.decode(backup.encoded()).tasks, [task])
        var downgraded = backup; downgraded.version = 3
        XCTAssertThrowsError(try TaskBackup.decode(downgraded.encoded()))
    }
    func testAttachmentValidationBlocksTraversalDuplicatesAndLimits() throws {
        for name in ["../escape.png", "..", ".", "a/b", "a\\b", "a\nb", ""] {
            XCTAssertThrowsError(try TaskAttachment.validate([TaskAttachment(name: name, typeIdentifier: "public.data", data: Data())]))
        }
        XCTAssertThrowsError(try TaskAttachment.validate([image, image]))
        XCTAssertThrowsError(try TaskAttachment.validate((0..<21).map { _ in TaskAttachment(name: "x", typeIdentifier: "public.data", data: Data()) }))
        let big = Data(repeating: 0, count: TaskAttachment.maximumFileBytes)
        let one = TaskAttachment(name: "a", typeIdentifier: "public.data", data: big)
        let two = TaskAttachment(name: "b", typeIdentifier: "public.data", data: big)
        XCTAssertNoThrow(try TaskAttachment.validate([one, two]))
        XCTAssertThrowsError(try TaskAttachment.validate([one, two, file]))
        XCTAssertThrowsError(try TaskAttachment.validate([TaskAttachment(name: "too big", typeIdentifier: "public.data", data: big + Data([0]))]))
    }
    func testSQLiteReopenSnapshotAndPreviousBackupKeepIndependentAttachmentCopies() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let source = TaskRepository(directory: directory); _ = try source.load()
        var task = OrbitTask(title: "附件持久化", attachments: [image, file])
        try source.save([task])
        XCTAssertEqual(try TaskRepository(directory: directory).load().first?.attachments, [image, file])
        let snapshot = directory.appendingPathComponent("snapshot.sqlite")
        try source.exportSnapshot(to: snapshot)
        task.attachments.removeAll(); try source.save([task])
        XCTAssertEqual(try TaskRepository.readBackup(at: source.previousURL).tasks.first?.attachments, [image, file])
        XCTAssertEqual(try TaskRepository.readBackup(at: snapshot).tasks.first?.attachments, [image, file])
        let restored = try TaskRepository.readBackup(at: snapshot)
        try source.save(restored.tasks)
        XCTAssertEqual(try TaskRepository(directory: directory).load(), restored.tasks)
    }
    func testAttachmentBackupBeyondOldTwelveMegabyteLimitRoundTrips() throws {
        let attachment = TaskAttachment(name: "large.bin", typeIdentifier: "public.data", data: Data(repeating: 1, count: 10 * 1024 * 1024))
        let data = try TaskBackup(tasks: [OrbitTask(title: "较大附件", attachments: [attachment])]).encoded()
        XCTAssertGreaterThan(data.count, 12 * 1024 * 1024)
        XCTAssertEqual(try TaskBackup.decode(data).tasks[0].attachments, [attachment])
    }
    func testEncryptedLocalSyncAndMergeRetainAttachments() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let remote = directory.appendingPathComponent("remote"); try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        let source = TaskRepository(directory: directory.appendingPathComponent("source")); _ = try source.load()
        let task = OrbitTask(title: "同步附件", attachments: [image, file]); try source.save([task])
        let snapshot = directory.appendingPathComponent("snapshot.sqlite"); try source.exportSnapshot(to: snapshot)
        let config = SyncConfiguration(location: remote.path)
        let receipt = try await DatabaseSync.upload(snapshot: snapshot, configuration: config)
        let downloaded = try await DatabaseSync.download(code: receipt.code, configuration: config)
        let merged = try DatabaseSync.merge(local: TaskBackup(tasks: []), remote: downloaded.backup)
        XCTAssertEqual(merged.tasks, [task])
        XCTAssertEqual(try TaskBackup.decode(merged.encoded()).tasks[0].attachments, [image, file])
    }
}
