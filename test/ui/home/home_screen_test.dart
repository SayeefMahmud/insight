import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:insight/app/settings_repository.dart';
import 'package:insight/domain/session.dart';
import 'package:insight/services/history_repository.dart';
import 'package:insight/services/hotkey_service.dart';
import 'package:insight/ui/app/app_navigation.dart';
import 'package:insight/ui/home/home_screen.dart';

class MockSecureStorage extends Mock implements SecureStorage {}
class MockHistoryRepository extends Mock implements HistoryRepository {}
class MockHotkeyController extends Mock implements HotkeyController {}

void main() {
  late SettingsRepository settingsRepository;
  late MockHistoryRepository historyRepository;
  late HotkeyService hotkeyService;
  late AppNavigation navigation;

  setUpAll(() {
    registerFallbackValue(HotKey(key: PhysicalKeyboardKey.keyA));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final secureStorage = MockSecureStorage();
    when(() => secureStorage.read(key: any(named: 'key'))).thenAnswer((_) async => null);
    when(() => secureStorage.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenAnswer((_) async {});
    settingsRepository = SettingsRepository(secureStorage: secureStorage);
    historyRepository = MockHistoryRepository();
    hotkeyService = HotkeyService(MockHotkeyController());
    navigation = AppNavigation();
  });

  testWidgets('shows the default shortcut and a registered status', (tester) async {
    when(() => historyRepository.loadAll()).thenAnswer((_) async => []);

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        settingsRepository: settingsRepository,
        historyRepository: historyRepository,
        hotkeyService: hotkeyService,
        navigation: navigation,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Meta+Shift+E'), findsOneWidget);
    expect(find.text('Registered'), findsOneWidget);
  });

  testWidgets('shows a conflict status when the hotkey failed to register', (tester) async {
    when(() => historyRepository.loadAll()).thenAnswer((_) async => []);
    final controller = MockHotkeyController();
    when(() => controller.unregisterAll()).thenAnswer((_) async {});
    when(() => controller.register(any(), onKeyDown: any(named: 'onKeyDown')))
        .thenThrow(Exception('conflict'));
    hotkeyService = HotkeyService(controller);
    await hotkeyService.applyShortcut(await settingsRepository.load(), () {});

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        settingsRepository: settingsRepository,
        historyRepository: historyRepository,
        hotkeyService: hotkeyService,
        navigation: navigation,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Conflict — rebind in Settings'), findsOneWidget);
  });

  testWidgets('shows recent sessions and opens one on tap', (tester) async {
    final session = ExplanationSession(
      id: 'abc',
      selectedText: 'quantum entanglement',
      createdAt: DateTime.now(),
      turns: const [],
    );
    when(() => historyRepository.loadAll()).thenAnswer((_) async => [session]);

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        settingsRepository: settingsRepository,
        historyRepository: historyRepository,
        hotkeyService: hotkeyService,
        navigation: navigation,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('quantum entanglement'), findsOneWidget);
    await tester.tap(find.byKey(const Key('recent-abc')));

    expect(navigation.activeTab.value, AppTab.history);
    expect(navigation.selectedSessionId.value, 'abc');
  });
}
