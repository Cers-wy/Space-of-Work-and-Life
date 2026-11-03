import Cocoa
import UniformTypeIdentifiers

enum SpaceLanguage {
  static func prepareBeforeApplicationLaunch() {
    // The app has a Chinese UI. Set its own language before AppKit or the
    // out-of-process file panel service caches a language. No global defaults.
    UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
  }
}

enum SpaceFilePanels {
  static func open(sqliteOnly: Bool, multiple: Bool) -> NSOpenPanel {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = multiple
    panel.title = sqliteOnly ? "导入SQLite备份" : "选择附件"
    panel.prompt = sqliteOnly ? "导入" : "选择"
    if sqliteOnly {
      panel.allowedContentTypes = databaseTypes
    }
    return panel
  }

  static func save(name: String, sqliteOnly: Bool) -> NSSavePanel {
    let panel = NSSavePanel()
    panel.title = sqliteOnly ? "导出SQLite备份" : "另存附件"
    panel.nameFieldLabel = "存储为："
    panel.nameFieldStringValue = name
    panel.prompt = "保存"
    if sqliteOnly {
      panel.allowedContentTypes = databaseTypes
    }
    return panel
  }

  private static var databaseTypes: [UTType] {
    ["sqlite", "sqlite3", "db"].compactMap { UTType(filenameExtension: $0) }
  }
}
