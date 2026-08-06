import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

abstract class TrayController {
  Future<void> setIcon(String iconPath);
  Future<void> setToolTip(String toolTip);
  Future<void> setContextMenu(Menu menu);
  Future<void> popUpContextMenu();
  void addListener(TrayListener listener);
}

class TrayManagerController implements TrayController {
  @override
  Future<void> setIcon(String iconPath) => trayManager.setIcon(iconPath);

  @override
  Future<void> setToolTip(String toolTip) => trayManager.setToolTip(toolTip);

  @override
  Future<void> setContextMenu(Menu menu) => trayManager.setContextMenu(menu);

  @override
  Future<void> popUpContextMenu() => trayManager.popUpContextMenu();

  @override
  void addListener(TrayListener listener) => trayManager.addListener(listener);
}

class TrayService with TrayListener {
  TrayService({
    required this.controller,
    required VoidCallback onSettings,
    required VoidCallback onQuit,
  })  : _onSettings = onSettings,
        _onQuit = onQuit;

  final TrayController controller;
  final VoidCallback _onSettings;
  final VoidCallback _onQuit;

  Future<void> initialize(String iconPath) async {
    await controller.setIcon(iconPath);
    await controller.setContextMenu(Menu(items: [
      MenuItem(key: 'settings', label: 'Settings...'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]));
    controller.addListener(this);
  }

  Future<void> showHotkeyConflictWarning() async {
    await controller.setToolTip(
      'Insight: shortcut conflict — open Settings to rebind',
    );
    await controller.setContextMenu(Menu(items: [
      MenuItem(key: 'hotkeyConflict', label: '⚠ Shortcut conflict — rebind...'),
      MenuItem.separator(),
      MenuItem(key: 'settings', label: 'Settings...'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]));
  }

  // tray_manager doesn't show the context menu automatically on click — the
  // app must explicitly pop it up in response to the mouse-down event
  // (confirmed via the plugin's own example app).
  @override
  void onTrayIconMouseDown() {
    controller.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'settings' || menuItem.key == 'hotkeyConflict') {
      _onSettings();
    } else if (menuItem.key == 'quit') {
      _onQuit();
    }
  }
}
