import XCTest
import AppKit
import OrbitCore
@testable import OrbitApp

@MainActor
final class RichDescriptionTests: XCTestCase {
    func testInlinePasteAtCaretAndRTFDRoundTripThroughDatabaseAndJSON() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.setColor(.red, atX: 0, y: 0)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let editor = AttachmentPasteTextView(); editor.isRichText = true
        editor.string = "前后"; editor.setSelectedRange(NSRange(location: 1, length: 0))
        var media: [TaskAttachment] = []; editor.attach = { media += $0 }
        XCTAssertTrue(editor.pasteAttachments(png: png))
        XCTAssertEqual(editor.string, "前\u{FFFC}\n后")
        XCTAssertNotNil(editor.textStorage?.attribute(.attachment, at: 1, effectiveRange: nil))
        editor.setSelectedRange(NSRange(location: 0, length: 1)); editor.toggleBoldText(nil)
        let rich = try XCTUnwrap(editor.rtfd(from: NSRange(location: 0, length: editor.string.utf16.count)))
        var task = OrbitTask(title: "图文任务", description: editor.string, attachments: media)
        task.richDescription = rich
        let backup = TaskBackup(tasks: [task]); XCTAssertEqual(backup.version, 6)
        let decoded = try TaskBackup.decode(backup.encoded()).tasks[0]
        let content = try XCTUnwrap(NSAttributedString(rtfd: try XCTUnwrap(decoded.richDescription), documentAttributes: nil))
        XCTAssertEqual(content.string, editor.string)
        XCTAssertNotNil(content.attribute(.attachment, at: 1, effectiveRange: nil))
        let font = try XCTUnwrap(content.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TaskRepository(directory: directory); _ = try repository.load(); try repository.save([task])
        XCTAssertEqual(try TaskRepository(directory: directory).load(), [task])
        let snapshot = directory.appendingPathComponent("rich.sqlite"); try repository.exportSnapshot(to: snapshot)
        XCTAssertEqual(try TaskRepository.readBackup(at: snapshot).tasks, [task])
        var downgraded = backup; downgraded.version = 5
        XCTAssertThrowsError(try TaskBackup.decode(downgraded.encoded()))
        XCTAssertEqual(TaskQuery().apply(to: [task], projectNames: [:]).count, 1)
        var changed = task; changed.richDescription = nil
        XCTAssertNotEqual(try GitHubSnapshotCodec.fingerprint(backup), try GitHubSnapshotCodec.fingerprint(TaskBackup(tasks: [changed])))
    }
    func testRejectedMediaDoesNotChangeTextOrDraft() {
        let editor = AttachmentPasteTextView(); editor.isRichText = true; editor.string = "保留正文"
        var called = false; editor.attach = { _ in called = true }
        var error: String?; editor.reportError = { error = $0 }
        XCTAssertTrue(editor.pasteAttachments(png: Data([1, 2, 3])))
        XCTAssertFalse(called); XCTAssertNotNil(error); XCTAssertEqual(editor.string, "保留正文")
    }
}
