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
import 'services/history_repository.dart';
import 'services/hotkey_service.dart';
import 'services/tray_service.dart';
import 'services/workers_ai_client.dart';
import 'ui/app/app_navigation.dart';
import 'ui/app/main_app_screen.dart';
import 'ui/history/history_screen.dart';
import 'ui/home/home_screen.dart';
import 'ui/popup/popup_screen.dart';
import 'ui/session/session_controller.dart';
import 'ui/settings/settings_screen.dart';

Rect computePopupFrame(Offset cursor, {Size size = const Size(420, 520)}) {
  return Rect.fromLTWH(cursor.dx, cursor.dy, size.width, size.height);
}

Future<void> openMacAccessibilitySettings() async {
  if (Platform.isMacOS) {
    await Process.run('open', [
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
    ]);
  }
}

ThemeMode _themeModeOf(AppSettings settings) =>
    settings.themeMode == 'light' ? ThemeMode.light : ThemeMode.dark;

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

// The popup window is created once (lazily, on first hotkey trigger) and
// reused for the rest of the app's life — desktop_multi_window's engine
// teardown on window close doesn't actually free the underlying
// FlutterEngine (confirmed: it never re-triggers "Child window deinit"),
// so recreating a window per trigger leaks an engine every time. Instead
// every close path here just hides the window; each new explanation is
// pushed into the SAME still-running engine via 'window_showExplanation'.
//
// window_manager's channel targets whichever window this isolate/engine
// belongs to, so blur can hide the window directly — no cross-window
// WindowController call needed for that.
class _PopupBlurListener extends WindowListener {
  _PopupBlurListener(this.onBlur);

  final VoidCallback onBlur;

  @override
  void onWindowBlur() => onBlur();
}

Future<void> _runPopupWindow(WindowController windowController) async {
  final payload = jsonDecode(windowController.arguments) as Map<String, dynamic>;
  final mainWindowId = payload['mainWindowId'] as String;
  var settings = AppSettings.fromJson(payload['settings'] as Map<String, dynamic>);

  final controller = SessionController(
    client: WorkersAiClient(),
    historyRepository: HistoryRepository(),
    clipboard: SystemClipboardAccess(),
  );
  final themeNotifier = ValueNotifier<ThemeMode>(_themeModeOf(settings));

  void hidePopup() {
    windowManager.hide();
  }

  await windowController.setWindowMethodHandler((call) async {
    switch (call.method) {
      case 'showExplanation':
        final args = call.arguments as Map<String, dynamic>;
        final capturedText = args['capturedText'] as String?;
        settings = AppSettings.fromJson(args['settings'] as Map<String, dynamic>);
        final frameJson = args['frame'] as Map<String, dynamic>;
        final frame = Rect.fromLTWH(
          (frameJson['left'] as num).toDouble(),
          (frameJson['top'] as num).toDouble(),
          (frameJson['width'] as num).toDouble(),
          (frameJson['height'] as num).toDouble(),
        );
        themeNotifier.value = _themeModeOf(settings);
        await windowManager.setSize(frame.size);
        await windowManager.setPosition(frame.topLeft);
        await windowManager.show();
        await windowManager.focus();
        await controller.start(capturedText: capturedText, settings: settings);
        return;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  });

  windowManager.addListener(_PopupBlurListener(hidePopup));

  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      minimumSize: Size(360, 400),
      alwaysOnTop: true,
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      await windowManager.setVisibleOnAllWorkspaces(true, visibleOnFullScreen: true);
      // Stays hidden until the first 'showExplanation' call arrives.
    },
  );

  runApp(ValueListenableBuilder<ThemeMode>(
    valueListenable: themeNotifier,
    builder: (context, mode, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: mode,
      home: PopupScreen(
        controller: controller,
        capturedText: null,
        settings: settings,
        onOpenSettings: () async {
          await WindowController.fromWindowId(mainWindowId).invokeMethod('openSettings');
          hidePopup();
        },
        onDismiss: hidePopup,
      ),
    ),
  ));
}

// Closing the main window (native close button) hides it rather than
// quitting — the app keeps running in the background (tray + Dock icon).
class _MainWindowCloseListener extends WindowListener {
  @override
  void onWindowClose() {
    windowManager.hide();
  }
}

Future<void> _runMainWindow(WindowController windowController) async {
  await windowManager.setPreventClose(true);
  windowManager.addListener(_MainWindowCloseListener());

  await windowManager.waitUntilReadyToShow(
    const WindowOptions(titleBarStyle: TitleBarStyle.hidden),
    () async {
      await windowManager.hide();
    },
  );

  final repository = SettingsRepository();
  final historyRepository = HistoryRepository();
  final workersAiClient = WorkersAiClient();
  final clipboard = SystemClipboardAccess();
  final navigation = AppNavigation();
  var settings = await repository.load();

  final themeNotifier = ValueNotifier<ThemeMode>(_themeModeOf(settings));

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
      navigation.goToSettings();
      await windowManager.show();
      await windowManager.focus();
    },
    onQuit: () => exit(0),
  );
  await trayService.initialize('assets/tray_icon.png');

  await windowController.setWindowMethodHandler((call) async {
    if (call.method == 'openSettings') {
      navigation.goToSettings();
      await windowManager.show();
      await windowManager.focus();
    }
  });

  // Created lazily on first trigger, then reused (hidden/shown) for the
  // rest of the app's life — see the comment on _PopupBlurListener above.
  WindowController? popupWindowController;

  Future<WindowController> ensurePopupWindow() async {
    final existing = popupWindowController;
    if (existing != null) return existing;

    final created = await WindowController.create(WindowConfiguration(
      hiddenAtLaunch: true,
      arguments: jsonEncode({
        'mainWindowId': windowController.windowId,
        'settings': settings.toJson(),
      }),
    ));
    popupWindowController = created;
    return created;
  }

  Future<void> triggerExplain() async {
    final capturedText = await clipboardCapture.captureSelection();
    final cursor = await screenRetriever.getCursorScreenPoint();
    final currentSettings = await repository.load();
    final frame = computePopupFrame(Offset(cursor.dx, cursor.dy));

    final popupController = await ensurePopupWindow();
    await popupController.invokeMethod('showExplanation', {
      'capturedText': capturedText,
      'settings': currentSettings.toJson(),
      'frame': {
        'left': frame.left,
        'top': frame.top,
        'width': frame.width,
        'height': frame.height,
      },
    });
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

  runApp(ValueListenableBuilder<ThemeMode>(
    valueListenable: themeNotifier,
    builder: (context, mode, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: mode,
      home: MainAppScreen(
        navigation: navigation,
        homeScreen: HomeScreen(
          settingsRepository: repository,
          historyRepository: historyRepository,
          hotkeyService: hotkeyService,
          navigation: navigation,
        ),
        historyScreen: HistoryScreen(
          historyRepository: historyRepository,
          client: workersAiClient,
          clipboard: clipboard,
          settingsRepository: repository,
          navigation: navigation,
        ),
        settingsScreen: SettingsScreen(
          repository: repository,
          onSaved: () async {
            settings = await repository.load();
            themeNotifier.value = _themeModeOf(settings);
            await applyHotkey(settings);
          },
        ),
      ),
    ),
  ));
}
