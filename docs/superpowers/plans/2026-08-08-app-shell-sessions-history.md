# App Shell, Sessions & History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Insight from a tray-only, one-shot-explanation utility into a normal Dock app with a tabbed main window (Home/History/Settings), a light/dark theme toggle, and a popup that supports follow-up questions and regeneration as a resumable, saved session.

**Architecture:** A new `ExplanationSession`/`SessionTurn` data model is shared between the floating popup and a new History tab's detail view via one reusable `ConversationView` widget driven by a `SessionController`. Sessions persist to a JSON file via a new `HistoryRepository`. The main window gains a `MainAppScreen` tab shell (Home/History/Settings) navigated via a small `AppNavigation` notifier-pair, replacing the bare `SettingsScreen` as the window's content. `WorkersAiClient` becomes conversation-aware (`streamChat` over a `List<ChatMessage>`) instead of single-prompt.

**Tech Stack:** Flutter (existing macOS + Windows desktop targets), `path_provider` (new — history file location), all other existing dependencies (`tray_manager`, `hotkey_manager`, `window_manager`, `desktop_multi_window`, `http`, `shared_preferences`, `flutter_secure_storage`, `mocktail` for tests).

## Global Constraints

- History retention: sessions are pruned once their `lastActivityAt` (the last turn's timestamp, or `createdAt` if no turns) is more than 30 days old.
- No user-facing cap on history count within the 30-day window.
- Regenerate replaces only the current last assistant turn; on failure the prior turn is kept as-is (not cleared) and an inline error shown alongside it.
- Click-outside/window-blur no longer dismisses the popup; only Esc or an explicit close button do.
- Popup window: resizable, minimum 360×400, default 420×520.
- Theme toggle (`AppSettings.themeMode`, `light`|`dark`, default `dark`) controls both the main window and any popup opened afterward; applies without restart.
- Main window starts hidden on every launch (including "Launch at login"); opened via Dock icon, tray icon, or in-app navigation (e.g. "Open Settings").
- Closing the main window (native close button) hides it; it does not quit the app. Quit (tray menu) must actually terminate the process — a real fix, since `AppDelegate.swift` already returns `false` from `applicationShouldTerminateAfterLastWindowClosed` (needed so hiding the window at launch doesn't kill the app), which means `windowManager.close()` no longer doubles as quit.
- Dock icon: `LSUIElement` is removed from `macos/Runner/Info.plist` so the app appears in the Dock and Cmd+Tab, in addition to keeping the existing tray icon.

---

## File Structure

```
lib/
  app/
    settings_model.dart          # MODIFY: add themeMode field
    settings_repository.dart     # MODIFY: persist themeMode
  domain/
    session.dart                 # NEW: ExplanationSession, SessionTurn, TurnRole, generateSessionId()
  services/
    workers_ai_client.dart       # MODIFY: replace streamExplanation with streamChat(messages) + ChatMessage/ChatRole
    history_repository.dart      # NEW: HistoryFileStorage abstraction + HistoryRepository
    hotkey_service.dart          # MODIFY: becomes a ChangeNotifier so Home can reflect registrationFailed
    clipboard_capture_service.dart  # unchanged — ClipboardAccess reused by SessionController
    tray_service.dart            # unchanged
    auto_start_sync.dart         # unchanged
  ui/
    session/
      session_controller.dart    # NEW: replaces ui/popup/explanation_controller.dart
      conversation_view.dart     # NEW: shared turns list + input + regenerate/copy/close UI
    popup/
      popup_screen.dart          # MODIFY: hosts ConversationView instead of the old single-text view
      explanation_controller.dart  # DELETE: superseded by ui/session/session_controller.dart
    app/
      app_navigation.dart        # NEW: AppTab enum + AppNavigation (tab/session-selection notifiers)
      main_app_screen.dart       # NEW: top-tabs shell (Home/History/Settings)
    home/
      home_screen.dart           # NEW: recent activity + shortcut/status
    history/
      history_screen.dart        # NEW: search + list + detail (via ConversationView)
    settings/
      settings_screen.dart       # MODIFY: drop own Scaffold/AppBar, add theme toggle
      shortcut_recorder_field.dart # unchanged
  main.dart                      # MODIFY: Dock icon removal follow-through, quit fix, window-close-hides,
                                  #         popup resizing/min-size, tray "Settings" -> Settings tab, theming

macos/Runner/Info.plist          # MODIFY: remove LSUIElement

test/
  domain/session_test.dart
  services/workers_ai_client_test.dart     # MODIFY: streamChat instead of streamExplanation
  services/history_repository_test.dart
  services/hotkey_service_test.dart        # MODIFY: ChangeNotifier behavior
  ui/session/session_controller_test.dart
  ui/session/conversation_view_test.dart
  ui/popup/popup_screen_test.dart          # MODIFY: reflects new ConversationView-based screen
  ui/home/home_screen_test.dart
  ui/history/history_screen_test.dart
  ui/app/main_app_screen_test.dart
  ui/settings/settings_screen_test.dart    # MODIFY: theme toggle, no own Scaffold
  main_test.dart                            # MODIFY: computePopupFrame's default size changes to 420x520
```

---

### Task 1: Theme setting

**Files:**
- Modify: `lib/app/settings_model.dart`
- Modify: `lib/app/settings_repository.dart`
- Modify: `test/app/settings_repository_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `AppSettings.themeMode` (`String`, values `'light'`/`'dark'`, via `AppSettings.defaultThemeMode = 'dark'`), persisted by `SettingsRepository`.

- [ ] **Step 1: Update the failing test for the new field**

In `test/app/settings_repository_test.dart`, update every `AppSettings(...)` literal to also pass `themeMode: 'dark'` (the `save`/`load` round-trip test and the `save` rejects test and the `toJson`/`fromJson` test all construct `AppSettings` directly — add the field to each), and add an assertion to the defaults test:

```dart
  test('load returns defaults when nothing has been saved', () async {
    final settings = await repository.load();

    expect(settings.accountId, '');
    expect(settings.model, AppSettings.defaultModel);
    expect(settings.promptTemplate, AppSettings.defaultPromptTemplate);
    expect(settings.shortcutKey, AppSettings.defaultShortcutKey);
    expect(settings.shortcutModifiers, AppSettings.defaultShortcutModifiers);
    expect(settings.launchAtLogin, isFalse);
    expect(settings.themeMode, AppSettings.defaultThemeMode);
  });
```

Also add a new test:

```dart
  test('save persists themeMode', () async {
    const settings = AppSettings(
      accountId: 'a',
      apiToken: 't',
      model: 'm',
      promptTemplate: '{{selection}}',
      shortcutKey: 'keyE',
      shortcutModifiers: ['meta'],
      launchAtLogin: false,
      themeMode: 'light',
    );

    await repository.save(settings);
    final loaded = await repository.load();

    expect(loaded.themeMode, 'light');
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/app/settings_repository_test.dart`
Expected: FAIL — compile error, no `themeMode` parameter on `AppSettings`.

- [ ] **Step 3: Add the field to `AppSettings`**

In `lib/app/settings_model.dart`, add `required this.themeMode` to the constructor, `final String themeMode;` as a field, `static const defaultThemeMode = 'dark';`, and include `themeMode` in both `toJson()` (`'themeMode': themeMode`) and `fromJson()` (`themeMode: json['themeMode'] as String`).

- [ ] **Step 4: Persist it in `SettingsRepository`**

In `lib/app/settings_repository.dart`, add `static const _kThemeMode = 'themeMode';`, read it in `load()` as `themeMode: prefs.getString(_kThemeMode) ?? AppSettings.defaultThemeMode,`, and write it in `save()` as `await prefs.setString(_kThemeMode, settings.themeMode);`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/app/settings_repository_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Fix other call sites that construct `AppSettings`**

`themeMode` is a required field, so every other `AppSettings(...)` literal in the codebase now fails to compile. Run `grep -rn "AppSettings(" lib test` and add `themeMode: 'dark'` (or `AppSettings.defaultThemeMode`) to each literal found in `lib/services/hotkey_service.dart`'s doc comments (none — it doesn't construct one), `test/services/hotkey_service_test.dart`, `test/ui/popup/popup_screen_test.dart`, `test/ui/settings/settings_screen_test.dart`. Do not run the full suite yet — later tasks touch these same files.

- [ ] **Step 7: Commit**

```bash
git add lib/app/settings_model.dart lib/app/settings_repository.dart test/app/settings_repository_test.dart test/services/hotkey_service_test.dart test/ui/popup/popup_screen_test.dart test/ui/settings/settings_screen_test.dart
git commit -m "feat: add themeMode setting"
```

---

### Task 2: Session domain model

**Files:**
- Create: `lib/domain/session.dart`
- Test: `test/domain/session_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum TurnRole { user, assistant }`
  - `class SessionTurn { const SessionTurn({required TurnRole role, required String content, required DateTime timestamp}); final TurnRole role; final String content; final DateTime timestamp; Map<String, dynamic> toJson(); static SessionTurn fromJson(Map<String, dynamic> json); }`
  - `class ExplanationSession { const ExplanationSession({required String id, required String selectedText, required DateTime createdAt, required List<SessionTurn> turns}); final String id; final String selectedText; final DateTime createdAt; final List<SessionTurn> turns; DateTime get lastActivityAt; ExplanationSession copyWith({List<SessionTurn>? turns}); Map<String, dynamic> toJson(); static ExplanationSession fromJson(Map<String, dynamic> json); }`
  - `String generateSessionId()`

- [ ] **Step 1: Write the failing test**

Create `test/domain/session_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:insight/domain/session.dart';

void main() {
  test('generateSessionId returns unique non-empty ids', () {
    final a = generateSessionId();
    final b = generateSessionId();

    expect(a, isNotEmpty);
    expect(a, isNot(equals(b)));
  });

  test('SessionTurn round-trips through toJson/fromJson', () {
    final turn = SessionTurn(
      role: TurnRole.assistant,
      content: 'hello',
      timestamp: DateTime.utc(2026, 1, 1, 12),
    );

    final roundTripped = SessionTurn.fromJson(turn.toJson());

    expect(roundTripped.role, TurnRole.assistant);
    expect(roundTripped.content, 'hello');
    expect(roundTripped.timestamp, DateTime.utc(2026, 1, 1, 12));
  });

  test('lastActivityAt falls back to createdAt when there are no turns', () {
    final session = ExplanationSession(
      id: '1',
      selectedText: 'text',
      createdAt: DateTime.utc(2026, 1, 1),
      turns: const [],
    );

    expect(session.lastActivityAt, DateTime.utc(2026, 1, 1));
  });

  test('lastActivityAt uses the last turn timestamp when turns exist', () {
    final session = ExplanationSession(
      id: '1',
      selectedText: 'text',
      createdAt: DateTime.utc(2026, 1, 1),
      turns: [
        SessionTurn(role: TurnRole.assistant, content: 'a', timestamp: DateTime.utc(2026, 1, 2)),
        SessionTurn(role: TurnRole.user, content: 'b', timestamp: DateTime.utc(2026, 1, 3)),
      ],
    );

    expect(session.lastActivityAt, DateTime.utc(2026, 1, 3));
  });

  test('copyWith replaces turns and keeps other fields', () {
    final session = ExplanationSession(
      id: '1',
      selectedText: 'text',
      createdAt: DateTime.utc(2026, 1, 1),
      turns: const [],
    );
    final newTurns = [
      SessionTurn(role: TurnRole.assistant, content: 'a', timestamp: DateTime.utc(2026, 1, 2)),
    ];

    final updated = session.copyWith(turns: newTurns);

    expect(updated.id, '1');
    expect(updated.selectedText, 'text');
    expect(updated.turns, newTurns);
  });

  test('ExplanationSession round-trips through toJson/fromJson', () {
    final session = ExplanationSession(
      id: '1',
      selectedText: 'text',
      createdAt: DateTime.utc(2026, 1, 1),
      turns: [
        SessionTurn(role: TurnRole.assistant, content: 'a', timestamp: DateTime.utc(2026, 1, 2)),
      ],
    );

    final roundTripped = ExplanationSession.fromJson(session.toJson());

    expect(roundTripped.id, '1');
    expect(roundTripped.selectedText, 'text');
    expect(roundTripped.createdAt, DateTime.utc(2026, 1, 1));
    expect(roundTripped.turns.single.content, 'a');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/domain/session_test.dart`
Expected: FAIL — compile error, `lib/domain/session.dart` doesn't exist.

- [ ] **Step 3: Implement the model**

Create `lib/domain/session.dart`:

```dart
import 'dart:math';

enum TurnRole { user, assistant }

class SessionTurn {
  const SessionTurn({
    required this.role,
    required this.content,
    required this.timestamp,
  });

  final TurnRole role;
  final String content;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  static SessionTurn fromJson(Map<String, dynamic> json) => SessionTurn(
        role: TurnRole.values.byName(json['role'] as String),
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

class ExplanationSession {
  const ExplanationSession({
    required this.id,
    required this.selectedText,
    required this.createdAt,
    required this.turns,
  });

  final String id;
  final String selectedText;
  final DateTime createdAt;
  final List<SessionTurn> turns;

  DateTime get lastActivityAt => turns.isEmpty ? createdAt : turns.last.timestamp;

  ExplanationSession copyWith({List<SessionTurn>? turns}) => ExplanationSession(
        id: id,
        selectedText: selectedText,
        createdAt: createdAt,
        turns: turns ?? this.turns,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'selectedText': selectedText,
        'createdAt': createdAt.toIso8601String(),
        'turns': turns.map((t) => t.toJson()).toList(),
      };

  static ExplanationSession fromJson(Map<String, dynamic> json) => ExplanationSession(
        id: json['id'] as String,
        selectedText: json['selectedText'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        turns: (json['turns'] as List)
            .map((t) => SessionTurn.fromJson(t as Map<String, dynamic>))
            .toList(),
      );
}

String generateSessionId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/domain/session_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/session.dart test/domain/session_test.dart
git commit -m "feat: add ExplanationSession/SessionTurn domain model"
```

---

### Task 3: History repository

**Files:**
- Create: `lib/services/history_repository.dart`
- Test: `test/services/history_repository_test.dart`
- Modify: `pubspec.yaml` — add `path_provider`

**Interfaces:**
- Consumes: `ExplanationSession` (Task 2).
- Produces:
  - `abstract class HistoryFileStorage { Future<String?> read(); Future<void> write(String contents); }` and `LocalHistoryFileStorage implements HistoryFileStorage` (uses `path_provider`'s `getApplicationSupportDirectory()`).
  - `class HistoryRepository { HistoryRepository({HistoryFileStorage? storage}); Future<List<ExplanationSession>> loadAll(); Future<void> save(ExplanationSession session); Future<void> delete(String id); }` — `loadAll()` returns sessions sorted by `lastActivityAt` descending, with any older than 30 days pruned (and the pruned result persisted back). `save()` upserts by `id`. A corrupt/unreadable stored file is treated as empty history rather than thrown.

- [ ] **Step 1: Add the `path_provider` dependency**

```bash
flutter pub add path_provider
```

- [ ] **Step 2: Write the failing test**

Create `test/services/history_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:insight/domain/session.dart';
import 'package:insight/services/history_repository.dart';

class MockHistoryFileStorage extends Mock implements HistoryFileStorage {}

ExplanationSession _session({
  required String id,
  required DateTime lastActivity,
  String selectedText = 'text',
}) =>
    ExplanationSession(
      id: id,
      selectedText: selectedText,
      createdAt: lastActivity,
      turns: [
        SessionTurn(role: TurnRole.assistant, content: 'reply $id', timestamp: lastActivity),
      ],
    );

void main() {
  late MockHistoryFileStorage storage;
  late HistoryRepository repository;

  setUp(() {
    storage = MockHistoryFileStorage();
    repository = HistoryRepository(storage: storage);
  });

  test('loadAll returns empty list when nothing is stored', () async {
    when(() => storage.read()).thenAnswer((_) async => null);

    final result = await repository.loadAll();

    expect(result, isEmpty);
  });

  test('loadAll returns empty list when the stored file is corrupt', () async {
    when(() => storage.read()).thenAnswer((_) async => 'not valid json{{{');

    final result = await repository.loadAll();

    expect(result, isEmpty);
  });

  test('loadAll sorts by lastActivityAt descending', () async {
    final older = _session(id: 'older', lastActivity: DateTime.utc(2026, 1, 1));
    final newer = _session(id: 'newer', lastActivity: DateTime.utc(2026, 1, 5));
    when(() => storage.read()).thenAnswer((_) async => '[${_jsonOf(older)},${_jsonOf(newer)}]');

    final result = await repository.loadAll();

    expect(result.map((s) => s.id).toList(), ['newer', 'older']);
  });

  test('loadAll prunes sessions older than 30 days and persists the pruned list', () async {
    final stale = _session(
      id: 'stale',
      lastActivity: DateTime.now().subtract(const Duration(days: 31)),
    );
    final fresh = _session(id: 'fresh', lastActivity: DateTime.now());
    when(() => storage.read()).thenAnswer((_) async => '[${_jsonOf(stale)},${_jsonOf(fresh)}]');
    when(() => storage.write(any())).thenAnswer((_) async {});

    final result = await repository.loadAll();

    expect(result.map((s) => s.id).toList(), ['fresh']);
    final written = verify(() => storage.write(captureAny())).captured.single as String;
    expect(written, isNot(contains('stale')));
  });

  test('save upserts a session by id', () async {
    final existing = _session(id: '1', lastActivity: DateTime.utc(2026, 1, 1));
    when(() => storage.read()).thenAnswer((_) async => '[${_jsonOf(existing)}]');
    String? written;
    when(() => storage.write(any())).thenAnswer((invocation) async {
      written = invocation.positionalArguments.single as String;
    });

    final updated = existing.copyWith(turns: [
      ...existing.turns,
      SessionTurn(role: TurnRole.user, content: 'follow-up', timestamp: DateTime.utc(2026, 1, 2)),
    ]);
    await repository.save(updated);

    expect(written, contains('follow-up'));
    expect(written!.split('"id":"1"').length, 2); // appears exactly once, not duplicated
  });

  test('delete removes a session by id', () async {
    final a = _session(id: 'a', lastActivity: DateTime.utc(2026, 1, 1));
    final b = _session(id: 'b', lastActivity: DateTime.utc(2026, 1, 2));
    when(() => storage.read()).thenAnswer((_) async => '[${_jsonOf(a)},${_jsonOf(b)}]');
    String? written;
    when(() => storage.write(any())).thenAnswer((invocation) async {
      written = invocation.positionalArguments.single as String;
    });

    await repository.delete('a');

    expect(written, isNot(contains('"id":"a"')));
    expect(written, contains('"id":"b"'));
  });
}

String _jsonOf(ExplanationSession session) {
  final map = session.toJson();
  final buffer = StringBuffer('{');
  buffer.write('"id":"${map['id']}",');
  buffer.write('"selectedText":"${map['selectedText']}",');
  buffer.write('"createdAt":"${map['createdAt']}",');
  buffer.write('"turns":[');
  buffer.write((map['turns'] as List).map((t) {
    final turn = t as Map<String, dynamic>;
    return '{"role":"${turn['role']}","content":"${turn['content']}","timestamp":"${turn['timestamp']}"}';
  }).join(','));
  buffer.write(']}');
  return buffer.toString();
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/services/history_repository_test.dart`
Expected: FAIL — compile error, `HistoryFileStorage`/`HistoryRepository` not defined.

- [ ] **Step 4: Implement the repository**

Create `lib/services/history_repository.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/session.dart';

abstract class HistoryFileStorage {
  Future<String?> read();
  Future<void> write(String contents);
}

class LocalHistoryFileStorage implements HistoryFileStorage {
  static const _fileName = 'history.json';

  @override
  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String contents) async {
    final file = await _file();
    await file.writeAsString(contents);
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }
}

class HistoryRepository {
  HistoryRepository({HistoryFileStorage? storage})
      : _storage = storage ?? LocalHistoryFileStorage();

  final HistoryFileStorage _storage;
  static const _retentionWindow = Duration(days: 30);

  Future<List<ExplanationSession>> loadAll() async {
    final all = await _readAll();
    final cutoff = DateTime.now().subtract(_retentionWindow);
    final fresh = all.where((s) => s.lastActivityAt.isAfter(cutoff)).toList()
      ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
    if (fresh.length != all.length) {
      await _writeAll(fresh);
    }
    return fresh;
  }

  Future<void> save(ExplanationSession session) async {
    final all = await _readAll();
    final index = all.indexWhere((s) => s.id == session.id);
    if (index >= 0) {
      all[index] = session;
    } else {
      all.add(session);
    }
    await _writeAll(all);
  }

  Future<void> delete(String id) async {
    final all = await _readAll();
    all.removeWhere((s) => s.id == id);
    await _writeAll(all);
  }

  Future<List<ExplanationSession>> _readAll() async {
    final contents = await _storage.read();
    if (contents == null || contents.isEmpty) return [];
    try {
      final list = jsonDecode(contents) as List;
      return list.map((e) => ExplanationSession.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeAll(List<ExplanationSession> sessions) async {
    await _storage.write(jsonEncode(sessions.map((s) => s.toJson()).toList()));
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/services/history_repository_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/services/history_repository.dart test/services/history_repository_test.dart
git commit -m "feat: add JSON-file-backed history repository with 30-day retention"
```

---

### Task 4: Multi-turn Workers AI client

**Files:**
- Modify: `lib/services/workers_ai_client.dart`
- Modify: `test/services/workers_ai_client_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `enum ChatRole { user, assistant }`, `class ChatMessage { const ChatMessage({required ChatRole role, required String content}); Map<String, dynamic> toJson(); }`, and replaces `WorkersAiClient.streamExplanation(...)` with `Stream<String> streamChat({required String accountId, required String apiToken, required String model, required List<ChatMessage> messages})`. `WorkersAiException` is unchanged.

- [ ] **Step 1: Update the failing test**

Replace the contents of `test/services/workers_ai_client_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:insight/services/workers_ai_client.dart';

void main() {
  test('streams decoded text chunks from an SSE payload', () async {
    final sseBody = 'data: {"response":"Hello"}\n\n'
        'data: {"response":" world"}\n\n'
        'data: [DONE]\n\n';
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.url.toString(), contains('/accounts/acct/ai/run/'));
      return http.Response(sseBody, 200);
    });
    final aiClient = WorkersAiClient(httpClient: client);

    final chunks = await aiClient
        .streamChat(
          accountId: 'acct',
          apiToken: 'test-token',
          model: '@cf/meta/llama-3.1-8b-instruct',
          messages: const [ChatMessage(role: ChatRole.user, content: 'Explain: hi')],
        )
        .toList();

    expect(chunks.join(), 'Hello world');
  });

  test('sends the full conversation as the messages array', () async {
    late String sentBody;
    final capturingClient = MockClient((request) async {
      sentBody = utf8.decode(request.bodyBytes);
      return http.Response('data: [DONE]\n\n', 200);
    });
    final aiClient = WorkersAiClient(httpClient: capturingClient);

    await aiClient
        .streamChat(
          accountId: 'acct',
          apiToken: 'token',
          model: 'm',
          messages: const [
            ChatMessage(role: ChatRole.user, content: 'Explain: hi'),
            ChatMessage(role: ChatRole.assistant, content: 'It means hello.'),
            ChatMessage(role: ChatRole.user, content: 'In French?'),
          ],
        )
        .toList();

    expect(sentBody, contains('"role":"user"'));
    expect(sentBody, contains('"role":"assistant"'));
    expect(sentBody, contains('In French?'));
  });

  test('throws WorkersAiException on a non-200 response', () async {
    final client = MockClient((request) async => http.Response('bad token', 401));
    final aiClient = WorkersAiClient(httpClient: client);

    expect(
      () => aiClient
          .streamChat(
            accountId: 'acct',
            apiToken: 'bad',
            model: 'm',
            messages: const [ChatMessage(role: ChatRole.user, content: 'p')],
          )
          .toList(),
      throwsA(isA<WorkersAiException>()),
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/services/workers_ai_client_test.dart`
Expected: FAIL — compile error, `ChatMessage`/`ChatRole`/`streamChat` not defined.

- [ ] **Step 3: Implement the multi-turn client**

Replace the contents of `lib/services/workers_ai_client.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class WorkersAiException implements Exception {
  WorkersAiException(this.message);
  final String message;

  @override
  String toString() => message;
}

enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  final ChatRole role;
  final String content;

  Map<String, dynamic> toJson() => {'role': role.name, 'content': content};
}

class WorkersAiClient {
  WorkersAiClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Stream<String> streamChat({
    required String accountId,
    required String apiToken,
    required String model,
    required List<ChatMessage> messages,
  }) async* {
    final uri = Uri.parse(
      'https://api.cloudflare.com/client/v4/accounts/$accountId/ai/run/$model',
    );
    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $apiToken'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'messages': messages.map((m) => m.toJson()).toList(),
        'stream': true,
      });

    final streamedResponse = await _httpClient.send(request);

    if (streamedResponse.statusCode != 200) {
      final body = await streamedResponse.stream.bytesToString();
      throw WorkersAiException(
        'Workers AI request failed (${streamedResponse.statusCode}): $body',
      );
    }

    final lines =
        streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data.isEmpty) continue;
      if (data == '[DONE]') break;
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      final chunk = decoded['response'] as String?;
      if (chunk != null && chunk.isNotEmpty) {
        yield chunk;
      }
    }
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/services/workers_ai_client_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/workers_ai_client.dart test/services/workers_ai_client_test.dart
git commit -m "feat: make WorkersAiClient conversation-aware (streamChat over messages)"
```

---

### Task 5: Session controller

**Files:**
- Create: `lib/ui/session/session_controller.dart`
- Delete: `lib/ui/popup/explanation_controller.dart`
- Delete: `test/ui/popup/popup_screen_test.dart` (rewritten against the new screen in Task 7; deleting now avoids a stale intermediate compile failure since it imports `explanation_controller.dart`)
- Test: `test/ui/session/session_controller_test.dart`

**Interfaces:**
- Consumes: `AppSettings` (Task 1), `ExplanationSession`/`SessionTurn`/`TurnRole`/`generateSessionId` (Task 2), `HistoryRepository` (Task 3), `WorkersAiClient`/`ChatMessage`/`ChatRole`/`WorkersAiException` (Task 4), `ClipboardAccess` (existing, from `lib/services/clipboard_capture_service.dart`).
- Produces:
  - `enum SessionStatus { loading, noSelection, active, error }`
  - `class SessionController extends ChangeNotifier { SessionController({required WorkersAiClient client, required HistoryRepository historyRepository, required ClipboardAccess clipboard}); SessionStatus status; ExplanationSession? session; String errorMessage; bool isStreaming; Future<void> start({required String? capturedText, required AppSettings settings}); void resume(ExplanationSession session, AppSettings settings); Future<void> sendFollowUp(String question); Future<void> regenerate(); Future<void> copyLastResponse(); }`

- [ ] **Step 1: Delete the superseded files**

```bash
git rm lib/ui/popup/explanation_controller.dart test/ui/popup/popup_screen_test.dart
```

- [ ] **Step 2: Write the failing test**

Create `test/ui/session/session_controller_test.dart`:

```dart
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
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/ui/session/session_controller_test.dart`
Expected: FAIL — compile error, `lib/ui/session/session_controller.dart` doesn't exist.

- [ ] **Step 4: Implement the controller**

Create `lib/ui/session/session_controller.dart`:

```dart
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/ui/session/session_controller_test.dart`
Expected: PASS (9 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/ui/session/session_controller.dart test/ui/session/session_controller_test.dart
git commit -m "feat: add SessionController (follow-ups, regenerate, resume, auto-save)"
```

(The Step 1 deletions of `lib/ui/popup/explanation_controller.dart` and `test/ui/popup/popup_screen_test.dart` are already staged from `git rm` and are included in this same commit.)

---

### Task 6: Conversation view widget

**Files:**
- Create: `lib/ui/session/conversation_view.dart`
- Test: `test/ui/session/conversation_view_test.dart`

**Interfaces:**
- Consumes: `SessionController`/`SessionStatus` (Task 5), `TurnRole` (Task 2).
- Produces: `class ConversationView extends StatefulWidget { const ConversationView({required SessionController controller, VoidCallback? onOpenSettings, VoidCallback? onClose}); }` — renders loading/no-selection/missing-credentials states, the turn list with a follow-up input, and header actions keyed `Key('regenerateButton')`, `Key('copyButton')`, `Key('closeButton')` (only shown when `onClose` is provided), plus a `Key('followUpField')` input and `Key('sendButton')`.

- [ ] **Step 1: Write the failing test**

Create `test/ui/session/conversation_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:insight/app/settings_model.dart';
import 'package:insight/services/clipboard_capture_service.dart';
import 'package:insight/services/history_repository.dart';
import 'package:insight/services/workers_ai_client.dart';
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
```

Add this settings helper at the bottom of the same test file, below `void main() { ... }`:

```dart
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/session/conversation_view_test.dart`
Expected: FAIL — compile error, `lib/ui/session/conversation_view.dart` doesn't exist.

- [ ] **Step 3: Implement the widget**

Create `lib/ui/session/conversation_view.dart`:

```dart
import 'package:flutter/material.dart';

import '../../domain/session.dart';
import 'session_controller.dart';

class ConversationView extends StatefulWidget {
  const ConversationView({
    super.key,
    required this.controller,
    this.onOpenSettings,
    this.onClose,
  });

  final SessionController controller;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onClose;

  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  final _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _inputController.text;
    if (text.trim().isEmpty) return;
    _inputController.clear();
    widget.controller.sendFollowUp(text);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        switch (controller.status) {
          case SessionStatus.loading:
            return const Center(
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          case SessionStatus.noSelection:
            return const Center(child: Text('No text selected'));
          case SessionStatus.error:
            if (controller.session == null) {
              return _MissingCredentialsError(
                message: controller.errorMessage,
                onOpenSettings: widget.onOpenSettings,
              );
            }
            return _buildSession(controller, showError: true);
          case SessionStatus.active:
            return _buildSession(controller, showError: false);
        }
      },
    );
  }

  Widget _buildSession(SessionController controller, {required bool showError}) {
    final session = controller.session!;
    final hasAssistantTurn = session.turns.any((t) => t.role == TurnRole.assistant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  session.selectedText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                key: const Key('regenerateButton'),
                icon: const Icon(Icons.refresh),
                tooltip: 'Regenerate',
                onPressed: (!controller.isStreaming && hasAssistantTurn)
                    ? controller.regenerate
                    : null,
              ),
              IconButton(
                key: const Key('copyButton'),
                icon: const Icon(Icons.copy),
                tooltip: 'Copy last response',
                onPressed: hasAssistantTurn ? controller.copyLastResponse : null,
              ),
              if (widget.onClose != null)
                IconButton(
                  key: const Key('closeButton'),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: widget.onClose,
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final turn in session.turns)
                Align(
                  alignment:
                      turn.role == TurnRole.user ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 320),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: turn.role == TurnRole.user
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(turn.content),
                  ),
                ),
              if (controller.isStreaming &&
                  (session.turns.isEmpty || session.turns.last.role != TurnRole.assistant))
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (showError)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    controller.errorMessage,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('followUpField'),
                  controller: _inputController,
                  enabled: !controller.isStreaming,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    hintText: 'Ask a follow-up...',
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                key: const Key('sendButton'),
                icon: const Icon(Icons.send),
                onPressed: controller.isStreaming ? null : _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MissingCredentialsError extends StatelessWidget {
  const _MissingCredentialsError({required this.message, this.onOpenSettings});

  final String message;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(message, style: const TextStyle(color: Colors.redAccent)),
          ),
          if (onOpenSettings != null)
            TextButton(onPressed: onOpenSettings, child: const Text('Open Settings')),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/ui/session/conversation_view_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/session/conversation_view.dart test/ui/session/conversation_view_test.dart
git commit -m "feat: add ConversationView (shared turn list, follow-up input, actions)"
```

---

### Task 7: Popup screen rewrite

**Files:**
- Modify: `lib/ui/popup/popup_screen.dart`
- Test: `test/ui/popup/popup_screen_test.dart` (re-created — deleted in Task 5)

**Interfaces:**
- Consumes: `SessionController` (Task 5), `ConversationView` (Task 6).
- Produces: `class PopupScreen extends StatefulWidget { const PopupScreen({required SessionController controller, required String? capturedText, required AppSettings settings, VoidCallback? onOpenSettings, VoidCallback? onDismiss}); }` — starts the session on init, embeds `ConversationView` (passing `onClose: onDismiss`), and still closes on Esc (click-outside/blur dismissal is removed — that's a `main.dart` change in Task 13, not this screen).

- [ ] **Step 1: Write the failing test**

Create `test/ui/popup/popup_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:insight/app/settings_model.dart';
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/popup/popup_screen_test.dart`
Expected: FAIL — compile error, `PopupScreen` still references the deleted `ExplanationController`/`PopupStatus`.

- [ ] **Step 3: Rewrite the screen**

Replace the contents of `lib/ui/popup/popup_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/settings_model.dart';
import '../session/conversation_view.dart';
import '../session/session_controller.dart';

class PopupScreen extends StatefulWidget {
  const PopupScreen({
    super.key,
    required this.controller,
    required this.capturedText,
    required this.settings,
    this.onOpenSettings,
    this.onDismiss,
  });

  final SessionController controller;
  final String? capturedText;
  final AppSettings settings;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onDismiss;

  @override
  State<PopupScreen> createState() => _PopupScreenState();
}

class _PopupScreenState extends State<PopupScreen> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.start(capturedText: widget.capturedText, settings: widget.settings);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismiss?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Material(
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ConversationView(
          controller: widget.controller,
          onOpenSettings: widget.onOpenSettings,
          onClose: widget.onDismiss,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/ui/popup/popup_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/popup/popup_screen.dart test/ui/popup/popup_screen_test.dart
git commit -m "feat: rewrite PopupScreen to host ConversationView"
```

---

### Task 8: Observable hotkey status

**Files:**
- Modify: `lib/services/hotkey_service.dart`
- Modify: `test/services/hotkey_service_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `HotkeyService` becomes `class HotkeyService extends ChangeNotifier`, calling `notifyListeners()` whenever `registrationFailed` changes value (so `HomeScreen`, Task 9, can react to it the same way the tray's conflict warning already does).

- [ ] **Step 1: Update the failing test**

In `test/services/hotkey_service_test.dart`, add `themeMode: 'dark'` to both `AppSettings(...)` literals (per Task 1), and add a new test:

```dart
  test('notifies listeners when registrationFailed changes', () async {
    final controller = MockHotkeyController();
    when(() => controller.unregisterAll()).thenAnswer((_) async {});
    when(() => controller.register(any(), onKeyDown: any(named: 'onKeyDown')))
        .thenAnswer((_) async {});
    final service = HotkeyService(controller);
    var notified = false;
    service.addListener(() => notified = true);

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

    expect(notified, isTrue);
    expect(service.registrationFailed, isFalse);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/services/hotkey_service_test.dart`
Expected: FAIL — `HotkeyService` has no `addListener` (not a `ChangeNotifier` yet).

- [ ] **Step 3: Make `HotkeyService` a `ChangeNotifier`**

In `lib/services/hotkey_service.dart`, change the import and class declaration:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../app/settings_model.dart';
```

(add the `foundation.dart` import above the existing `services.dart` one), then change:

```dart
class HotkeyService {
  HotkeyService(this._controller);

  final HotkeyController _controller;
  bool _registrationFailed = false;
  bool get registrationFailed => _registrationFailed;

  Future<void> applyShortcut(AppSettings settings, void Function() onTriggered) async {
    await _controller.unregisterAll();
    final hotKey = HotKey(
      key: _mapKey(settings.shortcutKey),
      modifiers: settings.shortcutModifiers.map(_mapModifier).toList(),
      scope: HotKeyScope.system,
    );
    try {
      await _controller.register(hotKey, onKeyDown: (_) => onTriggered());
      _registrationFailed = false;
    } catch (_) {
      _registrationFailed = true;
    }
  }
}
```

to:

```dart
class HotkeyService extends ChangeNotifier {
  HotkeyService(this._controller);

  final HotkeyController _controller;
  bool _registrationFailed = false;
  bool get registrationFailed => _registrationFailed;

  Future<void> applyShortcut(AppSettings settings, void Function() onTriggered) async {
    await _controller.unregisterAll();
    final hotKey = HotKey(
      key: _mapKey(settings.shortcutKey),
      modifiers: settings.shortcutModifiers.map(_mapModifier).toList(),
      scope: HotKeyScope.system,
    );
    try {
      await _controller.register(hotKey, onKeyDown: (_) => onTriggered());
      _registrationFailed = false;
    } catch (_) {
      _registrationFailed = true;
    }
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/services/hotkey_service_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/hotkey_service.dart test/services/hotkey_service_test.dart
git commit -m "feat: make HotkeyService observable for the Home tab's status indicator"
```

---

### Task 9: App navigation + Home tab

**Files:**
- Create: `lib/ui/app/app_navigation.dart`
- Create: `lib/ui/home/home_screen.dart`
- Test: `test/ui/home/home_screen_test.dart`

**Interfaces:**
- Consumes: `SettingsRepository`/`AppSettings` (existing + Task 1), `HistoryRepository`/`ExplanationSession` (Task 3, Task 2), `HotkeyService` (Task 8).
- Produces:
  - `enum AppTab { home, history, settings }`
  - `class AppNavigation { AppNavigation(); ValueNotifier<AppTab> activeTab; ValueNotifier<String?> selectedSessionId; void goToSettings(); void openSession(String id); }`
  - `class HomeScreen extends StatefulWidget { const HomeScreen({required SettingsRepository settingsRepository, required HistoryRepository historyRepository, required HotkeyService hotkeyService, required AppNavigation navigation}); }` — shows the current shortcut binding, a registered/conflict status (keyed `Key('shortcutStatus')`), and up to 5 recent sessions (each keyed `Key('recent-<id>')`, tapping calls `navigation.openSession(id)`).

- [ ] **Step 1: Write the failing test**

Create `test/ui/home/home_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/home/home_screen_test.dart`
Expected: FAIL — compile error, `lib/ui/app/app_navigation.dart` and `lib/ui/home/home_screen.dart` don't exist.

- [ ] **Step 3: Implement `AppNavigation`**

Create `lib/ui/app/app_navigation.dart`:

```dart
import 'package:flutter/foundation.dart';

enum AppTab { home, history, settings }

class AppNavigation {
  AppNavigation()
      : activeTab = ValueNotifier(AppTab.home),
        selectedSessionId = ValueNotifier(null);

  final ValueNotifier<AppTab> activeTab;
  final ValueNotifier<String?> selectedSessionId;

  void goToSettings() => activeTab.value = AppTab.settings;

  void openSession(String id) {
    selectedSessionId.value = id;
    activeTab.value = AppTab.history;
  }
}
```

- [ ] **Step 4: Implement `HomeScreen`**

Create `lib/ui/home/home_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../app/settings_model.dart';
import '../../app/settings_repository.dart';
import '../../domain/session.dart';
import '../../services/history_repository.dart';
import '../../services/hotkey_service.dart';
import '../app/app_navigation.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.settingsRepository,
    required this.historyRepository,
    required this.hotkeyService,
    required this.navigation,
  });

  final SettingsRepository settingsRepository;
  final HistoryRepository historyRepository;
  final HotkeyService hotkeyService;
  final AppNavigation navigation;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppSettings? _settings;
  List<ExplanationSession> _recent = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.settingsRepository.load();
    final sessions = await widget.historyRepository.loadAll();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _recent = sessions.take(5).toList();
    });
  }

  String _describeShortcut(AppSettings settings) {
    final modLabels =
        settings.shortcutModifiers.map((m) => m[0].toUpperCase() + m.substring(1)).join('+');
    final keyLabel = settings.shortcutKey.replaceFirst('key', '').toUpperCase();
    return modLabels.isEmpty ? keyLabel : '$modLabels+$keyLabel';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.hotkeyService,
      builder: (context, _) {
        final settings = _settings;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                key: const Key('shortcutStatus'),
                leading: Icon(
                  widget.hotkeyService.registrationFailed ? Icons.warning : Icons.check_circle,
                  color: widget.hotkeyService.registrationFailed ? Colors.orange : Colors.green,
                ),
                title: Text(
                  settings == null ? 'Loading...' : 'Shortcut: ${_describeShortcut(settings)}',
                ),
                subtitle: Text(
                  widget.hotkeyService.registrationFailed
                      ? 'Conflict — rebind in Settings'
                      : 'Registered',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Recent activity', style: Theme.of(context).textTheme.titleMedium),
            if (_recent.isEmpty)
              const Padding(padding: EdgeInsets.all(8), child: Text('No explanations yet')),
            for (final session in _recent)
              ListTile(
                key: Key('recent-${session.id}'),
                title: Text(session.selectedText, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => widget.navigation.openSession(session.id),
              ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/ui/home/home_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/ui/app/app_navigation.dart lib/ui/home/home_screen.dart test/ui/home/home_screen_test.dart
git commit -m "feat: add AppNavigation and Home tab (shortcut status + recent activity)"
```

---

### Task 10: History tab

**Files:**
- Create: `lib/ui/history/history_screen.dart`
- Test: `test/ui/history/history_screen_test.dart`

**Interfaces:**
- Consumes: `HistoryRepository`/`ExplanationSession`/`SessionTurn`/`TurnRole` (Tasks 2–3), `WorkersAiClient` (Task 4), `SessionController` (Task 5), `ConversationView` (Task 6), `ClipboardAccess` (existing), `SettingsRepository` (existing), `AppNavigation` (Task 9).
- Produces: `class HistoryScreen extends StatefulWidget { const HistoryScreen({required HistoryRepository historyRepository, required WorkersAiClient client, required ClipboardAccess clipboard, required SettingsRepository settingsRepository, required AppNavigation navigation}); }` — a search field (`Key('searchField')`) over a list (`Key('history-<id>')` per row); tapping a row opens a resumable detail view (`Key('backButton')`, `Key('deleteButton')`, embedding `ConversationView`); also reacts when `navigation.selectedSessionId` is set externally (e.g. from Home) by opening that session's detail view.

- [ ] **Step 1: Write the failing test**

Create `test/ui/history/history_screen_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/history/history_screen_test.dart`
Expected: FAIL — compile error, `lib/ui/history/history_screen.dart` doesn't exist.

- [ ] **Step 3: Implement the screen**

Create `lib/ui/history/history_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../app/settings_repository.dart';
import '../../domain/session.dart';
import '../../services/clipboard_capture_service.dart';
import '../../services/history_repository.dart';
import '../../services/workers_ai_client.dart';
import '../app/app_navigation.dart';
import '../session/conversation_view.dart';
import '../session/session_controller.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.historyRepository,
    required this.client,
    required this.clipboard,
    required this.settingsRepository,
    required this.navigation,
  });

  final HistoryRepository historyRepository;
  final WorkersAiClient client;
  final ClipboardAccess clipboard;
  final SettingsRepository settingsRepository;
  final AppNavigation navigation;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<ExplanationSession> _all = const [];
  String _query = '';
  String? _selectedId;
  SessionController? _detailController;

  @override
  void initState() {
    super.initState();
    _load();
    widget.navigation.selectedSessionId.addListener(_onExternalSelection);
  }

  @override
  void dispose() {
    widget.navigation.selectedSessionId.removeListener(_onExternalSelection);
    super.dispose();
  }

  void _onExternalSelection() {
    final id = widget.navigation.selectedSessionId.value;
    if (id != null) {
      _openSession(id);
      widget.navigation.selectedSessionId.value = null;
    }
  }

  Future<void> _load() async {
    final sessions = await widget.historyRepository.loadAll();
    if (!mounted) return;
    setState(() => _all = sessions);
  }

  List<ExplanationSession> get _filtered {
    if (_query.isEmpty) return _all;
    final q = _query.toLowerCase();
    return _all.where((s) {
      if (s.selectedText.toLowerCase().contains(q)) return true;
      return s.turns.any((t) => t.content.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _openSession(String id) async {
    final session = _all.firstWhere((s) => s.id == id);
    final settings = await widget.settingsRepository.load();
    final controller = SessionController(
      client: widget.client,
      historyRepository: widget.historyRepository,
      clipboard: widget.clipboard,
    );
    controller.resume(session, settings);
    if (!mounted) return;
    setState(() {
      _selectedId = id;
      _detailController = controller;
    });
  }

  Future<void> _delete(String id) async {
    await widget.historyRepository.delete(id);
    await _load();
    setState(() {
      _selectedId = null;
      _detailController = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedId != null && _detailController != null) {
      return Column(
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('backButton'),
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _selectedId = null;
                  _detailController = null;
                }),
              ),
              IconButton(
                key: const Key('deleteButton'),
                icon: const Icon(Icons.delete),
                onPressed: () => _delete(_selectedId!),
              ),
            ],
          ),
          Expanded(child: ConversationView(controller: _detailController!)),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            key: const Key('searchField'),
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(hintText: 'Search history...'),
          ),
        ),
        Expanded(
          child: _filtered.isEmpty
              ? const Center(child: Text('No matching history'))
              : ListView(
                  children: [
                    for (final session in _filtered)
                      ListTile(
                        key: Key('history-${session.id}'),
                        title: Text(
                          session.selectedText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${session.turns.length} turn(s)'),
                        onTap: () => _openSession(session.id),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/ui/history/history_screen_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/history/history_screen.dart test/ui/history/history_screen_test.dart
git commit -m "feat: add History tab (search, resumable detail view, delete)"
```

---

### Task 11: Settings screen — embed in tab shell, add theme toggle

**Files:**
- Modify: `lib/ui/settings/settings_screen.dart`
- Modify: `test/ui/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes: `AppSettings.themeMode` (Task 1).
- Produces: `SettingsScreen` no longer wraps itself in its own `Scaffold`/`AppBar` (the tab shell built in Task 12 provides those) and gains a `Key('themeToggle')` `SwitchListTile` for dark/light mode, saved via the existing `onSaved` flow.

- [ ] **Step 1: Update the failing test**

Replace the contents of `test/ui/settings/settings_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:insight/app/settings_model.dart';
import 'package:insight/app/settings_repository.dart';
import 'package:insight/ui/settings/settings_screen.dart';

class MockSecureStorage extends Mock implements SecureStorage {}

void main() {
  late MockSecureStorage secureStorage;
  late SettingsRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStorage = MockSecureStorage();
    when(() => secureStorage.read(key: any(named: 'key')))
        .thenAnswer((_) async => null);
    when(() => secureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        )).thenAnswer((_) async {});
    repository = SettingsRepository(secureStorage: secureStorage);
  });

  Widget buildScreen({VoidCallback? onSaved}) => MaterialApp(
        home: Scaffold(body: SettingsScreen(repository: repository, onSaved: onSaved)),
      );

  testWidgets('loads existing settings into the form', (tester) async {
    await repository.save(const AppSettings(
      accountId: 'acct-1',
      apiToken: 'tok',
      model: 'model-x',
      promptTemplate: 'Explain: {{selection}}',
      shortcutKey: 'keyE',
      shortcutModifiers: ['meta', 'shift'],
      launchAtLogin: true,
      themeMode: 'light',
    ));
    when(() => secureStorage.read(key: 'apiToken')).thenAnswer((_) async => 'tok');

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'acct-1'), findsOneWidget);
  });

  testWidgets('shows a validation error when saving a template missing {{selection}}', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('promptTemplateField')), 'no placeholder');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Prompt template must contain {{selection}}'), findsOneWidget);
  });

  testWidgets('calls onSaved after a successful save', (tester) async {
    var savedCount = 0;
    await tester.pumpWidget(buildScreen(onSaved: () => savedCount++));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedCount, 1);
  });

  testWidgets('picking a model from the dropdown fills the model field', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('modelDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(kCommonWorkersAiModels.first).last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, kCommonWorkersAiModels.first), findsOneWidget);
  });

  testWidgets('toggling dark mode and saving persists themeMode', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('themeToggle')));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = await repository.load();
    expect(saved.themeMode, isNot(AppSettings.defaultThemeMode));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/settings/settings_screen_test.dart`
Expected: FAIL — no `Scaffold`/`AppBar` expectation issue yet, but `Key('themeToggle')` doesn't exist and the screen still wraps its own `Scaffold` (nesting one `Scaffold` inside another is legal in Flutter but the test builds its own `Scaffold` around `SettingsScreen`, which is fine either way — the real failure is the missing theme toggle).

- [ ] **Step 3: Update the screen**

In `lib/ui/settings/settings_screen.dart`, add a `bool _isDarkMode = true;` state field (initialized from settings in `_load()`), include it in the `AppSettings(...)` constructed by `_save()` as `themeMode: _isDarkMode ? 'dark' : 'light'`, add `themeMode: settings.themeMode == 'dark'` handling in `_load()` (`_isDarkMode = settings.themeMode == 'dark';`), remove the `Scaffold`/`AppBar` wrapper so `build()` returns the `Padding` directly, and add the toggle to the `ListView`'s children (right after the `SwitchListTile` for "Launch at login"):

```dart
  bool _isDarkMode = true;
```

(add alongside the other state fields)

```dart
  Future<void> _load() async {
    final settings = await widget.repository.load();
    setState(() {
      _accountIdController.text = settings.accountId;
      _apiTokenController.text = settings.apiToken;
      _modelController.text = settings.model;
      _promptTemplateController.text = settings.promptTemplate;
      _launchAtLogin = settings.launchAtLogin;
      _shortcutKey = settings.shortcutKey;
      _shortcutModifiers = settings.shortcutModifiers;
      _isDarkMode = settings.themeMode == 'dark';
    });
  }
```

```dart
  Future<void> _save() async {
    if (!_promptTemplateController.text.contains('{{selection}}')) {
      setState(() => _validationError = 'Prompt template must contain {{selection}}');
      return;
    }
    setState(() => _validationError = null);
    await widget.repository.save(AppSettings(
      accountId: _accountIdController.text,
      apiToken: _apiTokenController.text,
      model: _modelController.text,
      promptTemplate: _promptTemplateController.text,
      shortcutKey: _shortcutKey,
      shortcutModifiers: _shortcutModifiers,
      launchAtLogin: _launchAtLogin,
      themeMode: _isDarkMode ? 'dark' : 'light',
    ));
    widget.onSaved?.call();
  }
```

```dart
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          TextField(
            controller: _accountIdController,
            decoration: const InputDecoration(labelText: 'Cloudflare Account ID'),
          ),
          TextField(
            controller: _apiTokenController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'API Token'),
          ),
          DropdownButtonFormField<String>(
            key: const Key('modelDropdown'),
            initialValue: kCommonWorkersAiModels.contains(_modelController.text)
                ? _modelController.text
                : null,
            hint: const Text('Choose a common model...'),
            decoration: const InputDecoration(labelText: 'Common models'),
            items: kCommonWorkersAiModels
                .map((model) => DropdownMenuItem(value: model, child: Text(model)))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _modelController.text = value);
            },
          ),
          TextField(
            controller: _modelController,
            decoration: const InputDecoration(labelText: 'Model (or type a custom override)'),
          ),
          TextField(
            key: const Key('promptTemplateField'),
            controller: _promptTemplateController,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'System prompt template'),
          ),
          if (_validationError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_validationError!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 8),
          ShortcutRecorderField(
            shortcutKey: _shortcutKey,
            modifiers: _shortcutModifiers,
            onChanged: (key, modifiers) => setState(() {
              _shortcutKey = key;
              _shortcutModifiers = modifiers;
            }),
          ),
          SwitchListTile(
            title: const Text('Launch at login'),
            value: _launchAtLogin,
            onChanged: (value) => setState(() => _launchAtLogin = value),
          ),
          SwitchListTile(
            key: const Key('themeToggle'),
            title: const Text('Dark mode'),
            value: _isDarkMode,
            onChanged: (value) => setState(() => _isDarkMode = value),
          ),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/ui/settings/settings_screen_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/settings_screen.dart test/ui/settings/settings_screen_test.dart
git commit -m "feat: embed SettingsScreen in the tab shell and add a dark-mode toggle"
```

---

### Task 12: Main app screen (tab shell)

**Files:**
- Create: `lib/ui/app/main_app_screen.dart`
- Test: `test/ui/app/main_app_screen_test.dart`

**Interfaces:**
- Consumes: `AppNavigation`/`AppTab` (Task 9).
- Produces: `class MainAppScreen extends StatefulWidget { const MainAppScreen({required AppNavigation navigation, required Widget homeScreen, required Widget historyScreen, required Widget settingsScreen}); }` — a `Scaffold` with a top `TabBar` (Home/History/Settings) whose selection stays in sync with `navigation.activeTab` in both directions (tapping a tab updates `activeTab`; setting `activeTab` externally, e.g. from the tray or Home's recent-activity tap, switches the visible tab).

- [ ] **Step 1: Write the failing test**

Create `test/ui/app/main_app_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight/ui/app/app_navigation.dart';
import 'package:insight/ui/app/main_app_screen.dart';

void main() {
  testWidgets('shows Home content initially and switches tabs on tap', (tester) async {
    final navigation = AppNavigation();

    await tester.pumpWidget(MaterialApp(
      home: MainAppScreen(
        navigation: navigation,
        homeScreen: const Text('HOME CONTENT'),
        historyScreen: const Text('HISTORY CONTENT'),
        settingsScreen: const Text('SETTINGS CONTENT'),
      ),
    ));

    expect(find.text('HOME CONTENT'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('HISTORY CONTENT'), findsOneWidget);
    expect(navigation.activeTab.value, AppTab.history);
  });

  testWidgets('external navigation.activeTab changes switch the visible tab', (tester) async {
    final navigation = AppNavigation();

    await tester.pumpWidget(MaterialApp(
      home: MainAppScreen(
        navigation: navigation,
        homeScreen: const Text('HOME CONTENT'),
        historyScreen: const Text('HISTORY CONTENT'),
        settingsScreen: const Text('SETTINGS CONTENT'),
      ),
    ));

    navigation.goToSettings();
    await tester.pumpAndSettle();

    expect(find.text('SETTINGS CONTENT'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/app/main_app_screen_test.dart`
Expected: FAIL — compile error, `lib/ui/app/main_app_screen.dart` doesn't exist.

- [ ] **Step 3: Implement the screen**

Create `lib/ui/app/main_app_screen.dart`:

```dart
import 'package:flutter/material.dart';

import 'app_navigation.dart';

class MainAppScreen extends StatefulWidget {
  const MainAppScreen({
    super.key,
    required this.navigation,
    required this.homeScreen,
    required this.historyScreen,
    required this.settingsScreen,
  });

  final AppNavigation navigation;
  final Widget homeScreen;
  final Widget historyScreen;
  final Widget settingsScreen;

  @override
  State<MainAppScreen> createState() => _MainAppScreenState();
}

class _MainAppScreenState extends State<MainAppScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.navigation.activeTab.value.index,
    );
    widget.navigation.activeTab.addListener(_onExternalTabChange);
    _tabController.addListener(_onTabControllerChange);
  }

  void _onExternalTabChange() {
    final index = widget.navigation.activeTab.value.index;
    if (_tabController.index != index) {
      _tabController.animateTo(index);
    }
  }

  void _onTabControllerChange() {
    if (_tabController.indexIsChanging) return;
    final tab = AppTab.values[_tabController.index];
    if (widget.navigation.activeTab.value != tab) {
      widget.navigation.activeTab.value = tab;
    }
  }

  @override
  void dispose() {
    widget.navigation.activeTab.removeListener(_onExternalTabChange);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Insight'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.home), text: 'Home'),
            Tab(icon: Icon(Icons.history), text: 'History'),
            Tab(icon: Icon(Icons.settings), text: 'Settings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [widget.homeScreen, widget.historyScreen, widget.settingsScreen],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/ui/app/main_app_screen_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/app/main_app_screen.dart test/ui/app/main_app_screen_test.dart
git commit -m "feat: add MainAppScreen tab shell (Home/History/Settings)"
```

---

### Task 13: Wire it all together in `main.dart`

**Files:**
- Modify: `lib/main.dart`
- Modify: `test/main_test.dart`
- Modify: `macos/Runner/Info.plist`

**Interfaces:**
- Consumes: everything from Tasks 1–12.
- Produces: the fully wired app — Dock icon, tabbed main window with live theme switching, quit that actually terminates, window-close-hides, resizable session popup with no blur-dismiss, tray "Settings" jumping to the Settings tab.

- [ ] **Step 1: Remove `LSUIElement` from `macos/Runner/Info.plist`**

Delete these two lines from `macos/Runner/Info.plist`:

```xml
	<key>LSUIElement</key>
	<true/>
```

- [ ] **Step 2: Update `computePopupFrame`'s default size and its test**

In `test/main_test.dart`, change both expectations of the default size from `360, 200` to `420, 520`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight/main.dart';

void main() {
  test('computePopupFrame anchors a 420x520 frame at the cursor by default', () {
    final frame = computePopupFrame(const Offset(100, 200));

    expect(frame, const Rect.fromLTWH(100, 200, 420, 520));
  });

  test('computePopupFrame accepts a custom size', () {
    final frame = computePopupFrame(const Offset(0, 0), size: const Size(300, 150));

    expect(frame, const Rect.fromLTWH(0, 0, 300, 150));
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/main_test.dart`
Expected: FAIL — `computePopupFrame`'s default is still `Size(360, 200)`.

- [ ] **Step 4: Replace `lib/main.dart`**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'app/settings_model.dart';
import 'app/settings_repository.dart';
import 'services/auto_start_sync.dart';
import 'services/clipboard_capture_service.dart';
import 'services/history_repository.dart';
import 'services/hotkey_service.dart';
import 'services/tray_service.dart';
import 'services/workers_ai_client.dart';
import 'ui/app/app_navigation.dart';
import 'ui/app/main_app_screen.dart';
import 'ui/history/history_screen.dart';
import 'ui/home/home_screen.dart';
import 'ui/popup/popup_screen.dart';
import 'ui/session/session_controller.dart';
import 'ui/settings/settings_screen.dart';

Rect computePopupFrame(Offset cursor, {Size size = const Size(420, 520)}) {
  return Rect.fromLTWH(cursor.dx, cursor.dy, size.width, size.height);
}

Future<void> openMacAccessibilitySettings() async {
  if (Platform.isMacOS) {
    await Process.run('open', [
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
    ]);
  }
}

ThemeMode _themeModeOf(AppSettings settings) =>
    settings.themeMode == 'light' ? ThemeMode.light : ThemeMode.dark;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final windowController = await WindowController.fromCurrentEngine();

  if (windowController.arguments.isEmpty) {
    await _runMainWindow(windowController);
  } else {
    await _runPopupWindow(windowController);
  }
}

Future<void> _runPopupWindow(WindowController windowController) async {
  final payload = jsonDecode(windowController.arguments) as Map<String, dynamic>;
  final capturedText = payload['capturedText'] as String?;
  final settings = AppSettings.fromJson(payload['settings'] as Map<String, dynamic>);
  final mainWindowId = payload['mainWindowId'] as String;
  final frameJson = payload['frame'] as Map<String, dynamic>;
  final frame = Rect.fromLTWH(
    (frameJson['left'] as num).toDouble(),
    (frameJson['top'] as num).toDouble(),
    (frameJson['width'] as num).toDouble(),
    (frameJson['height'] as num).toDouble(),
  );

  await windowController.setWindowMethodHandler((call) async {
    if (call.method == 'window_close') {
      return windowManager.close();
    }
    throw MissingPluginException('Not implemented: ${call.method}');
  });

  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: frame.size,
      minimumSize: const Size(360, 400),
      skipTaskbar: true,
      alwaysOnTop: true,
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      await windowManager.setPosition(frame.topLeft);
      await windowManager.show();
      await windowManager.focus();
    },
  );

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.light(),
    darkTheme: ThemeData.dark(),
    themeMode: _themeModeOf(settings),
    home: PopupScreen(
      controller: SessionController(
        client: WorkersAiClient(),
        historyRepository: HistoryRepository(),
        clipboard: SystemClipboardAccess(),
      ),
      capturedText: capturedText,
      settings: settings,
      onOpenSettings: () async {
        await WindowController.fromWindowId(mainWindowId).invokeMethod('openSettings');
        await windowManager.close();
      },
      onDismiss: () => windowManager.close(),
    ),
  ));
}

// Closing the main window (native close button) hides it rather than
// quitting — the app keeps running in the background (tray + Dock icon).
class _MainWindowCloseListener extends WindowListener {
  @override
  void onWindowClose() {
    windowManager.hide();
  }
}

Future<void> _runMainWindow(WindowController windowController) async {
  await windowManager.setPreventClose(true);
  windowManager.addListener(_MainWindowCloseListener());

  await windowManager.waitUntilReadyToShow(
    const WindowOptions(skipTaskbar: true, titleBarStyle: TitleBarStyle.hidden),
    () async {
      await windowManager.hide();
    },
  );

  final repository = SettingsRepository();
  final historyRepository = HistoryRepository();
  final workersAiClient = WorkersAiClient();
  final clipboard = SystemClipboardAccess();
  final navigation = AppNavigation();
  var settings = await repository.load();

  final themeNotifier = ValueNotifier<ThemeMode>(_themeModeOf(settings));

  // launch_at_startup falls back to a no-op implementation that throws on
  // every call until setup() has been run once.
  launchAtStartup.setup(
    appName: 'Insight',
    appPath: Platform.resolvedExecutable,
    packageName: 'com.cefalo.insight.insight',
  );
  await AutoStartSync(LaunchAtStartupController()).applySetting(settings.launchAtLogin);

  final clipboardCapture = ClipboardCaptureService(
    keySimulator: PlatformKeySimulator(),
    clipboard: SystemClipboardAccess(),
  );

  final hotkeyService = HotkeyService(HotkeyManagerController());
  final trayService = TrayService(
    controller: TrayManagerController(),
    onSettings: () async {
      navigation.goToSettings();
      await windowManager.show();
      await windowManager.focus();
    },
    onQuit: () => exit(0),
  );
  await trayService.initialize('assets/tray_icon.png');

  await windowController.setWindowMethodHandler((call) async {
    if (call.method == 'openSettings') {
      navigation.goToSettings();
      await windowManager.show();
      await windowManager.focus();
    }
  });

  // Tracks the single open popup window so a second hotkey press replaces
  // rather than stacks a new one (spec: no multiple simultaneous popups).
  String? openPopupWindowId;

  Future<void> triggerExplain() async {
    if (openPopupWindowId != null) {
      await WindowController.fromWindowId(openPopupWindowId!).invokeMethod('window_close');
      openPopupWindowId = null;
    }

    final capturedText = await clipboardCapture.captureSelection();
    final cursor = await screenRetriever.getCursorScreenPoint();
    final currentSettings = await repository.load();
    final frame = computePopupFrame(Offset(cursor.dx, cursor.dy));

    final popupController = await WindowController.create(WindowConfiguration(
      hiddenAtLaunch: true,
      arguments: jsonEncode({
        'capturedText': capturedText,
        'settings': currentSettings.toJson(),
        'mainWindowId': windowController.windowId,
        'frame': {
          'left': frame.left,
          'top': frame.top,
          'width': frame.width,
          'height': frame.height,
        },
      }),
    ));
    openPopupWindowId = popupController.windowId;
  }

  Future<void> applyHotkey(AppSettings current) async {
    await hotkeyService.applyShortcut(current, () {
      triggerExplain();
    });
    if (hotkeyService.registrationFailed) {
      await trayService.showHotkeyConflictWarning();
      if (Platform.isMacOS) {
        await openMacAccessibilitySettings();
      }
    }
  }

  await applyHotkey(settings);

  runApp(ValueListenableBuilder<ThemeMode>(
    valueListenable: themeNotifier,
    builder: (context, mode, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: mode,
      home: MainAppScreen(
        navigation: navigation,
        homeScreen: HomeScreen(
          settingsRepository: repository,
          historyRepository: historyRepository,
          hotkeyService: hotkeyService,
          navigation: navigation,
        ),
        historyScreen: HistoryScreen(
          historyRepository: historyRepository,
          client: workersAiClient,
          clipboard: clipboard,
          settingsRepository: repository,
          navigation: navigation,
        ),
        settingsScreen: SettingsScreen(
          repository: repository,
          onSaved: () async {
            settings = await repository.load();
            themeNotifier.value = _themeModeOf(settings);
            await applyHotkey(settings);
          },
        ),
      ),
    ),
  ));
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/main_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Run the full test suite**

Run: `flutter test`
Expected: PASS — every test from Tasks 1–13.

- [ ] **Step 7: Verify the macOS build still compiles**

Run: `flutter build macos --debug`
Expected: build succeeds (this only proves compilation — Dock icon presence, window hide/show, quit, and theme switching are OS-level behavior verified manually in Task 14).

- [ ] **Step 8: Commit**

```bash
git add lib/main.dart test/main_test.dart macos/Runner/Info.plist
git commit -m "feat: wire app shell, sessions, and theming into main.dart; fix Quit and window-close-hides"
```

---

### Task 14: Manual verification

**Files:** none (verification only — no code changes).

This exercises real OS-level behavior (Dock presence, window lifecycle, process termination, live theme switching, resizing) that `flutter test` cannot drive. Complete every item before considering this feature done.

- [ ] **Step 1: Dock icon and Cmd+Tab**

Run the app (`flutter run -d macos`). Confirm a Dock icon appears and the app shows up in Cmd+Tab, in addition to the tray icon still being present.

- [ ] **Step 2: Window hides, doesn't quit, on close**

Open the main window (Dock or tray icon), click its native close button. Confirm the window disappears but the app is still running (tray icon still present, `ps` shows the process alive). Reopen it from the Dock or tray and confirm it comes back showing the same tab it was on before closing.

- [ ] **Step 3: Quit actually terminates**

Use the tray menu's "Quit" item. Confirm the process actually exits (check via Activity Monitor or `ps`) rather than just hiding the window.

- [ ] **Step 4: Tab navigation and tray "Settings" jump**

Click through Home/History/Settings tabs manually. Then close the window, and from the tray menu click "Settings…" — confirm the window opens directly on the Settings tab (even if it was last left on a different tab).

- [ ] **Step 5: Theme toggle applies live**

With the app open, flip the dark-mode toggle in Settings and click Save. Confirm the main window's colors change immediately without restarting the app. Trigger the hotkey to open a new popup and confirm it reflects the new theme.

- [ ] **Step 6: End-to-end session flow**

Select text in another app, trigger the hotkey. Confirm the popup streams an initial explanation, then:
- Ask a follow-up question in the input field and confirm a new exchange streams in below the first.
- Click regenerate and confirm the last response is replaced by a new one.
- Click copy and confirm the last response is on the clipboard (paste somewhere to check).
- Press Esc — confirm it closes. Click outside a newly-opened popup instead — confirm it does **not** close (this supersedes the original spec's blur-dismiss).

- [ ] **Step 7: History persists and resumes**

Open the History tab. Confirm the session from Step 6 appears with a preview of the selected text. Search for a word that appears only in one of your sessions and confirm filtering works. Open that session, add another follow-up from within History, and confirm it streams and saves correctly (reopen History and confirm the new turn persisted).

- [ ] **Step 8: History retention and delete**

Delete a session from its detail view and confirm it disappears from the list. (30-day pruning itself isn't practically testable manually in one sitting — covered by `HistoryRepository`'s automated test in Task 3.)

- [ ] **Step 9: Home tab reflects real state**

Confirm Home shows the current shortcut binding and a "Registered" status. Temporarily set the shortcut (in Settings) to a combination already used by another running app, save, and confirm Home switches to a conflict status and the tray shows its conflict warning (tooltip + menu item), matching the pre-existing hotkey-conflict behavior.

- [ ] **Step 10: Repeat on Windows**

Repeat Steps 1–9 on Windows where applicable (no Dock/Cmd+Tab equivalent — confirm the taskbar/Alt+Tab behavior instead, and that the app still runs from its tray icon). Note any Windows-specific issues and fix before shipping.

- [ ] **Step 11: Record results**

Note the outcome of each step (pass/fail + any fixes made) in the PR description or final commit message when this feature branch is finalized.
