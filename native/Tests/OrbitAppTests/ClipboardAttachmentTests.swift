import XCTest
import AppKit
import OrbitCore
@testable import OrbitApp

@MainActor
final class ClipboardAttachmentTests: XCTestCase {
    private func imageBytes(_ type: NSBitmapImageRep.FileType) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.setColor(.red, atX: 0, y: 0)
        return try XCTUnwrap(bitmap.representation(using: type, properties: [:]))
    }
    func testPNGClipboardBecomesAttachmentAndInlineImage() throws {
        let bytes = try imageBytes(.png)
        let view = AttachmentPasteTextView(); view.string = "说明正文"
        var result: [TaskAttachment] = []; view.attach = { result = $0 }
        XCTAssertTrue(view.pasteAttachments(png: bytes))
        XCTAssertEqual(result.count, 1); XCTAssertEqual(try XCTUnwrap(result.first).data, bytes)
        XCTAssertEqual(result[0].typeIdentifier, "public.png")
        XCTAssertTrue(view.string.contains("说明正文"))
        XCTAssertTrue(view.string.contains("\u{FFFC}"))
    }
    func testTIFFScreenshotClipboardConvertsToPNG() throws {
        let bytes = try imageBytes(.tiff)
        let view = AttachmentPasteTextView(); var result: [TaskAttachment] = []; view.attach = { result = $0 }
        XCTAssertTrue(view.pasteAttachments(tiff: bytes))
        XCTAssertEqual(result.count, 1); XCTAssertNotNil(NSImage(data: result[0].data))
        XCTAssertEqual(result[0].typeIdentifier, "public.png")
    }
    func testPlainTextUsesNormalTextPasteAndFileURLsCopyBytes() throws {
        let view = AttachmentPasteTextView(); XCTAssertFalse(view.pasteAttachments())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data("文件剪贴板".utf8); try bytes.write(to: url)
        var result: [TaskAttachment] = []; view.attach = { result = $0 }
        var error: String?; view.reportError = { error = $0 }
        XCTAssertTrue(view.pasteAttachments(fileURLs: [url])); XCTAssertNil(error)
        XCTAssertEqual(result.first?.data, bytes)
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(result.first?.data, bytes)
    }
}
