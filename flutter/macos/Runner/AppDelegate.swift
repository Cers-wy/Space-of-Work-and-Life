import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    DispatchQueue.main.async { for case let window as MainFlutterWindow in NSApp.windows {
      window.title = "Space"; window.addSpaceMenus()
    } }
  }
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    MainFlutterWindow.mayDiscardEdits() ? .terminateNow : .terminateCancel
  }
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
