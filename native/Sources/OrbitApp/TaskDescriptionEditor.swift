import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLook
import OrbitCore

/// Native rich text with inline images; a plain text mirror supports search and previews.
struct TaskDescriptionTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var richText: Data?
    var attachments: [TaskAttachment]
    let dark: Bool
    let attach: ([TaskAttachment]) -> Void
    let reportError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        let editor = AttachmentPasteTextView()
        editor.isRichText = true; editor.importsGraphics = true; editor.allowsUndo = true
        editor.drawsBackground = false; editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.font = NSFont(name: "PingFangSC-Regular", size: 14)
        editor.delegate = context.coordinator; editor.setAccessibilityLabel("任务说明，支持粘贴图片和文件")
        scroll.documentView = editor
        updateNSView(scroll, context: context)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? AttachmentPasteTextView else { return }
        if context.coordinator.lastRichText != richText || editor.string != text {
            if let richText, let content = NSAttributedString(rtfd: richText, documentAttributes: nil) {
                editor.textStorage?.setAttributedString(content)
            } else { editor.string = text }
            context.coordinator.lastRichText = richText
        }
        editor.existingAttachments = attachments
        editor.textColor = NSColor(OrbitPalette(dark: dark).text)
        editor.insertionPointColor = NSColor(OrbitPalette(dark: dark).accent)
        editor.attach = attach; editor.reportError = reportError
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TaskDescriptionTextView
        var lastRichText: Data?
        init(_ parent: TaskDescriptionTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            guard let data = editor.rtfd(from: NSRange(location: 0, length: editor.textStorage?.length ?? 0)) else {
                parent.reportError("富文本暂时无法保存，请重试。"); return
            }
            lastRichText = data
            parent.richText = data
            parent.text = editor.string
        }
    }
}

final class AttachmentPasteTextView: NSTextView {
    var attach: (([TaskAttachment]) -> Void)?
    var existingAttachments: [TaskAttachment] = []
    var reportError: ((String) -> Void)?
    @objc func toggleBoldText(_ sender: Any?) {
        let range = selectedRange()
        let manager = NSFontManager.shared
        let current = (range.length > 0 ? textStorage?.attribute(.font, at: range.location, effectiveRange: nil) : typingAttributes[.font]) as? NSFont ?? NSFont.systemFont(ofSize: 14)
        let bold = manager.traits(of: current).contains(.boldFontMask)
        let font = bold ? manager.convert(current, toNotHaveTrait: .boldFontMask) : manager.convert(current, toHaveTrait: .boldFontMask)
        if range.length == 0 { typingAttributes[.font] = font }
        else if shouldChangeText(in: range, replacementString: nil) {
            textStorage?.addAttribute(.font, value: font, range: range); didChangeText()
        }
    }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "b" {
            toggleBoldText(nil); return
        }
        super.keyDown(with: event)
    }
    override func paste(_ sender: Any?) {
        let clipboard = NSPasteboard.general
        let urls = clipboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !pasteAttachments(fileURLs: urls, png: clipboard.data(forType: .png), tiff: clipboard.data(forType: .tiff)) { super.paste(sender) }
    }
    // Test media decoding without accessing the system clipboard or the user's current contents.
    @discardableResult
    func pasteAttachments(fileURLs urls: [URL] = [], png: Data? = nil, tiff: Data? = nil) -> Bool {
        if !urls.isEmpty {
            do { try insertMedia(TaskAttachmentFiles.read(urls)) }
            catch { reportError?(error.localizedDescription) }
            return true
        }
        if let data = png {
            do { try insertMedia([TaskAttachment(name: "粘贴图片-\(UUID().uuidString.prefix(8)).png", typeIdentifier: UTType.png.identifier, data: data)]) }
            catch { reportError?(error.localizedDescription) }
            return true
        }
        if let tiff, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) {
            do { try insertMedia([TaskAttachment(name: "粘贴图片-\(UUID().uuidString.prefix(8)).png", typeIdentifier: UTType.png.identifier, data: data)]) }
            catch { reportError?(error.localizedDescription) }
            return true
        }
        return false
    }
    private func insertMedia(_ media: [TaskAttachment]) throws {
        try TaskAttachment.validate(existingAttachments + media)
        let images = media.filter {
            UTType($0.typeIdentifier)?.conforms(to: .image) == true ||
            ["png", "jpg", "jpeg", "tif", "tiff", "gif", "heic", "webp", "bmp"].contains(URL(fileURLWithPath: $0.name).pathExtension.lowercased())
        }
        guard images.allSatisfy({ NSImage(data: $0.data) != nil }) else {
            throw OrbitError.invalid("无法读取粘贴的图片，请使用PNG或JPEG重试。")
        }
        // Validate the complete batch before changing the draft or the editor.
        attach?(media)
        for item in images where isRichText {
            let image = NSImage(data: item.data)!
            let scale = min(1, 480 / max(1, image.size.width), 240 / max(1, image.size.height))
            image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let wrapper = FileWrapper(regularFileWithContents: item.data); wrapper.preferredFilename = item.name
            let attachment = NSTextAttachment(fileWrapper: wrapper)
            attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
            let content = NSMutableAttributedString(attachment: attachment)
            content.append(NSAttributedString(string: "\n", attributes: typingAttributes))
            let range = selectedRange()
            if shouldChangeText(in: range, replacementString: content.string) {
                textStorage?.replaceCharacters(in: range, with: content)
                setSelectedRange(NSRange(location: range.location + content.length, length: 0))
                didChangeText()
            }
        }
    }

}

