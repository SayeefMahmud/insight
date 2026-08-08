import Cocoa
import FlutterMacOS

/// A panel that can become key (so the follow-up text field can receive
/// keystrokes) without ever becoming the app's main window.
class PopupPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

/// Hosts a single, lazily-created popup window and its own FlutterEngine,
/// created once and reused for the app's life rather than recreated per
/// hotkey trigger.
///
/// This is a real NSPanel with the `.nonactivatingPanel` style, not a
/// desktop_multi_window NSWindow. Two things are only true of an actual
/// non-activating panel: it can become key window (so the follow-up
/// field can be typed into) without making Insight the active app, and —
/// combined with `.canJoinAllSpaces`/`.fullScreenAuxiliary` and a high
/// window level — it can render above another app's dedicated fullscreen
/// Space. A plain NSWindow, and any call to `NSApp.activate()`, cannot do
/// either; `.nonactivatingPanel` has no effect on a non-NSPanel window.
class PopupBridge: NSObject, NSWindowDelegate {
  static let shared = PopupBridge()

  private var mainChannel: FlutterMethodChannel?
  private var popupEngine: FlutterEngine?
  private var popupChannel: FlutterMethodChannel?
  private var panel: PopupPanel?

  func attachMainChannel(_ channel: FlutterMethodChannel) {
    mainChannel = channel
  }

  func handleMainCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "showExplanation":
      showExplanation(call.arguments as? [String: Any] ?? [:])
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func ensurePopup() -> (PopupPanel, FlutterMethodChannel) {
    if let panel = panel, let channel = popupChannel {
      return (panel, channel)
    }

    let engine = FlutterEngine(name: "insight-popup", project: nil)
    engine.run(withEntrypoint: "popupMain")
    RegisterGeneratedPlugins(registry: engine)

    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)

    let panel = PopupPanel(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
      styleMask: [.nonactivatingPanel, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.minSize = NSSize(width: 360, height: 400)
    panel.contentViewController = controller
    panel.delegate = self

    let channel = FlutterMethodChannel(
      name: "insight/popup_bridge", binaryMessenger: engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "hide":
        self?.panel?.orderOut(nil)
        result(nil)
      case "openSettings":
        self?.panel?.orderOut(nil)
        self?.mainChannel?.invokeMethod("openSettings", arguments: nil)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    self.popupEngine = engine
    self.panel = panel
    self.popupChannel = channel
    return (panel, channel)
  }

  private func showExplanation(_ args: [String: Any]) {
    let (panel, channel) = ensurePopup()

    if let frameArgs = args["frame"] as? [String: Any],
      let left = (frameArgs["left"] as? NSNumber)?.doubleValue,
      let top = (frameArgs["top"] as? NSNumber)?.doubleValue,
      let width = (frameArgs["width"] as? NSNumber)?.doubleValue,
      let height = (frameArgs["height"] as? NSNumber)?.doubleValue
    {
      // The incoming frame uses top-left screen coordinates (matching
      // window_manager's own convention); Cocoa's are bottom-left.
      let screenHeight = NSScreen.screens.first?.frame.height ?? 0
      let origin = NSPoint(x: left, y: screenHeight - top - height)
      panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    }

    panel.makeKeyAndOrderFront(nil)
    channel.invokeMethod("showExplanation", arguments: args)
  }

  // NSWindowDelegate — click-outside/blur dismiss.
  func windowDidResignKey(_ notification: Notification) {
    panel?.orderOut(nil)
  }
}
