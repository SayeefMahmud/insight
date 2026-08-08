import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:insight/app/settings_repository.dart';
import 'package:insight/domain/session.dart';
import 'package:insight/services/clipboard_capture_service.dart';
import 'package:insight/services/history_repository.dart';
import 'package:insight/services/workers_ai_client.dart';
import 'package:insight/ui/app/app_navigation.dart';
import 'package:insight/ui/history/history_screen.dart';

class MockSecureStorage extends Mock implements SecureStorage {}
class MockHistoryRepository extends Mock implements HistoryRepository {}
class MockWorkersAiClient extends Mock implements WorkersAiClient {}
class MockClipboardAccess extends Mock implements ClipboardAccess {}

ExplanationSession _session(String id, String text, {List<SessionTurn> turns = const []}) =>
    ExplanationSession(id: id, selectedText: text, createdAt: DateTime.now(), turns: turns);

void main() {
  late SettingsRepository settingsRepository;
  late MockHistoryRepository historyRepository;
  late MockWorkersAiClient client;
  late MockClipboardAccess clipboard;
  late AppNavigation navigation;

  setUpAll(() {
    registerFallbackValue(ExplanationSession(
      id: 'fallback',
      selectedText: '',
      createdAt: DateTime.now(),
      turns: const [],
    ));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final secureStorage = MockSecureStorage();
    when(() => secureStorage.read(key: any(named: 'key'))).thenAnswer((_) async => null);
    when(() => secureStorage.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenAnswer((_) async {});
    settingsRepository = SettingsRepository(secureStorage: secureStorage);
    historyRepository = MockHistoryRepository();
    client = MockWorkersAiClient();
    clipboard = MockClipboardAccess();
    navigation = AppNavigation();
  });

  Widget buildScreen() => MaterialApp(
        home: HistoryScreen(
          historyRepository: historyRepository,
          client: client,
          clipboard: clipboard,
          settingsRepository: settingsRepository,
          navigation: navigation,
        ),
      );

  testWidgets('lists sessions and filters by search text', (tester) async {
    when(() => historyRepository.loadAll()).thenAnswer((_) async => [
          _session('1', 'quantum entanglement'),
          _session('2', 'photosynthesis'),
        ]);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('quantum entanglement'), findsOneWidget);
    expect(find.text('photosynthesis'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('searchField')), 'quantum');
    await tester.pumpAndSettle();

    expect(find.text('quantum entanglement'), findsOneWidget);
    expect(find.text('photosynthesis'), findsNothing);
  });

  testWidgets('opening a session shows its transcript, resumable', (tester) async {
    final session = _session('1', 'quantum entanglement', turns: [
      SessionTurn(
        role: TurnRole.assistant,
        content: 'It is a physics phenomenon.',
        timestamp: DateTime.now(),
      ),
    ]);
    when(() => historyRepository.loadAll()).thenAnswer((_) async => [session]);
    when(() => historyRepository.save(any())).thenAnswer((_) async {});
    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer((_) => Stream.fromIterable(['Bonjour']));

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-1')));
    await tester.pumpAndSettle();

    expect(find.text('It is a physics phenomenon.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('followUpField')), 'In French?');
    await tester.tap(find.byKey(const Key('sendButton')));
    await tester.pumpAndSettle();

    expect(find.text('Bonjour'), findsOneWidget);
  });

  testWidgets('delete removes the session and returns to the list', (tester) async {
    final session = _session('1', 'quantum entanglement');
    when(() => historyRepository.loadAll()).thenAnswer((_) async => [session]);
    when(() => historyRepository.delete('1')).thenAnswer((_) async {});

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-1')));
    await tester.pumpAndSettle();

    when(() => historyRepository.loadAll()).thenAnswer((_) async => []);
    await tester.tap(find.byKey(const Key('deleteButton')));
    await tester.pumpAndSettle();

    verify(() => historyRepository.delete('1')).called(1);
    expect(find.byKey(const Key('searchField')), findsOneWidget);
  });

  testWidgets('selecting a session id via AppNavigation opens its detail view', (tester) async {
    final session = _session('1', 'quantum entanglement');
    when(() => historyRepository.loadAll()).thenAnswer((_) async => [session]);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    navigation.selectedSessionId.value = '1';
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backButton')), findsOneWidget);
  });
}
