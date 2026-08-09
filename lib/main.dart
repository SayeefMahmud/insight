import 'dart:io';

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

// The single channel bridging the main engine and the popup's own engine
// (hosted in a native NSPanel — see macos/Runner/PopupBridge.swift). Each
// engine gets its own independent MethodChannel instance under this name;
// native code relays between them. Main -> popup: 'showExplanation'.
// Popup -> main: 'openSettings'. Popup -> native only: 'hide'.
const _popupBridge = MethodChannel('insight/popup_bridge');

Rect computePopupFrame(Offset cursor, {Size size = const Size(420, 520)}) {
  return Rect.fromLTWH(cursor.dx, cursor.dy, size.width, size.height);
}

/// Shifts [frame] so it stays entirely within [screen], preferring to keep
/// its size intact (moving it up/left) over letting any edge get cropped.
Rect clampFrameToScreen(Rect frame, Rect screen) {
  var left = frame.left;
  var top = frame.top;

  if (left + frame.width > screen.right) {
    left = screen.right - frame.width;
  }
  if (top + frame.height > screen.bottom) {
    top = screen.bottom - frame.height;
  }
  if (left < screen.left) left = screen.left;
  if (top < screen.top) top = screen.top;

  return Rect.fromLTWH(left, top, frame.width, frame.height);
}

Rect _visibleBounds(Display display) {
  final position = display.visiblePosition ?? Offset.zero;
  final size = display.visibleSize ?? display.size;
  return Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
}

Future<Rect> _screenBoundsForCursor(Offset cursor) async {
  final displays = await screenRetriever.getAllDisplays();
  for (final display in displays) {
    if (_visibleBounds(display).contains(cursor)) {
      return _visibleBounds(display);
    }
  }
  return _visibleBounds(await screenRetriever.getPrimaryDisplay());
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
  await _runMainWindow();
}

// Entrypoint for the popup's own FlutterEngine, run once by
// PopupBridge.swift and reused for the app's life (nonactivating NSPanel
// windows, unlike plain NSWindows, can render above another app's
// fullscreen Space and receive keystrokes without making Insight the
// active app — which is what lets the popup show over a fullscreen app,
// and why it isn't just another desktop_multi_window window).
@pragma('vm:entry-point')
Future<void> popupMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  final controller = SessionController(
    client: WorkersAiClient(),
    historyRepository: HistoryRepository(),
    clipboard: SystemClipboardAccess(),
  );
  var settings = AppSettings(
    accountId: '',
    apiToken: '',
    model: AppSettings.defaultModel,
    promptTemplate: AppSettings.defaultPromptTemplate,
    shortcutKey: AppSettings.defaultShortcutKey,
    shortcutModifiers: AppSettings.defaultShortcutModifiers,
    launchAtLogin: false,
    themeMode: AppSettings.defaultThemeMode,
  );
  final themeNotifier = ValueNotifier<ThemeMode>(_themeModeOf(settings));

  _popupBridge.setMethodCallHandler((call) async {
    if (call.method == 'showExplanation') {
      final args = call.arguments as Map<dynamic, dynamic>;
      final capturedText = args['capturedText'] as String?;
      settings = AppSettings.fromJson(Map<String, dynamic>.from(args['settings'] as Map));
      themeNotifier.value = _themeModeOf(settings);
      await controller.start(capturedText: capturedText, settings: settings);
    }
    return null;
  });

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
        onOpenSettings: () => _popupBridge.invokeMethod('openSettings'),
        onDismiss: () => _popupBridge.invokeMethod('hide'),
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

Future<void> _runMainWindow() async {
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

  _popupBridge.setMethodCallHandler((call) async {
    if (call.method == 'openSettings') {
      navigation.goToSettings();
      await windowManager.show();
      await windowManager.focus();
    }
    return null;
  });

  Future<void> triggerExplain() async {
    final capturedText = await clipboardCapture.captureSelection();
    final cursor = await screenRetriever.getCursorScreenPoint();
    final currentSettings = await repository.load();
    final cursorOffset = Offset(cursor.dx, cursor.dy);
    final screenBounds = await _screenBoundsForCursor(cursorOffset);
    final frame = clampFrameToScreen(computePopupFrame(cursorOffset), screenBounds);

    await _popupBridge.invokeMethod('showExplanation', {
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
