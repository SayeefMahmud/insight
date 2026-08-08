import Cocoa
import CoreGraphics
import FlutterMacOS
import ServiceManagement
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // launch_at_startup ships no macOS implementation of its own; it expects
    // the app to handle its "launch_at_startup" channel itself. We back it
    // with Apple's own SMAppService (macOS 13+) instead of the third-party
    // LaunchAtLogin SPM package the plugin's README suggests.
    FlutterMethodChannel(
      name: "launch_at_startup", binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    .setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "launchAtStartupIsEnabled":
        result(SMAppService.mainApp.status == .enabled)
      case "launchAtStartupSetEnabled":
        guard let arguments = call.arguments as? [String: Any],
          let enabled = arguments["setEnabledValue"] as? Bool
        else {
          result(FlutterError(code: "invalid_arguments", message: "setEnabledValue missing", details: nil))
          return
        }
        do {
          if enabled {
            try SMAppService.mainApp.register()
          } else {
            try SMAppService.mainApp.unregister()
          }
          result(nil)
        } catch {
          result(FlutterError(code: "SMAppService", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Every popup window desktop_multi_window creates gets its own
    // FlutterViewController/engine — plugins (window_manager, etc.) are
    // NOT automatically registered on it unless we do so here too.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)

      // window_manager's alwaysOnTop only reaches NSWindow.Level.floating,
      // which isn't high enough to render over another app's dedicated
      // fullscreen Space. Raise it further and force-close directly,
      // bypassing window_manager's Cocoa performClose/delegate chain, as a
      // diagnostic for whether that chain is where disposal is getting lost.
      let channel = FlutterMethodChannel(
        name: "insight/popup_window", binaryMessenger: controller.engine.binaryMessenger
      )
      channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        guard let window = controller.view.window else {
          NSLog("insight/popup_window: \(call.method) — no window attached")
          result(nil)
          return
        }
        switch call.method {
        case "raiseAboveFullscreen":
          window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
          result(nil)
        case "hardClose":
          NSLog("insight/popup_window: hardClose calling window.close() on \(window)")
          window.close()
          NSLog("insight/popup_window: hardClose window.close() returned")
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    super.awakeFromNib()
  }
}
