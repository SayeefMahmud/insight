import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:keypress_simulator/keypress_simulator.dart';
import 'package:super_clipboard/super_clipboard.dart';

abstract class KeySimulator {
  Future<void> simulateCopy();

  // macOS revokes Accessibility permission for an ad-hoc-signed app
  // whenever its code signature changes — i.e. on every rebuild during
  // development — which makes simulateCopy() silently no-op. Surfacing
  // this distinguishes "permission is missing" from "nothing selected".
  Future<bool> hasAccessibilityPermission();
}

class PlatformKeySimulator implements KeySimulator {
  @override
  Future<void> simulateCopy() async {
    final modifier =
        Platform.isMacOS ? ModifierKey.metaModifier : ModifierKey.controlModifier;
    await KeyPressSimulator.instance
        .simulateKeyDown(PhysicalKeyboardKey.keyC, [modifier]);
    await KeyPressSimulator.instance
        .simulateKeyUp(PhysicalKeyboardKey.keyC, [modifier]);
  }

  @override
  Future<bool> hasAccessibilityPermission() {
    if (!Platform.isMacOS) return Future.value(true);
    return KeyPressSimulator.instance.isAccessAllowed();
  }
}

abstract class ClipboardAccess {
  Future<String?> readText();
  Future<void> writeText(String? text);
}

class SystemClipboardAccess implements ClipboardAccess {
  @override
  Future<String?> readText() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return null;
    final reader = await clipboard.read();
    return reader.readValue(Formats.plainText);
  }

  @override
  Future<void> writeText(String? text) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;
    final item = DataWriterItem();
    item.add(Formats.plainText(text ?? ''));
    await clipboard.write([item]);
  }
}

class ClipboardCaptureService {
  ClipboardCaptureService({
    required this.keySimulator,
    required this.clipboard,
    this.copyDelay = const Duration(milliseconds: 50),
    this.maxWait = const Duration(milliseconds: 500),
  });

  final KeySimulator keySimulator;
  final ClipboardAccess clipboard;
  final Duration copyDelay;

  // The target app can take longer than a single fixed delay to update the
  // system clipboard after a synthetic copy — especially non-native apps
  // under load — so this polls for up to maxWait instead of checking once.
  final Duration maxWait;

  Future<String?> captureSelection() async {
    if (!await keySimulator.hasAccessibilityPermission()) {
      debugPrint(
        'ClipboardCaptureService: Accessibility permission not granted — '
        'the synthetic copy will likely be ignored by the OS.',
      );
    }

    final original = await clipboard.readText();
    await keySimulator.simulateCopy();

    String? captured;
    final stopwatch = Stopwatch()..start();
    do {
      await Future.delayed(copyDelay);
      captured = await clipboard.readText();
    } while (_isUnchanged(captured, original) && stopwatch.elapsed < maxWait);

    await clipboard.writeText(original);

    return _isUnchanged(captured, original) ? null : captured;
  }

  bool _isUnchanged(String? captured, String? original) =>
      captured == null || captured.isEmpty || captured == original;
}
