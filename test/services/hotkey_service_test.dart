import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:mocktail/mocktail.dart';
import 'package:insight/app/settings_model.dart';
import 'package:insight/services/hotkey_service.dart';

class MockHotkeyController extends Mock implements HotkeyController {}

void main() {
  setUpAll(() {
    registerFallbackValue(HotKey(key: PhysicalKeyboardKey.keyA));
  });

  test('unregisters existing shortcuts and registers the mapped one', () async {
    final controller = MockHotkeyController();
    when(() => controller.unregisterAll()).thenAnswer((_) async {});
    when(() => controller.register(any(), onKeyDown: any(named: 'onKeyDown')))
        .thenAnswer((_) async {});
    final service = HotkeyService(controller);

    var triggered = false;
    await service.applyShortcut(
      const AppSettings(
        accountId: '',
        apiToken: '',
        model: '',
        promptTemplate: '{{selection}}',
        shortcutKey: 'keyE',
        shortcutModifiers: ['meta', 'shift'],
        launchAtLogin: false,
        themeMode: 'dark',
      ),
      () => triggered = true,
    );

    verify(() => controller.unregisterAll()).called(1);
    final captured =
        verify(() => controller.register(captureAny(), onKeyDown: captureAny(named: 'onKeyDown')))
            .captured;
    final hotKey = captured[0] as HotKey;
    expect(hotKey.key, PhysicalKeyboardKey.keyE);
    expect(hotKey.modifiers, containsAll([HotKeyModifier.meta, HotKeyModifier.shift]));
    expect(service.registrationFailed, isFalse);

    final onKeyDown = captured[1] as void Function(HotKey);
    onKeyDown(hotKey);
    expect(triggered, isTrue);
  });

  test('sets registrationFailed when the controller throws', () async {
    final controller = MockHotkeyController();
    when(() => controller.unregisterAll()).thenAnswer((_) async {});
    when(() => controller.register(any(), onKeyDown: any(named: 'onKeyDown')))
        .thenThrow(Exception('already registered by another app'));
    final service = HotkeyService(controller);

    await service.applyShortcut(
      const AppSettings(
        accountId: '',
        apiToken: '',
        model: '',
        promptTemplate: '{{selection}}',
        shortcutKey: 'keyE',
        shortcutModifiers: ['meta'],
        launchAtLogin: false,
        themeMode: 'dark',
      ),
      () {},
    );

    expect(service.registrationFailed, isTrue);
  });
}
