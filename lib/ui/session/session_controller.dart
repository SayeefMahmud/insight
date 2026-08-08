import 'package:flutter/foundation.dart';

import '../../app/settings_model.dart';
import '../../domain/session.dart';
import '../../services/clipboard_capture_service.dart';
import '../../services/history_repository.dart';
import '../../services/workers_ai_client.dart';

enum SessionStatus { loading, noSelection, active, error }

class SessionController extends ChangeNotifier {
  SessionController({
    required WorkersAiClient client,
    required HistoryRepository historyRepository,
    required ClipboardAccess clipboard,
  })  : _client = client,
        _historyRepository = historyRepository,
        _clipboard = clipboard;

  final WorkersAiClient _client;
  final HistoryRepository _historyRepository;
  final ClipboardAccess _clipboard;

  SessionStatus status = SessionStatus.loading;
  ExplanationSession? session;
  String errorMessage = '';
  bool isStreaming = false;

  AppSettings? _settings;

  Future<void> start({required String? capturedText, required AppSettings settings}) async {
    _settings = settings;
    if (capturedText == null) {
      status = SessionStatus.noSelection;
      notifyListeners();
      return;
    }
    if (settings.accountId.isEmpty || settings.apiToken.isEmpty) {
      status = SessionStatus.error;
      errorMessage =
          'Cloudflare account ID or API token is missing. Open Settings to configure.';
      notifyListeners();
      return;
    }

    session = ExplanationSession(
      id: generateSessionId(),
      selectedText: capturedText,
      createdAt: DateTime.now(),
      turns: const [],
    );
    status = SessionStatus.active;
    notifyListeners();
    await _streamNewAssistantTurn(baseTurns: const [], rollbackSession: session!);
  }

  void resume(ExplanationSession existingSession, AppSettings settings) {
    _settings = settings;
    session = existingSession;
    status = SessionStatus.active;
    notifyListeners();
  }

  Future<void> sendFollowUp(String question) async {
    if (session == null || question.trim().isEmpty) return;
    final withQuestion = [
      ...session!.turns,
      SessionTurn(role: TurnRole.user, content: question.trim(), timestamp: DateTime.now()),
    ];
    session = session!.copyWith(turns: withQuestion);
    notifyListeners();
    await _streamNewAssistantTurn(baseTurns: withQuestion, rollbackSession: session!);
  }

  Future<void> regenerate() async {
    if (session == null) return;
    final turns = session!.turns;
    if (turns.isEmpty || turns.last.role != TurnRole.assistant) return;
    final original = session!;
    final withoutLast = turns.sublist(0, turns.length - 1);
    await _streamNewAssistantTurn(baseTurns: withoutLast, rollbackSession: original);
  }

  Future<void> copyLastResponse() async {
    final turns = session?.turns;
    if (turns == null) return;
    for (final turn in turns.reversed) {
      if (turn.role == TurnRole.assistant) {
        await _clipboard.writeText(turn.content);
        return;
      }
    }
  }

  List<ChatMessage> _buildMessages(AppSettings settings, List<SessionTurn> turns) {
    final initialPrompt = settings.promptTemplate.replaceAll('{{selection}}', session!.selectedText);
    return [
      ChatMessage(role: ChatRole.user, content: initialPrompt),
      ...turns.map((t) => ChatMessage(
            role: t.role == TurnRole.user ? ChatRole.user : ChatRole.assistant,
            content: t.content,
          )),
    ];
  }

  Future<void> _streamNewAssistantTurn({
    required List<SessionTurn> baseTurns,
    required ExplanationSession rollbackSession,
  }) async {
    final settings = _settings!;
    isStreaming = true;
    status = SessionStatus.active;
    notifyListeners();

    final baseSession = session!.copyWith(turns: baseTurns);
    final messages = _buildMessages(settings, baseTurns);
    var buffer = '';
    var appended = false;
    try {
      await for (final chunk in _client.streamChat(
        accountId: settings.accountId,
        apiToken: settings.apiToken,
        model: settings.model,
        messages: messages,
      )) {
        buffer += chunk;
        final newTurn = SessionTurn(role: TurnRole.assistant, content: buffer, timestamp: DateTime.now());
        session = baseSession.copyWith(turns: [...baseTurns, newTurn]);
        appended = true;
        notifyListeners();
      }
      isStreaming = false;
      await _historyRepository.save(session!);
      notifyListeners();
    } catch (e) {
      isStreaming = false;
      session = appended ? session : rollbackSession;
      status = SessionStatus.error;
      errorMessage = e.toString();
      notifyListeners();
    }
  }
}
