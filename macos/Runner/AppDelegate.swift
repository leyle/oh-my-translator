import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Return false to keep app running when window is hidden
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Handle dock icon click when app is already running
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      // No visible windows, show the main window
      for window in sender.windows {
        if window is MainFlutterWindow {
          window.makeKeyAndOrderFront(self)
          break
        }
      }
    }
    return true
  }
}