enum TaskAttachmentFiles {
    static func read(_ urls: [URL]) throws -> [TaskAttachment] {
        guard urls.count <= TaskAttachment.maximumCount else { throw OrbitError.invalid("每项任务最多添加20个附件。") }
        var result: [TaskAttachment] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard info.isRegularFile == true else { throw OrbitError.invalid("请选择文件，文件夹请先压缩后上传。") }
            guard (info.fileSize ?? 0) <= TaskAttachment.maximumFileBytes else { throw OrbitError.invalid("“\(url.lastPathComponent)”超过10 MB，请选择较小文件。") }
            result.append(TaskAttachment(name: url.lastPathComponent, typeIdentifier: (UTType(filenameExtension: url.pathExtension) ?? .data).identifier,
                                         data: try Data(contentsOf: url)))
            try TaskAttachment.validate(result)
        }
        return result
    }
}

struct TaskAttachmentList: View {
    @Binding var attachments: [TaskAttachment]
    let reportError: (String) -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var previewURL: URL?
    @State private var previewDirectory: URL?
    private var palette: OrbitPalette { OrbitPalette(dark: scheme == .dark) }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(attachments) { attachment in
                HStack(spacing: 12) {
                    Button { preview(attachment) } label: {
                        HStack(spacing: 12) {
                            if UTType(attachment.typeIdentifier)?.conforms(to: .image) == true,
                               let image = NSImage(data: attachment.data) {
                                Image(nsImage: image).resizable().scaledToFit().frame(width: 96, height: 64)
                                    .background(palette.card, in: RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "doc").font(.system(size: 20)).foregroundStyle(palette.accent)
                                    .frame(width: 32, height: 40)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(attachment.name).orbitFont(12).lineLimit(2).multilineTextAlignment(.leading)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                                    .orbitFont(12).foregroundStyle(palette.muted)
                            }
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).help("预览“\(attachment.name)”").accessibilityLabel("预览附件 \(attachment.name)")
                    OrbitIconButton(symbol: "square.and.arrow.down", label: "另存附件 \(attachment.name)", compact: true) { export(attachment) }
                    OrbitIconButton(symbol: "xmark", label: "移除附件 \(attachment.name)", compact: true) {
                        attachments.removeAll { $0.id == attachment.id }
                    }
                }.padding(8).glass(palette)
            }
        }
        .quickLookPreview($previewURL)
        .onDisappear { cleanupPreview() }
    }
    private func preview(_ attachment: TaskAttachment) {
        do {
            let directory: URL
            if let existing = previewDirectory { directory = existing }
            else {
                directory = FileManager.default.temporaryDirectory.appendingPathComponent("Space-Preview-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                previewDirectory = directory
            }
            // Attachment IDs from imported backups are metadata, never filesystem paths.
            let safeDirectory = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: safeDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = safeDirectory.appendingPathComponent(attachment.name)
            try attachment.data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            previewURL = url
        } catch { reportError("无法预览附件：\(error.localizedDescription)") }
    }
    private func export(_ attachment: TaskAttachment) {
        let panel = NSSavePanel(); panel.title = "另存附件"; panel.prompt = "保存"
        panel.nameFieldStringValue = attachment.name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try attachment.data.write(to: url, options: .atomic) }
        catch { reportError("附件保存失败：\(error.localizedDescription)") }
    }
    private func cleanupPreview() {
        previewURL = nil
        if let directory = previewDirectory { try? FileManager.default.removeItem(at: directory) }
        previewDirectory = nil
    }
}
