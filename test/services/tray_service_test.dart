import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:insight/services/tray_service.dart';

class MockTrayController extends Mock implements TrayController {}

class _FakeTrayListener extends Fake implements TrayListener {}

void main() {
  setUpAll(() {
    registerFallbackValue(Menu(items: const []));
    registerFallbackValue(_FakeTrayListener());
  });

  test('initialize sets the icon and a menu with settings/quit items', () async {
    final controller = MockTrayController();
    when(() => controller.setIcon(any())).thenAnswer((_) async {});
    when(() => controller.setContextMenu(any())).thenAnswer((_) async {});
    when(() => controller.addListener(any())).thenReturn(null);
    final service = TrayService(controller: controller, onSettings: () {}, onQuit: () {});

    await service.initialize('assets/tray_icon.png');

    verify(() => controller.setIcon('assets/tray_icon.png')).called(1);
    final captured = verify(() => controller.setContextMenu(captureAny())).captured;
    final menu = captured.single as Menu;
    expect(menu.items!.map((item) => item.key), containsAll(['settings', 'quit']));
  });

  test('showHotkeyConflictWarning sets a tooltip and adds a warning menu item', () async {
    final controller = MockTrayController();
    when(() => controller.setIcon(any())).thenAnswer((_) async {});
    when(() => controller.setToolTip(any())).thenAnswer((_) async {});
    when(() => controller.setContextMenu(any())).thenAnswer((_) async {});
    when(() => controller.addListener(any())).thenReturn(null);
    final service = TrayService(controller: controller, onSettings: () {}, onQuit: () {});
    await service.initialize('assets/tray_icon.png');

    await service.showHotkeyConflictWarning();

    verify(() => controller.setToolTip(any(that: contains('shortcut conflict')))).called(1);
    final captured = verify(() => controller.setContextMenu(captureAny())).captured;
    final menu = captured.last as Menu;
    expect(menu.items!.map((item) => item.key), contains('hotkeyConflict'));
  });

  test('clicking the settings menu item triggers onSettings', () {
    var settingsClicked = false;
    final service = TrayService(
      controller: MockTrayController(),
      onSettings: () => settingsClicked = true,
      onQuit: () {},
    );

    service.onTrayMenuItemClick(MenuItem(key: 'settings', label: 'Settings...'));

    expect(settingsClicked, isTrue);
  });

  test('clicking the quit menu item triggers onQuit', () {
    var quitClicked = false;
    final service = TrayService(
      controller: MockTrayController(),
      onSettings: () {},
      onQuit: () => quitClicked = true,
    );

    service.onTrayMenuItemClick(MenuItem(key: 'quit', label: 'Quit'));

    expect(quitClicked, isTrue);
  });
}
