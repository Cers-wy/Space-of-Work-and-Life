import Cocoa
import Vision
import FlutterMacOS
import Security
import Quartz
import LocalAuthentication
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var menuEnabled:[String:Bool] = [:]
  override func validateMenuItem(_ item:NSMenuItem)->Bool {
    guard let action=item.representedObject as? String else {return super.validateMenuItem(item)}
    return menuEnabled[action] ?? true
  }
  private var desktopChannel: FlutterMethodChannel?
  private var menusInstalled = false
  func windowDidBecomeKey(_ notification: Notification) { title = "Space"; addSpaceMenus() }
  static var hasUnsavedEdits = false
  static var uploadsActive = false
  private var previewController: SpacePreview?
  func windowShouldClose(_ sender: NSWindow) -> Bool { Self.mayDiscardEdits() }
  static func mayDiscardEdits() -> Bool {
    if uploadsActive {
      (NSApp.windows.first(where: { $0 is MainFlutterWindow }) as? MainFlutterWindow)?.desktopChannel?.invokeMethod("requestClose", arguments: nil)
      return false
    }
    guard hasUnsavedEdits else { return true }
    let alert = NSAlert(); alert.messageText = "放弃未保存的更改？"; alert.informativeText = "当前输入和附件尚未保存。"; alert.addButton(withTitle: "保留编辑"); alert.addButton(withTitle: "放弃更改")
    return alert.runModal() == .alertSecondButtonReturn
  }
  override func awakeFromNib() {
    let controller = FlutterViewController()
    contentViewController = controller
    title = "Space"
    titlebarAppearsTransparent = true
    setFrame(NSRect(x: 0, y: 0, width: 1380, height: 860), display: false)
    contentMinSize = NSSize(width: 1020, height: 640)
    center()
    RegisterGeneratedPlugins(registry: controller)
    let channel = FlutterMethodChannel(name: "com.cers.space/desktop", binaryMessenger: controller.engine.binaryMessenger)
    desktopChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      let a = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "menuState":
        self.updateMenuState(a); result(nil)
      case "diagnostics":
        result(["title": self.title, "windowClass": String(describing: type(of:self)), "frameWidth":self.frame.width, "frameHeight":self.frame.height, "scale":self.backingScaleFactor, "menus":NSApp.mainMenu?.items.map(\.title) ?? [], "appActive":NSApp.isActive, "windowKey":self.isKeyWindow, "frontmostPid":NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1])
      case "accessibility":
        self.title = "Space"; self.addSpaceMenus()
        result(["reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency])
      case "appearance":
        let dark = a["dark"] as? Bool ?? false
        self.appearance = a["system"] as? Bool == true ? nil : NSAppearance(named: dark ? .darkAqua : .aqua)
        self.backgroundColor = dark ? .black : .windowBackgroundColor
        result(nil)
      case "systemAppearance":
        result(NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
      case "appInfo":
        result(["version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""])
      case "openExternal":
        guard let value = a["url"] as? String, let url = URL(string: value),
              ["https", "mailto"].contains(url.scheme?.lowercased() ?? "") else { result(false); return }
        result(NSWorkspace.shared.open(url))
      case "driveState":
        MainFlutterWindow.uploadsActive = a["active"] as? Bool ?? false; result(nil)
      case "finishClose":
        MainFlutterWindow.uploadsActive = false; result(nil); NSApp.terminate(nil)
      case "openFolder":
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: self) { response in result(response == .OK ? panel.url?.path : nil) }
      case "dirty":
        MainFlutterWindow.hasUnsavedEdits = a["dirty"] as? Bool ?? false
        result(nil)
      case "openFiles":
        let panel = SpaceFilePanels.open(sqliteOnly: a["sqliteOnly"] as? Bool ?? false,
                                         multiple: a["multiple"] as? Bool ?? false,
                                         title: a["title"] as? String, extensions: a["extensions"] as? [String] ?? [])
        panel.beginSheetModal(for: self) { response in result(response == .OK ? panel.urls.map(\.path) : []) }
      case "saveFile":
        let panel = SpaceFilePanels.save(name: a["name"] as? String ?? "Space备份.sqlite",
                                         sqliteOnly: a["sqliteOnly"] as? Bool ?? false, title: a["title"] as? String)
        panel.beginSheetModal(for: self) { response in result(response == .OK ? panel.url?.path : nil) }
      case "recognizeInvoiceImage":
        guard let path = a["path"] as? String else { result(FlutterError(code: "ocr", message: "图片路径无效", details: nil)); return }
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.004
            try VNImageRequestHandler(url: URL(fileURLWithPath: path), options: [:]).perform([request])
            let lines = (request.results ?? []).sorted { left, right in
              if abs(left.boundingBox.midY - right.boundingBox.midY) > 0.008 { return left.boundingBox.midY > right.boundingBox.midY }
              return left.boundingBox.minX < right.boundingBox.minX
            }.compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async { result(lines.joined(separator: "\n")) }
          } catch { DispatchQueue.main.async { result(FlutterError(code: "ocr", message: "本地识别失败：\(error.localizedDescription)", details: nil)) } }
        }
      case "invoiceInspect", "invoicePreview", "invoiceRender", "invoiceWrite", "invoicePrint":
        SpaceInvoicePDF.handle(call.method, a, result)
      case "reveal":
        if let path = a["path"] as? String { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }; result(nil)
      case "preview":
        if let path = a["path"] as? String {
          let url = path.hasPrefix("https://") ? URL(string: path) : URL(fileURLWithPath: path)
          if let url {
            if url.isFileURL {
              let preview = SpacePreview(url: url); self.previewController = preview
              if let panel = QLPreviewPanel.shared() { panel.dataSource = preview; panel.delegate = preview; panel.reloadData(); panel.makeKeyAndOrderFront(nil) }
            } else { NSWorkspace.shared.open(url) }
          }
        }; result(nil)
      case "clipboardFiles":
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        result(urls.map(\.path))
      case "clipboardImage":
        if let data = NSPasteboard.general.data(forType: .png) { result(FlutterStandardTypedData(bytes: data)) }
        else if let image = NSImage(pasteboard: .general), let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) { result(FlutterStandardTypedData(bytes: png)) }
        else { result(nil) }
      case "readSecret":
        guard let id = a["id"] as? String else { result(FlutterError(code: "invalid", message: "凭据标识无效", details: nil)); return }
        // Keychain 可能等待系统认证，不能占用 AppKit/Flutter 主线程。
        DispatchQueue.global(qos: .userInitiated).async {
          let authentication = LAContext(); authentication.interactionNotAllowed = true
          let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.cers.space.flutter", kSecAttrAccount as String: id, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne, kSecUseAuthenticationContext as String: authentication]
          var value: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &value)
          let text = (value as? Data).flatMap { String(data: $0, encoding: .utf8) }
          DispatchQueue.main.async {
            if status == errSecSuccess { result(text) }
            else if status == errSecItemNotFound { result(nil) }
            else { result(FlutterError(code: "keychain", message: "无法读取本机钥匙串", details: nil)) }
          }
        }
      case "writeSecret":
        guard let id = a["id"] as? String, let value = (a["value"] as? String)?.data(using: .utf8) else { result(FlutterError(code: "invalid", message: "凭据无效", details: nil)); return }
        DispatchQueue.global(qos: .userInitiated).async {
          let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.cers.space.flutter", kSecAttrAccount as String: id]
          let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
          var status = update
          if update == errSecItemNotFound { var add = query; add[kSecValueData as String] = value; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly; status = SecItemAdd(add as CFDictionary, nil) }
          let saved = status == errSecSuccess
          DispatchQueue.main.async {
            if saved { result(nil) } else { result(FlutterError(code: "keychain", message: "无法保存到本机钥匙串", details: nil)) }
          }
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.desktopChannel?.invokeMethod("accessibilityChanged", arguments: nil) }
    DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
      self?.desktopChannel?.invokeMethod("systemAppearanceChanged", arguments: nil)
    }
    delegate = self
    super.awakeFromNib()
    title = "Space"
  }
  private func updateMenuState(_ state:[String:Any]) {
    let modal=state["modal"] as? Bool ?? false
    let loaded=state["loaded"] as? Bool ?? false
    let area = state["area"] as? String ?? "tasks"
    let taskActions: Set<String> = ["new", "statuses", "overview", "board", "list", "gantt", "calendar", "reload"]
    func update(_ menu:NSMenu) {
      for item in menu.items {
        if let action=item.representedObject as? String {
          item.isEnabled = !modal
          if action == "new" || action == "statuses" { item.isEnabled = loaded && !modal }
          if action == "undo" { item.isEnabled = modal || (area == "tasks" && (state["canUndo"] as? Bool ?? false)) || NSApp.keyWindow?.firstResponder is NSTextView }
          if taskActions.contains(action) && area != "tasks" { item.isEnabled = false }
          if action == "search" {
            item.isEnabled = !modal && area != "tools"
            item.title = area == "invoices" ? "搜索发票" : "搜索任务"
          }
          menuEnabled[action]=item.isEnabled
          if action == "nav" {item.title = (state["navCollapsed"] as? Bool ?? true) ? "展开导航":"收起导航"}
          if action == "overview" {item.title = (state["overviewCollapsed"] as? Bool ?? false) ? "展开概览":"收起概览"}
          if action == "theme" {item.title = (state["dark"] as? Bool ?? false) ? "切换明亮主题":"切换暗色主题"}
        }
        if let sub=item.submenu { update(sub) }
      }
    }
    if let menu=NSApp.mainMenu {update(menu)}
  }
  @objc func performSpaceAction(_ sender: NSMenuItem) {
    if let action = sender.representedObject as? String {
      if action == "undo", NSApp.keyWindow?.firstResponder is NSTextView { NSApp.sendAction(Selector(("undo:")),to:nil,from:sender); return }
      desktopChannel?.invokeMethod("shortcut", arguments: action)
    }
  }
  func addSpaceMenus() {
    guard !menusInstalled, let menu=NSApp.mainMenu else { return }
    menusInstalled = true
    func add(_ title:String,_ entries:[(String,String,String)]) {
      let item=NSMenuItem(title:title,action:nil,keyEquivalent:"");let submenu=NSMenu(title:title)
      for (name,action,key) in entries { let entry=NSMenuItem(title:name,action:#selector(performSpaceAction(_:)),keyEquivalent:key);entry.target=self;entry.representedObject=action;entry.keyEquivalentModifierMask = .command;submenu.addItem(entry) }
      item.submenu=submenu;menu.insertItem(item,at:min(menu.items.count, title=="文件" ? 1:4))
    }
    add("文件",[("新建任务","new","n")])
    add("工作台",[("状态与分类管理…","statuses",""),("看板视图","board","1"),("列表视图","list","2"),("甘特图视图","gantt","3"),("日历视图","calendar","4"),("展开或收起导航","nav",""),("展开或收起概览","overview",""),("切换主题","theme",""),("重新载入任务","reload","")])
    func entry(_ name:String,_ action:String,_ key:String)->NSMenuItem { let item=NSMenuItem(title:name,action:#selector(performSpaceAction(_:)),keyEquivalent:key);item.target=self;item.representedObject=action;item.keyEquivalentModifierMask = .command;return item }
    if let app=menu.items.first?.submenu { app.insertItem(entry("数据与设置…","settings",","),at:min(2,app.items.count)) }
    if let edit=menu.items.first(where:{$0.title=="编辑"})?.submenu {
      for item in edit.items where item.action == Selector(("undo:")) || item.action == Selector(("redo:")) { edit.removeItem(item) }
      edit.insertItem(entry("撤销","undo","z"),at:0);edit.addItem(.separator());edit.addItem(entry("搜索任务","search","f"))
    }
    if let help=menu.items.first(where:{$0.title=="帮助"})?.submenu { help.removeAllItems();help.addItem(entry("Space 使用帮助","help","")) }

  }

}

private class SpacePreview: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
  let url: URL
  init(url:URL) { self.url=url }
  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }
  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { url as NSURL }
}
