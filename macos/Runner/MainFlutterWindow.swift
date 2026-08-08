import Cocoa
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
    //
    // That popup window/engine is created once and reused for the app's
    // lifetime (see lib/main.dart) rather than recreated per hotkey
    // trigger — desktop_multi_window's window teardown on close doesn't
    // actually free the underlying FlutterEngine, so recreating it
    // repeatedly leaked one engine per trigger.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
    }

    super.awakeFromNib()
  }
}
