import AppKit
import CoreGraphics
import FlutterMacOS
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum SpaceInvoicePDF {
  private static let worker = DispatchQueue(label: "com.cers.space.invoice-pdf", qos: .userInitiated)

  static func handle(_ method: String, _ arguments: [String: Any], _ result: @escaping FlutterResult) {
    if method == "invoicePrint" {
      do {
        try printPDF(arguments)
        result(nil)
      } catch {
        fail(error, result)
      }
      return
    }
    worker.async {
      do {
        let value = try autoreleasepool { try execute(method, arguments) }
        DispatchQueue.main.async { result(value) }
      } catch {
        DispatchQueue.main.async { fail(error, result) }
      }
    }
  }

  private static func fail(_ error: Error, _ result: FlutterResult) {
    result(FlutterError(code: "invoice_pdf", message: error.localizedDescription, details: nil))
  }

  private struct Failure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
  }

  private static func execute(_ method: String, _ a: [String: Any]) throws -> Any? {
    switch method {
    case "invoiceInspect":
      let source = try Source(path(a))
      let trim = a["trim"] as? Bool ?? false
      return try (1...source.count).map { index in
        try autoreleasepool {
          let page = try source.page(index)
          let box = trim ? try contentBounds(page) : page.box
          return [Double(box.minX), Double(box.minY), Double(box.width), Double(box.height)]
        }
      }
    case "invoicePreview":
      let source = try Source(path(a))
      let page = try source.page(a["page"] as? Int ?? 1)
      let data = try thumbnail(page.box, limit: 900) { page.draw(in: $0) }
      return ["pages": source.count, "bytes": FlutterStandardTypedData(bytes: data)]
    case "invoiceRender":
      guard let sheet = a["sheet"] as? [String: Any] else { throw Failure("缺少预览页") }
      let size = try paper(sheet)
      let data = try thumbnail(size, limit: 880) { try draw(sheet, in: $0) }
      return FlutterStandardTypedData(bytes: data)
    case "invoiceWrite":
      guard let sheets = a["sheets"] as? [[String: Any]], let first = sheets.first else {
        throw Failure("没有可保存的发票")
      }
      let url = URL(fileURLWithPath: try path(a))
      var bounds = try paper(first)
      guard let pdf = CGContext(url as CFURL, mediaBox: &bounds, nil) else {
        throw Failure("无法创建 PDF 文件")
      }
      defer { pdf.closePDF() }
      for sheet in sheets {
        try autoreleasepool {
          pdf.beginPDFPage(nil)
          defer { pdf.endPDFPage() }
          try draw(sheet, in: pdf)
        }
      }
      return nil
    default:
      return FlutterMethodNotImplemented
    }
  }

  private static func path(_ a: [String: Any]) throws -> String {
    guard let value = a["path"] as? String, !value.isEmpty else { throw Failure("缺少文件路径") }
    return value
  }

  private enum Content {
    case pdf(CGPDFPage)
    case image(CGImage)

    var box: CGRect {
      switch self {
      case .pdf(let page):
        let box = page.getBoxRect(.cropBox)
        return abs(page.rotationAngle % 180) == 90
          ? CGRect(x: 0, y: 0, width: box.height, height: box.width)
          : CGRect(x: 0, y: 0, width: box.width, height: box.height)
      case .image(let image):
        return CGRect(x: 0, y: 0, width: image.width, height: image.height)
      }
    }

    func draw(in context: CGContext) {
      switch self {
      case .pdf(let page):
        context.saveGState()
        context.concatenate(page.getDrawingTransform(.cropBox, rect: box, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        context.restoreGState()
      case .image(let image):
        context.draw(image, in: box)
      }
    }
  }

  private struct Source {
    let pdf: CGPDFDocument?
    let image: CGImage?
    let name: String
    var count: Int { pdf?.numberOfPages ?? 1 }

    init(_ path: String) throws {
      let url = URL(fileURLWithPath: path)
      name = url.lastPathComponent
      if url.pathExtension.lowercased() == "pdf" {
        guard let doc = CGPDFDocument(url as CFURL), doc.isUnlocked, doc.numberOfPages > 0 else {
          throw Failure("无法打开 PDF，文件可能已损坏或加密：\(name)")
        }
        pdf = doc
        image = nil
      } else {
        let options = [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 2600,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let raster = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
          throw Failure("无法打开图片：\(name)")
        }
        image = raster
        pdf = nil
      }
    }

    func page(_ index: Int) throws -> Content {
      let content: Content
      if let pdf, let page = pdf.page(at: index) {
        content = .pdf(page)
      } else if let image, index == 1 {
        content = .image(image)
      } else {
        throw Failure("无法读取第 \(index) 页：\(name)")
      }
      let bounds = content.box
      guard bounds.width.isFinite, bounds.height.isFinite, bounds.width >= 1, bounds.height >= 1 else {
        throw Failure("页面尺寸无效：\(name)")
      }
      return content
    }
  }

  private static func paper(_ sheet: [String: Any]) throws -> CGRect {
    guard let w = sheet["width"] as? Double, let h = sheet["height"] as? Double,
          (100...1000).contains(w), (100...1000).contains(h) else { throw Failure("纸张尺寸无效") }
    return CGRect(x: 0, y: 0, width: w, height: h)
  }

  private static func rectangle(_ values: Any?) throws -> CGRect {
    guard let v = values as? [Double], v.count == 4,
          v.allSatisfy({ $0.isFinite }), v[2] > 0, v[3] > 0 else { throw Failure("票面位置无效") }
    return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
  }

  private static func draw(_ sheet: [String: Any], in context: CGContext) throws {
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(try paper(sheet))
    for slot in sheet["slots"] as? [[String: Any]] ?? [] {
      let source = try Source(path(slot))
      let page = try source.page(slot["page"] as? Int ?? 1)
      let crop = try rectangle(slot["crop"])
      let position = try rectangle(slot["rect"])
      context.saveGState()
      context.clip(to: position)
      context.translateBy(x: position.minX, y: position.minY)
      context.scaleBy(x: position.width / crop.width, y: position.height / crop.height)
      context.translateBy(x: -crop.minX, y: -crop.minY)
      page.draw(in: context)
      context.restoreGState()
    }
    context.setStrokeColor(CGColor(gray: 0.58, alpha: 1))
    context.setLineWidth(0.5)
    context.setLineDash(phase: 0, lengths: [4, 3])
    for line in sheet["lines"] as? [[Double]] ?? [] where line.count == 4 {
      context.move(to: CGPoint(x: line[0], y: line[1]))
      context.addLine(to: CGPoint(x: line[2], y: line[3]))
    }
    context.strokePath()
  }

  private static func raster(
    _ box: CGRect, limit: CGFloat, draw: (CGContext) throws -> Void
  ) throws -> (CGContext, CGFloat) {
    let scale = limit / max(box.width, box.height)
    let width = max(1, Int(ceil(box.width * scale)))
    let height = max(1, Int(ceil(box.height * scale)))
    let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: info) else { throw Failure("无法生成预览") }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: scale, y: scale)
    try draw(context)
    return (context, scale)
  }

  private static func thumbnail(
    _ box: CGRect, limit: CGFloat, draw: (CGContext) throws -> Void
  ) throws -> Data {
    let (context, _) = try raster(box, limit: limit, draw: draw)
    let data = NSMutableData()
    guard let image = context.makeImage(),
          let encoder = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
      throw Failure("无法编码预览")
    }
    CGImageDestinationAddImage(encoder, image, nil)
    guard CGImageDestinationFinalize(encoder) else { throw Failure("无法保存预览") }
    return data as Data
  }

  private static func contentBounds(_ page: Content) throws -> CGRect {
    if case .image = page { return page.box }
    let (context, scale) = try raster(page.box, limit: 560) { page.draw(in: $0) }
    guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return page.box }
    let width = context.width, height = context.height
    // 先用逐行、逐列投影找出真实票面：零星噪点、极细的页脚小字不参与边界计算，
    // 否则会像整页排版那样把大片空白算进发票高度，票面被压小。
    var rowHits = [Int](repeating: 0, count: height)
    var colHits = [Int](repeating: 0, count: width)
    for row in 0..<height {
      let pixels = bytes + row * context.bytesPerRow
      for x in 0..<width {
        let p = pixels + x * 4
        if p[0] < 242 || p[1] < 242 || p[2] < 242 {
          rowHits[row] += 1
          colHits[x] += 1
        }
      }
    }
    let rowFloor = max(2, width / 100)
    let colFloor = max(2, height / 100)
    let rows = (0..<height).filter { rowHits[$0] >= rowFloor }
    let columns = (0..<width).filter { colHits[$0] >= colFloor }
    guard let firstRow = rows.first, let lastRow = rows.last,
          let firstColumn = columns.first, let lastColumn = columns.last else {
      return page.box
    }
    let bounds = CGRect(x: CGFloat(firstColumn) / scale,
                        y: CGFloat(height - lastRow - 1) / scale,
                        width: CGFloat(lastColumn - firstColumn + 1) / scale,
                        height: CGFloat(lastRow - firstRow + 1) / scale)
    return page.box.intersection(bounds.insetBy(dx: -2, dy: -2))
  }

  private static func printPDF(_ a: [String: Any]) throws {
    let url = URL(fileURLWithPath: try path(a))
    let bounds = try paper(a)
    let landscape = a["landscape"] as? Bool ?? false
    let info = NSPrintInfo()
    info.paperSize = landscape ? NSSize(width: bounds.height, height: bounds.width) : bounds.size
    info.orientation = landscape ? .landscape : .portrait
    info.topMargin = 0
    info.bottomMargin = 0
    info.leftMargin = 0
    info.rightMargin = 0
    guard let document = PDFDocument(url: url),
          let operation = document.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: false) else {
      throw Failure("无法打开打印面板")
    }
    operation.jobTitle = "发票合并"
    operation.showsPrintPanel = true
    operation.showsProgressPanel = true
    operation.run()
  }
}
