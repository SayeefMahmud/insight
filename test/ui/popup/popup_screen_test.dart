import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:insight/app/settings_model.dart';
import 'package:insight/domain/session.dart';
import 'package:insight/services/clipboard_capture_service.dart';
import 'package:insight/services/history_repository.dart';
import 'package:insight/services/workers_ai_client.dart';
import 'package:insight/ui/popup/popup_screen.dart';
import 'package:insight/ui/session/session_controller.dart';

class MockWorkersAiClient extends Mock implements WorkersAiClient {}
class MockHistoryRepository extends Mock implements HistoryRepository {}
class MockClipboardAccess extends Mock implements ClipboardAccess {}

AppSettings _testSettings() => const AppSettings(
      accountId: 'acct',
      apiToken: 'token',
      model: 'model',
      promptTemplate: '{{selection}}',
      shortcutKey: 'keyE',
      shortcutModifiers: ['meta'],
      launchAtLogin: false,
      themeMode: 'dark',
    );

void main() {
  late SessionController controller;

  setUpAll(() {
    registerFallbackValue(ExplanationSession(
      id: 'fallback',
      selectedText: '',
      createdAt: DateTime.now(),
      turns: const [],
    ));
  });

  setUp(() {
    final client = MockWorkersAiClient();
    final historyRepository = MockHistoryRepository();
    final clipboard = MockClipboardAccess();
    when(() => historyRepository.save(any())).thenAnswer((_) async {});
    when(() => clipboard.writeText(any())).thenAnswer((_) async {});
    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer((_) => Stream.fromIterable(['answer']));
    controller = SessionController(
      client: client,
      historyRepository: historyRepository,
      clipboard: clipboard,
    );
  });

  testWidgets('starts the session on init and shows the streamed answer', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PopupScreen(
        controller: controller,
        capturedText: 'some text',
        settings: _testSettings(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('answer'), findsOneWidget);
  });

  testWidgets('pressing Esc calls onDismiss', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(MaterialApp(
      home: PopupScreen(
        controller: controller,
        capturedText: 'some text',
        settings: _testSettings(),
        onDismiss: () => dismissed = true,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(dismissed, isTrue);
  });

  testWidgets('the close button in ConversationView calls onDismiss', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(MaterialApp(
      home: PopupScreen(
        controller: controller,
        capturedText: 'some text',
        settings: _testSettings(),
        onDismiss: () => dismissed = true,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('closeButton')));

    expect(dismissed, isTrue);
  });
}
