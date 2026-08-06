import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'app/settings_model.dart';
import 'app/settings_repository.dart';
import 'services/auto_start_sync.dart';
import 'services/clipboard_capture_service.dart';
import 'services/hotkey_service.dart';
import 'services/tray_service.dart';
import 'services/workers_ai_client.dart';
import 'ui/popup/explanation_controller.dart';
import 'ui/popup/popup_screen.dart';
import 'ui/settings/settings_screen.dart';

Rect computePopupFrame(Offset cursor, {Size size = const Size(360, 200)}) {
  return Rect.fromLTWH(cursor.dx, cursor.dy, size.width, size.height);
}

Future<void> openMacAccessibilitySettings() async {
  if (Platform.isMacOS) {
    await Process.run('open', [
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
    ]);
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final windowController = await WindowController.fromCurrentEngine();

  if (windowController.arguments.isEmpty) {
    await _runMainWindow(windowController);
  } else {
    await _runPopupWindow(windowController);
  }
}

// window_manager's channel targets whichever window this isolate/engine
// belongs to, so a popup window closes itself directly on blur — no
// cross-window WindowController call is needed for that.
class _PopupBlurListener extends WindowListener {
  @override
  void onWindowBlur() {
    windowManager.close();
  }
}

Future<void> _runPopupWindow(WindowController windowController) async {
  final payload = jsonDecode(windowController.arguments) as Map<String, dynamic>;
  final capturedText = payload['capturedText'] as String?;
  final settings = AppSettings.fromJson(payload['settings'] as Map<String, dynamic>);
  final mainWindowId = payload['mainWindowId'] as String;
  final frameJson = payload['frame'] as Map<String, dynamic>;
  final frame = Rect.fromLTWH(
    (frameJson['left'] as num).toDouble(),
    (frameJson['top'] as num).toDouble(),
    (frameJson['width'] as num).toDouble(),
    (frameJson['height'] as num).toDouble(),
  );

  await windowController.setWindowMethodHandler((call) async {
    if (call.method == 'window_close') {
      return windowManager.close();
    }
    throw MissingPluginException('Not implemented: ${call.method}');
  });

  windowManager.addListener(_PopupBlurListener());

  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: frame.size,
      skipTaskbar: true,
      alwaysOnTop: true,
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      await windowManager.setPosition(frame.topLeft);
      await windowManager.show();
      await windowManager.focus();
    },
  );

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PopupScreen(
      controller: ExplanationController(client: WorkersAiClient()),
      capturedText: capturedText,
      settings: settings,
      onOpenSettings: () async {
        await WindowController.fromWindowId(mainWindowId).invokeMethod('openSettings');
        await windowManager.close();
      },
      onDismiss: () => windowManager.close(),
    ),
  ));
}

Future<void> _runMainWindow(WindowController windowController) async {
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(skipTaskbar: true, titleBarStyle: TitleBarStyle.hidden),
    () async {
      await windowManager.hide();
    },
  );

  final repository = SettingsRepository();
  var settings = await repository.load();

  // launch_at_startup falls back to a no-op implementation that throws on
  // every call until setup() has been run once.
  launchAtStartup.setup(
    appName: 'Insight',
    appPath: Platform.resolvedExecutable,
    packageName: 'com.cefalo.insight.insight',
  );
  await AutoStartSync(LaunchAtStartupController()).applySetting(settings.launchAtLogin);

  final clipboardCapture = ClipboardCaptureService(
    keySimulator: PlatformKeySimulator(),
    clipboard: SystemClipboardAccess(),
  );

  final hotkeyService = HotkeyService(HotkeyManagerController());
  final trayService = TrayService(
    controller: TrayManagerController(),
    onSettings: () async {
      await windowManager.show();
      await windowManager.focus();
    },
    onQuit: () => windowManager.close(),
  );
  await trayService.initialize('assets/tray_icon.png');

  await windowController.setWindowMethodHandler((call) async {
    if (call.method == 'openSettings') {
      await windowManager.show();
      await windowManager.focus();
    }
  });

  // Tracks the single open popup window so a second hotkey press replaces
  // rather than stacks a new one (spec: no multiple simultaneous popups).
  String? openPopupWindowId;

  Future<void> triggerExplain() async {
    if (openPopupWindowId != null) {
      await WindowController.fromWindowId(openPopupWindowId!).invokeMethod('window_close');
      openPopupWindowId = null;
    }

    final capturedText = await clipboardCapture.captureSelection();
    final cursor = await screenRetriever.getCursorScreenPoint();
    final currentSettings = await repository.load();
    final frame = computePopupFrame(Offset(cursor.dx, cursor.dy));

    final popupController = await WindowController.create(WindowConfiguration(
      hiddenAtLaunch: true,
      arguments: jsonEncode({
        'capturedText': capturedText,
        'settings': currentSettings.toJson(),
        'mainWindowId': windowController.windowId,
        'frame': {
          'left': frame.left,
          'top': frame.top,
          'width': frame.width,
          'height': frame.height,
        },
      }),
    ));
    openPopupWindowId = popupController.windowId;
  }

  Future<void> applyHotkey(AppSettings current) async {
    await hotkeyService.applyShortcut(current, () {
      triggerExplain();
    });
    if (hotkeyService.registrationFailed) {
      await trayService.showHotkeyConflictWarning();
      if (Platform.isMacOS) {
        await openMacAccessibilitySettings();
      }
    }
  }

  await applyHotkey(settings);

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SettingsScreen(
      repository: repository,
      onSaved: () async {
        settings = await repository.load();
        await applyHotkey(settings);
      },
    ),
  ));
}
