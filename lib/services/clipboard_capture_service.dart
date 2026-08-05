import 'dart:io';

import 'package:flutter/services.dart';
import 'package:keypress_simulator/keypress_simulator.dart';
import 'package:super_clipboard/super_clipboard.dart';

abstract class KeySimulator {
  Future<void> simulateCopy();
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
    this.copyDelay = const Duration(milliseconds: 100),
  });

  final KeySimulator keySimulator;
  final ClipboardAccess clipboard;
  final Duration copyDelay;

  Future<String?> captureSelection() async {
    final original = await clipboard.readText();
    await keySimulator.simulateCopy();
    await Future.delayed(copyDelay);
    final captured = await clipboard.readText();
    await clipboard.writeText(original);

    if (captured == null || captured.isEmpty || captured == original) {
      return null;
    }
    return captured;
  }
}
