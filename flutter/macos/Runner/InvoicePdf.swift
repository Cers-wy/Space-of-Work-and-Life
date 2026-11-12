import AppKit
import FlutterMacOS
import PDFKit

// PDF inspection, cropping, rendering and composition use the shared PDFium
// engine in Dart. macOS only presents its native print panel for the final PDF.
enum SpaceInvoicePDF {
  static func handle(_ method: String, _ arguments: [String: Any], _ result: @escaping FlutterResult) {
    guard method == "invoicePrint" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let path = arguments["path"] as? String,
          let width = arguments["width"] as? Double,
          let height = arguments["height"] as? Double,
          width.isFinite, height.isFinite,
          (100...1000).contains(width), (100...1000).contains(height),
          let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
      result(FlutterError(code: "invoice_pdf", message: "无法打开打印文件", details: nil))
      return
    }
    let landscape = arguments["landscape"] as? Bool ?? false
    let info = NSPrintInfo()
    info.paperSize = landscape ? NSSize(width: height, height: width) : NSSize(width: width, height: height)
    info.orientation = landscape ? .landscape : .portrait
    info.topMargin = 0
    info.bottomMargin = 0
    info.leftMargin = 0
    info.rightMargin = 0
    guard let operation = document.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: false) else {
      result(FlutterError(code: "invoice_pdf", message: "无法打开打印面板", details: nil))
      return
    }
    operation.jobTitle = "发票合并"
    operation.showsPrintPanel = true
    operation.showsProgressPanel = true
    operation.run()
    result(nil)
  }
}
