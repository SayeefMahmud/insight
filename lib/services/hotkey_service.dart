import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../app/settings_model.dart';

const Map<String, PhysicalKeyboardKey> kSupportedShortcutKeys = {
  'keyA': PhysicalKeyboardKey.keyA, 'keyB': PhysicalKeyboardKey.keyB,
  'keyC': PhysicalKeyboardKey.keyC, 'keyD': PhysicalKeyboardKey.keyD,
  'keyE': PhysicalKeyboardKey.keyE, 'keyF': PhysicalKeyboardKey.keyF,
  'keyG': PhysicalKeyboardKey.keyG, 'keyH': PhysicalKeyboardKey.keyH,
  'keyI': PhysicalKeyboardKey.keyI, 'keyJ': PhysicalKeyboardKey.keyJ,
  'keyK': PhysicalKeyboardKey.keyK, 'keyL': PhysicalKeyboardKey.keyL,
  'keyM': PhysicalKeyboardKey.keyM, 'keyN': PhysicalKeyboardKey.keyN,
  'keyO': PhysicalKeyboardKey.keyO, 'keyP': PhysicalKeyboardKey.keyP,
  'keyQ': PhysicalKeyboardKey.keyQ, 'keyR': PhysicalKeyboardKey.keyR,
  'keyS': PhysicalKeyboardKey.keyS, 'keyT': PhysicalKeyboardKey.keyT,
  'keyU': PhysicalKeyboardKey.keyU, 'keyV': PhysicalKeyboardKey.keyV,
  'keyW': PhysicalKeyboardKey.keyW, 'keyX': PhysicalKeyboardKey.keyX,
  'keyY': PhysicalKeyboardKey.keyY, 'keyZ': PhysicalKeyboardKey.keyZ,
};

PhysicalKeyboardKey _mapKey(String name) {
  final key = kSupportedShortcutKeys[name];
  if (key == null) throw ArgumentError('Unsupported shortcut key: $name');
  return key;
}

HotKeyModifier _mapModifier(String name) => switch (name) {
      'meta' => HotKeyModifier.meta,
      'control' => HotKeyModifier.control,
      'shift' => HotKeyModifier.shift,
      'alt' => HotKeyModifier.alt,
      _ => throw ArgumentError('Unsupported modifier: $name'),
    };

abstract class HotkeyController {
  Future<void> register(HotKey hotKey, {required void Function(HotKey) onKeyDown});
  Future<void> unregisterAll();
}

class HotkeyManagerController implements HotkeyController {
  @override
  Future<void> register(HotKey hotKey, {required void Function(HotKey) onKeyDown}) =>
      hotKeyManager.register(hotKey, keyDownHandler: onKeyDown);

  @override
  Future<void> unregisterAll() => hotKeyManager.unregisterAll();
}

class HotkeyService {
  HotkeyService(this._controller);

  final HotkeyController _controller;
  bool _registrationFailed = false;
  bool get registrationFailed => _registrationFailed;

  Future<void> applyShortcut(AppSettings settings, void Function() onTriggered) async {
    await _controller.unregisterAll();
    final hotKey = HotKey(
      key: _mapKey(settings.shortcutKey),
      modifiers: settings.shortcutModifiers.map(_mapModifier).toList(),
      scope: HotKeyScope.system,
    );
    try {
      await _controller.register(hotKey, onKeyDown: (_) => onTriggered());
      _registrationFailed = false;
    } catch (_) {
      _registrationFailed = true;
    }
  }
}
