import Cocoa
import FlutterMacOS
import ServiceManagement

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

    // Bridges this (main) engine to the popup's own engine — see
    // PopupBridge.swift for why the popup is a hand-rolled NSPanel with
    // its own FlutterEngine rather than a desktop_multi_window window.
    let popupBridgeChannel = FlutterMethodChannel(
      name: "insight/popup_bridge", binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    popupBridgeChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      PopupBridge.shared.handleMainCall(call, result: result)
    }
    PopupBridge.shared.attachMainChannel(popupBridgeChannel)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
