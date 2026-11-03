import AppKit
import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
func read(_ name: String) throws -> NSAttributedString {
    let data = try Data(contentsOf: directory.appendingPathComponent(name))
    return try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
}
func inspect(_ text: NSAttributedString) -> [String: Any] {
    var bold = 0, underline = 0, images = 0
    text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
        if let font = attributes[.font] as? NSFont, NSFontManager.shared.traits(of: font).contains(.boldFontMask) { bold += range.length }
        if let value = attributes[.underlineStyle] as? Int, value != 0 { underline += range.length }
        if attributes[.attachment] != nil { images += 1 }
    }
    return ["text": text.string, "boldUnits": bold, "underlineUnits": underline, "images": images]
}
let original = try read("native-original.rtfd")
let flutter = try read("flutter-roundtrip.rtfd")
let a = inspect(original), b = inspect(flutter)
print("original:", String(reflecting: original.string)); print("flutter:", String(reflecting: flutter.string));
if original.string != flutter.string { print("DIFFERENT TEXT"); exit(1) }
precondition(a["images"] as! Int == b["images"] as! Int && b["images"] as! Int == 1, "Image count changed")
precondition(a["boldUnits"] as! Int == b["boldUnits"] as! Int, "Bold range changed")
precondition(a["underlineUnits"] as! Int == b["underlineUnits"] as! Int, "Underline range changed")
let output: [String: Any] = ["passed": true, "reader": "macOS AppKit NSAttributedString .rtfd", "original": a, "flutter": b]
let bytes = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
try bytes.write(to: directory.appendingPathComponent("appkit-result.json"))
print("PASS: Flutter RTFD reloaded by AppKit with identical text, image order, bold and underline ranges")
