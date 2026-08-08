import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:insight/app/settings_model.dart';
import 'package:insight/domain/session.dart';
import 'package:insight/services/clipboard_capture_service.dart';
import 'package:insight/services/history_repository.dart';
import 'package:insight/services/workers_ai_client.dart';
import 'package:insight/ui/session/session_controller.dart';

class MockWorkersAiClient extends Mock implements WorkersAiClient {}
class MockHistoryRepository extends Mock implements HistoryRepository {}
class MockClipboardAccess extends Mock implements ClipboardAccess {}

AppSettings _testSettings() => const AppSettings(
      accountId: 'acct',
      apiToken: 'token',
      model: 'model',
      promptTemplate: 'Explain: {{selection}}',
      shortcutKey: 'keyE',
      shortcutModifiers: ['meta'],
      launchAtLogin: false,
      themeMode: 'dark',
    );

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

  test('start sets noSelection status when nothing was captured', () async {
    await controller.start(capturedText: null, settings: _testSettings());

    expect(controller.status, SessionStatus.noSelection);
    expect(controller.session, isNull);
  });

  test('start sets error status when credentials are missing', () async {
    const settings = AppSettings(
      accountId: '',
      apiToken: '',
      model: 'm',
      promptTemplate: '{{selection}}',
      shortcutKey: 'keyE',
      shortcutModifiers: ['meta'],
      launchAtLogin: false,
      themeMode: 'dark',
    );

    await controller.start(capturedText: 'hi', settings: settings);

    expect(controller.status, SessionStatus.error);
    expect(controller.session, isNull);
  });

  test('start streams the initial assistant turn and saves it', () async {
    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer((_) => Stream.fromIterable(['Hel', 'lo']));

    await controller.start(capturedText: 'some text', settings: _testSettings());

    expect(controller.status, SessionStatus.active);
    expect(controller.session!.selectedText, 'some text');
    expect(controller.session!.turns, hasLength(1));
    expect(controller.session!.turns.single.role, TurnRole.assistant);
    expect(controller.session!.turns.single.content, 'Hello');
    expect(controller.isStreaming, isFalse);
    verify(() => historyRepository.save(any())).called(1);
  });

  test('start sends the substituted prompt as the first message', () async {
    late List<ChatMessage> sentMessages;
    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer((invocation) {
      sentMessages = invocation.namedArguments[#messages] as List<ChatMessage>;
      return Stream.fromIterable(['ok']);
    });

    await controller.start(capturedText: 'some text', settings: _testSettings());

    expect(sentMessages.single.role, ChatRole.user);
    expect(sentMessages.single.content, 'Explain: some text');
  });

  test('sendFollowUp appends a user turn then streams a new assistant turn', () async {
    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer((_) => Stream.fromIterable(['Hello']));
    await controller.start(capturedText: 'some text', settings: _testSettings());

    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer((_) => Stream.fromIterable(['Bonjour']));
    await controller.sendFollowUp('In French?');

    final turns = controller.session!.turns;
    expect(turns, hasLength(3));
    expect(turns[1].role, TurnRole.user);
    expect(turns[1].content, 'In French?');
    expect(turns[2].role, TurnRole.assistant);
    expect(turns[2].content, 'Bonjour');
  });

  test('regenerate replaces only the last assistant turn', () async {
    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer((_) => Stream.fromIterable(['first answer']));
    await controller.start(capturedText: 'some text', settings: _testSettings());

    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer((_) => Stream.fromIterable(['second answer']));
    await controller.regenerate();

    final turns = controller.session!.turns;
    expect(turns, hasLength(1));
    expect(turns.single.content, 'second answer');
  });

  test('regenerate on failure keeps the prior turn and shows an error', () async {
    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer((_) => Stream.fromIterable(['first answer']));
    await controller.start(capturedText: 'some text', settings: _testSettings());

    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer((_) => Stream.error(WorkersAiException('boom')));
    await controller.regenerate();

    final turns = controller.session!.turns;
    expect(turns, hasLength(1));
    expect(turns.single.content, 'first answer');
    expect(controller.status, SessionStatus.error);
  });

  test('resume loads an existing session without calling the AI client', () async {
    final existing = ExplanationSession(
      id: 'abc',
      selectedText: 'old text',
      createdAt: DateTime.now(),
      turns: [
        SessionTurn(role: TurnRole.assistant, content: 'old answer', timestamp: DateTime.now()),
      ],
    );

    controller.resume(existing, _testSettings());

    expect(controller.status, SessionStatus.active);
    expect(controller.session, existing);
    verifyNever(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        ));
  });

  test('copyLastResponse copies the last assistant turn to the clipboard', () async {
    when(() => client.streamChat(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
        )).thenAnswer((_) => Stream.fromIterable(['answer']));
    await controller.start(capturedText: 'some text', settings: _testSettings());

    await controller.copyLastResponse();

    verify(() => clipboard.writeText('answer')).called(1);
  });
}
