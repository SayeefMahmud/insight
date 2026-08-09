import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:insight/app/settings_model.dart';
import 'package:insight/services/clipboard_capture_service.dart';
import 'package:insight/services/history_repository.dart';
import 'package:insight/services/workers_ai_client.dart';
import 'package:insight/domain/session.dart';
import 'package:insight/ui/session/conversation_view.dart';
import 'package:insight/ui/session/session_controller.dart';

class MockWorkersAiClient extends Mock implements WorkersAiClient {}
class MockHistoryRepository extends Mock implements HistoryRepository {}
class MockClipboardAccess extends Mock implements ClipboardAccess {}

void main() {
  late MockWorkersAiClient client;
  late MockHistoryRepository historyRepository;
  late MockClipboardAccess clipboard;
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
    client = MockWorkersAiClient();
    historyRepository = MockHistoryRepository();
    clipboard = MockClipboardAccess();
    when(() => historyRepository.save(any())).thenAnswer((_) async {});
    when(() => clipboard.writeText(any())).thenAnswer((_) async {});
    controller = SessionController(
      client: client,
      historyRepository: historyRepository,
      clipboard: clipboard,
    );
  });

  testWidgets('shows "No text selected" in the noSelection state', (tester) async {
    await controller.start(capturedText: null, settings: const _NoopSettings());

    await tester.pumpWidget(MaterialApp(
      home: ConversationView(controller: controller),
    ));

    expect(find.text('No text selected'), findsOneWidget);
  });

  testWidgets('renders turns and submits a follow-up', (tester) async {
    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer((_) => Stream.fromIterable(['Hello']));
    await controller.start(capturedText: 'some text', settings: const _NoopSettings());

    await tester.pumpWidget(MaterialApp(
      home: ConversationView(controller: controller),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Hello'), findsOneWidget);

    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer((_) => Stream.fromIterable(['Bonjour']));

    await tester.enterText(find.byKey(const Key('followUpField')), 'In French?');
    await tester.tap(find.byKey(const Key('sendButton')));
    await tester.pumpAndSettle();

    expect(find.text('In French?'), findsOneWidget);
    expect(find.text('Bonjour'), findsOneWidget);
  });

  testWidgets('auto-scrolls to the bottom when a new turn overflows the viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer(
            (_) => Stream.fromIterable([List.generate(20, (_) => 'first answer').join(' ')]));
    await controller.start(capturedText: 'some text', settings: const _NoopSettings());

    await tester.pumpWidget(MaterialApp(
      home: ConversationView(controller: controller),
    ));
    await tester.pumpAndSettle();

    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer(
            (_) => Stream.fromIterable([List.generate(20, (_) => 'second answer').join(' ')]));

    await tester.enterText(find.byKey(const Key('followUpField')), 'another question');
    await tester.tap(find.byKey(const Key('sendButton')));
    await tester.pumpAndSettle();

    final listView = tester.widget<ListView>(find.byKey(const Key('conversationScrollView')));
    final scrollController = listView.controller!;
    expect(scrollController.offset, scrollController.position.maxScrollExtent);
  });

  testWidgets('regenerate button re-runs the last turn', (tester) async {
    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer((_) => Stream.fromIterable(['first answer']));
    await controller.start(capturedText: 'some text', settings: const _NoopSettings());

    await tester.pumpWidget(MaterialApp(
      home: ConversationView(controller: controller),
    ));
    await tester.pumpAndSettle();

    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer((_) => Stream.fromIterable(['second answer']));
    await tester.tap(find.byKey(const Key('regenerateButton')));
    await tester.pumpAndSettle();

    expect(find.text('second answer'), findsOneWidget);
    expect(find.text('first answer'), findsNothing);
  });

  testWidgets('copy button copies the last response', (tester) async {
    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer((_) => Stream.fromIterable(['answer']));
    await controller.start(capturedText: 'some text', settings: const _NoopSettings());

    await tester.pumpWidget(MaterialApp(
      home: ConversationView(controller: controller),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('copyButton')));
    await tester.pumpAndSettle();

    verify(() => clipboard.writeText('answer')).called(1);
  });

  testWidgets('close button is only shown when onClose is provided', (tester) async {
    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer((_) => Stream.fromIterable(['answer']));
    await controller.start(capturedText: 'some text', settings: const _NoopSettings());
    var closed = false;

    await tester.pumpWidget(MaterialApp(
      home: ConversationView(controller: controller, onClose: () => closed = true),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('closeButton')));
    expect(closed, isTrue);
  });

  testWidgets('shows missing-credentials error with an Open Settings button', (tester) async {
    final freshController = SessionController(
      client: client,
      historyRepository: historyRepository,
      clipboard: clipboard,
    );
    var opened = false;
    await freshController.start(
      capturedText: 'text',
      settings: const _NoopSettings(accountId: '', apiToken: ''),
    );

    await tester.pumpWidget(MaterialApp(
      home: ConversationView(controller: freshController, onOpenSettings: () => opened = true),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('missing'), findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    expect(opened, isTrue);
  });
}

class _NoopSettings extends AppSettings {
  const _NoopSettings({String accountId = 'acct', String apiToken = 'token'})
      : super(
          accountId: accountId,
          apiToken: apiToken,
          model: 'model',
          promptTemplate: 'Explain: {{selection}}',
          shortcutKey: 'keyE',
          shortcutModifiers: const ['meta'],
          launchAtLogin: false,
          themeMode: 'dark',
        );
}
