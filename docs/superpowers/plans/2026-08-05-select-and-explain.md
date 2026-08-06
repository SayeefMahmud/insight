# Select & Explain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter desktop app (macOS + Windows) that runs in the background from login, captures the current text selection on a global hotkey, and shows a streamed AI explanation from Cloudflare Workers AI in a popup near the cursor.

**Architecture:** Single Flutter app with two entry-point modes in one `main.dart`: the main window (hidden, tray-only, owns settings + hotkey registration) and a popup window spawned via `desktop_multi_window` for each explanation request. Pure logic (settings, clipboard capture, AI streaming, hotkey mapping, tray menu, auto-start sync) is isolated behind small interfaces so it can be unit/widget-tested without touching real OS APIs; only `main.dart`'s wiring and the native OS interactions themselves are left to manual verification.

**Tech Stack:** Flutter (macOS + Windows desktop targets), `tray_manager`, `hotkey_manager`, `keypress_simulator`, `super_clipboard`, `screen_retriever`, `desktop_multi_window`, `flutter_secure_storage`, `shared_preferences`, `launch_at_startup`, `window_manager`, `http`, `mocktail` (dev).

## Global Constraints

- Platforms: macOS and Windows desktop only (per spec's non-goals: no Linux/mobile).
- Cloudflare API token must be stored via OS-level secure storage (Keychain on macOS, Credential Manager/DPAPI on Windows) — never in plain prefs.
- System prompt template must always contain the literal `{{selection}}` placeholder; saving a template without it must be rejected.
- Default global shortcut: `Cmd+Shift+E` on macOS, `Ctrl+Shift+E` on Windows.
- Response text must stream into the popup incrementally, not appear all at once.
- App has no dock icon / taskbar entry — it only exposes a tray/menu-bar icon.
- No retry/regenerate button, no history/logging, no multiple simultaneous popups (v1 non-goals).

---

## File Structure

```
lib/
  app/
    settings_model.dart          # AppSettings data class + json (de)serialization
    settings_repository.dart     # SecureStorage abstraction + SettingsRepository
  services/
    clipboard_capture_service.dart   # KeySimulator/ClipboardAccess abstractions + ClipboardCaptureService
    workers_ai_client.dart           # WorkersAiClient (SSE streaming) + WorkersAiException
    auto_start_sync.dart             # AutoStartController abstraction + AutoStartSync
    tray_service.dart                # TrayController abstraction + TrayService
    hotkey_service.dart              # HotkeyController abstraction + HotkeyService + key/modifier maps
  ui/
    popup/
      explanation_controller.dart  # PopupStatus enum + ExplanationController
      popup_screen.dart            # PopupScreen widget
    settings/
      settings_screen.dart         # SettingsScreen widget
      shortcut_recorder_field.dart # ShortcutRecorderField widget
  main.dart                        # entry point: main-window vs popup-window wiring

test/
  app/settings_repository_test.dart
  services/clipboard_capture_service_test.dart
  services/workers_ai_client_test.dart
  services/auto_start_sync_test.dart
  services/tray_service_test.dart
  services/hotkey_service_test.dart
  ui/popup/popup_screen_test.dart
  ui/settings/settings_screen_test.dart
  ui/settings/shortcut_recorder_field_test.dart
  main_test.dart

macos/Runner/Info.plist            # add LSUIElement (hide dock icon)
```

---

### Task 1: Project scaffolding

**Files:**
- Create: whole Flutter project (via `flutter create`) in repo root
- Modify: `macos/Runner/Info.plist`
- Modify: `lib/main.dart`

**Interfaces:**
- Produces: a runnable Flutter desktop project with macOS + Windows targets and all dependencies declared in `pubspec.yaml`, which every later task builds on.

- [ ] **Step 1: Scaffold the Flutter project**

```bash
flutter create --platforms=macos,windows --project-name insight --org com.cefalo.insight .
```

- [ ] **Step 2: Add dependencies**

```bash
flutter pub add tray_manager hotkey_manager keypress_simulator super_clipboard screen_retriever desktop_multi_window flutter_secure_storage shared_preferences launch_at_startup window_manager http
flutter pub add --dev mocktail
```

- [ ] **Step 3: Hide the dock icon on macOS**

Open `macos/Runner/Info.plist` and add, as a top-level key inside the outer `<dict>`:

```xml
<key>LSUIElement</key>
<true/>
```

- [ ] **Step 4: Replace `lib/main.dart` with a minimal placeholder**

```dart
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(body: Center(child: Text('Insight'))),
  ));
}
```

- [ ] **Step 5: Verify the app builds and runs on macOS**

Run: `flutter run -d macos`
Expected: a window opens showing "Insight" with no crash. Stop the run once confirmed.

- [ ] **Step 6: Verify the Windows target at least compiles**

Run: `flutter build windows` (or `flutter run -d windows` if you have Windows hardware/VM available)
Expected: build succeeds. If you have no access to a Windows machine right now, note this in your task summary — full Windows manual verification is covered by Task 9 and must happen before shipping.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "chore: scaffold Flutter desktop project with dependencies"
```

---

### Task 2: Settings model and repository

**Files:**
- Create: `lib/app/settings_model.dart`
- Create: `lib/app/settings_repository.dart`
- Test: `test/app/settings_repository_test.dart`

**Interfaces:**
- Produces:
  - `AppSettings` — immutable data class with fields `accountId, apiToken, model, promptTemplate, shortcutKey, shortcutModifiers (List<String>), launchAtLogin (bool)`, plus `toJson()`/`AppSettings.fromJson(Map<String, dynamic>)` and static defaults `AppSettings.defaultModel`, `AppSettings.defaultPromptTemplate`, `AppSettings.defaultShortcutKey`, `AppSettings.defaultShortcutModifiers`.
  - `abstract class SecureStorage { Future<String?> read({required String key}); Future<void> write({required String key, required String? value}); }` and `FlutterSecureStorageAdapter implements SecureStorage`.
  - `SettingsRepository({SecureStorage? secureStorage, SharedPreferences? prefs})` with `Future<AppSettings> load()` and `Future<void> save(AppSettings settings)` (throws `ArgumentError` if `promptTemplate` lacks `{{selection}}`).
- Consumes: nothing from other tasks (this is foundational).

- [ ] **Step 1: Write the failing test**

Create `test/app/settings_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:insight/app/settings_model.dart';
import 'package:insight/app/settings_repository.dart';

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

  test('load returns defaults when nothing has been saved', () async {
    final settings = await repository.load();

    expect(settings.accountId, '');
    expect(settings.model, AppSettings.defaultModel);
    expect(settings.promptTemplate, AppSettings.defaultPromptTemplate);
    expect(settings.shortcutKey, AppSettings.defaultShortcutKey);
    expect(settings.shortcutModifiers, AppSettings.defaultShortcutModifiers);
    expect(settings.launchAtLogin, isFalse);
  });

  test('save persists values that load then returns', () async {
    const settings = AppSettings(
      accountId: 'acct-1',
      apiToken: 'secret-token',
      model: '@cf/meta/llama-3.1-8b-instruct',
      promptTemplate: 'Explain: {{selection}}',
      shortcutKey: 'keyE',
      shortcutModifiers: ['meta', 'shift'],
      launchAtLogin: true,
    );
    when(() => secureStorage.read(key: 'apiToken'))
        .thenAnswer((_) async => 'secret-token');

    await repository.save(settings);
    final loaded = await repository.load();

    expect(loaded.accountId, 'acct-1');
    expect(loaded.apiToken, 'secret-token');
    expect(loaded.launchAtLogin, isTrue);
    verify(() => secureStorage.write(key: 'apiToken', value: 'secret-token'))
        .called(1);
  });

  test('save rejects a prompt template missing {{selection}}', () {
    const settings = AppSettings(
      accountId: 'a',
      apiToken: 't',
      model: 'm',
      promptTemplate: 'no placeholder here',
      shortcutKey: 'keyE',
      shortcutModifiers: ['meta'],
      launchAtLogin: false,
    );

    expect(() => repository.save(settings), throwsArgumentError);
  });

  test('AppSettings round-trips through toJson/fromJson', () {
    const settings = AppSettings(
      accountId: 'acct-1',
      apiToken: 'secret',
      model: 'model-x',
      promptTemplate: '{{selection}}',
      shortcutKey: 'keyE',
      shortcutModifiers: ['meta', 'shift'],
      launchAtLogin: true,
    );

    final roundTripped = AppSettings.fromJson(settings.toJson());

    expect(roundTripped.accountId, settings.accountId);
    expect(roundTripped.shortcutModifiers, settings.shortcutModifiers);
    expect(roundTripped.launchAtLogin, settings.launchAtLogin);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/app/settings_repository_test.dart`
Expected: FAIL — compile error, `AppSettings`/`SettingsRepository`/`SecureStorage` are not defined.

- [ ] **Step 3: Implement the settings model**

Create `lib/app/settings_model.dart`:

```dart
class AppSettings {
  const AppSettings({
    required this.accountId,
    required this.apiToken,
    required this.model,
    required this.promptTemplate,
    required this.shortcutKey,
    required this.shortcutModifiers,
    required this.launchAtLogin,
  });

  final String accountId;
  final String apiToken;
  final String model;
  final String promptTemplate;
  final String shortcutKey;
  final List<String> shortcutModifiers;
  final bool launchAtLogin;

  static const defaultModel = '@cf/meta/llama-3.1-8b-instruct';
  static const defaultPromptTemplate =
      'Explain the following text concisely:\n\n{{selection}}';
  static const defaultShortcutKey = 'keyE';
  static const defaultShortcutModifiers = ['meta', 'shift'];

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'apiToken': apiToken,
        'model': model,
        'promptTemplate': promptTemplate,
        'shortcutKey': shortcutKey,
        'shortcutModifiers': shortcutModifiers,
        'launchAtLogin': launchAtLogin,
      };

  static AppSettings fromJson(Map<String, dynamic> json) => AppSettings(
        accountId: json['accountId'] as String,
        apiToken: json['apiToken'] as String,
        model: json['model'] as String,
        promptTemplate: json['promptTemplate'] as String,
        shortcutKey: json['shortcutKey'] as String,
        shortcutModifiers: List<String>.from(json['shortcutModifiers'] as List),
        launchAtLogin: json['launchAtLogin'] as bool,
      );
}
```

- [ ] **Step 4: Implement the secure storage abstraction and repository**

Create `lib/app/settings_repository.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_model.dart';

abstract class SecureStorage {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String? value});
}

class FlutterSecureStorageAdapter implements SecureStorage {
  const FlutterSecureStorageAdapter([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String? value}) =>
      _storage.write(key: key, value: value);
}

class SettingsRepository {
  SettingsRepository({SecureStorage? secureStorage, SharedPreferences? prefs})
      : _secureStorage = secureStorage ?? const FlutterSecureStorageAdapter(),
        _prefs = prefs;

  static const _kAccountId = 'accountId';
  static const _kModel = 'model';
  static const _kPromptTemplate = 'promptTemplate';
  static const _kShortcutKey = 'shortcutKey';
  static const _kShortcutModifiers = 'shortcutModifiers';
  static const _kLaunchAtLogin = 'launchAtLogin';
  static const _kApiToken = 'apiToken';

  final SecureStorage _secureStorage;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _prefsInstance() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<AppSettings> load() async {
    final prefs = await _prefsInstance();
    final apiToken = await _secureStorage.read(key: _kApiToken) ?? '';
    return AppSettings(
      accountId: prefs.getString(_kAccountId) ?? '',
      apiToken: apiToken,
      model: prefs.getString(_kModel) ?? AppSettings.defaultModel,
      promptTemplate:
          prefs.getString(_kPromptTemplate) ?? AppSettings.defaultPromptTemplate,
      shortcutKey: prefs.getString(_kShortcutKey) ?? AppSettings.defaultShortcutKey,
      shortcutModifiers: prefs.getStringList(_kShortcutModifiers) ??
          AppSettings.defaultShortcutModifiers,
      launchAtLogin: prefs.getBool(_kLaunchAtLogin) ?? false,
    );
  }

  Future<void> save(AppSettings settings) async {
    if (!settings.promptTemplate.contains('{{selection}}')) {
      throw ArgumentError('promptTemplate must contain {{selection}}');
    }
    final prefs = await _prefsInstance();
    await prefs.setString(_kAccountId, settings.accountId);
    await prefs.setString(_kModel, settings.model);
    await prefs.setString(_kPromptTemplate, settings.promptTemplate);
    await prefs.setString(_kShortcutKey, settings.shortcutKey);
    await prefs.setStringList(_kShortcutModifiers, settings.shortcutModifiers);
    await prefs.setBool(_kLaunchAtLogin, settings.launchAtLogin);
    await _secureStorage.write(key: _kApiToken, value: settings.apiToken);
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/app/settings_repository_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/app test/app
git commit -m "feat: add settings model and repository with secure token storage"
```

---

### Task 3: Clipboard capture service

**Files:**
- Create: `lib/services/clipboard_capture_service.dart`
- Test: `test/services/clipboard_capture_service_test.dart`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces:
  - `abstract class KeySimulator { Future<void> simulateCopy(); }` and `PlatformKeySimulator implements KeySimulator`.
  - `abstract class ClipboardAccess { Future<String?> readText(); Future<void> writeText(String? text); }` and `SystemClipboardAccess implements ClipboardAccess`.
  - `class ClipboardCaptureService { ClipboardCaptureService({required KeySimulator keySimulator, required ClipboardAccess clipboard, Duration copyDelay}); Future<String?> captureSelection(); }` — returns `null` when nothing was selected (clipboard unchanged after the copy simulation).

- [ ] **Step 1: Write the failing test**

Create `test/services/clipboard_capture_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:insight/services/clipboard_capture_service.dart';

class MockKeySimulator extends Mock implements KeySimulator {}
class MockClipboardAccess extends Mock implements ClipboardAccess {}

void main() {
  late MockKeySimulator keySimulator;
  late MockClipboardAccess clipboard;
  late ClipboardCaptureService service;

  setUp(() {
    keySimulator = MockKeySimulator();
    clipboard = MockClipboardAccess();
    when(() => keySimulator.simulateCopy()).thenAnswer((_) async {});
    when(() => clipboard.writeText(any())).thenAnswer((_) async {});
    service = ClipboardCaptureService(
      keySimulator: keySimulator,
      clipboard: clipboard,
      copyDelay: Duration.zero,
    );
  });

  test('returns newly copied text and restores the original clipboard', () async {
    var readCallCount = 0;
    when(() => clipboard.readText()).thenAnswer((_) async {
      readCallCount++;
      return readCallCount == 1 ? 'old clipboard value' : 'selected text';
    });

    final result = await service.captureSelection();

    expect(result, 'selected text');
    verify(() => keySimulator.simulateCopy()).called(1);
    verify(() => clipboard.writeText('old clipboard value')).called(1);
  });

  test('returns null when the clipboard is unchanged (nothing selected)', () async {
    when(() => clipboard.readText()).thenAnswer((_) async => 'same value');

    final result = await service.captureSelection();

    expect(result, isNull);
    verify(() => clipboard.writeText('same value')).called(1);
  });

  test('returns null when the captured text is empty', () async {
    var readCallCount = 0;
    when(() => clipboard.readText()).thenAnswer((_) async {
      readCallCount++;
      return readCallCount == 1 ? 'old value' : '';
    });

    final result = await service.captureSelection();

    expect(result, isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/services/clipboard_capture_service_test.dart`
Expected: FAIL — compile error, types not defined.

- [ ] **Step 3: Implement the service**

Create `lib/services/clipboard_capture_service.dart`:

```dart
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/services/clipboard_capture_service_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/clipboard_capture_service.dart test/services/clipboard_capture_service_test.dart
git commit -m "feat: add clipboard capture service with save/restore semantics"
```

---

### Task 4: Workers AI streaming client

**Files:**
- Create: `lib/services/workers_ai_client.dart`
- Test: `test/services/workers_ai_client_test.dart`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `class WorkersAiClient { WorkersAiClient({http.Client? httpClient}); Stream<String> streamExplanation({required String accountId, required String apiToken, required String model, required String prompt}); }` and `class WorkersAiException implements Exception { final String message; }`.

- [ ] **Step 1: Write the failing test**

Create `test/services/workers_ai_client_test.dart`:

```dart
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
        .streamExplanation(
          accountId: 'acct',
          apiToken: 'test-token',
          model: '@cf/meta/llama-3.1-8b-instruct',
          prompt: 'Explain: hi',
        )
        .toList();

    expect(chunks.join(), 'Hello world');
  });

  test('throws WorkersAiException on a non-200 response', () async {
    final client = MockClient((request) async => http.Response('bad token', 401));
    final aiClient = WorkersAiClient(httpClient: client);

    expect(
      () => aiClient
          .streamExplanation(
            accountId: 'acct',
            apiToken: 'bad',
            model: 'm',
            prompt: 'p',
          )
          .toList(),
      throwsA(isA<WorkersAiException>()),
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/services/workers_ai_client_test.dart`
Expected: FAIL — compile error, `WorkersAiClient` not defined.

- [ ] **Step 3: Implement the client**

Create `lib/services/workers_ai_client.dart`:

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

class WorkersAiClient {
  WorkersAiClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Stream<String> streamExplanation({
    required String accountId,
    required String apiToken,
    required String model,
    required String prompt,
  }) async* {
    final uri = Uri.parse(
      'https://api.cloudflare.com/client/v4/accounts/$accountId/ai/run/$model',
    );
    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $apiToken'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
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
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/workers_ai_client.dart test/services/workers_ai_client_test.dart
git commit -m "feat: add streaming Cloudflare Workers AI client"
```

---

### Task 5: Popup controller and screen

**Files:**
- Create: `lib/ui/popup/explanation_controller.dart`
- Create: `lib/ui/popup/popup_screen.dart`
- Test: `test/ui/popup/popup_screen_test.dart`

**Interfaces:**
- Consumes: `AppSettings` (Task 2), `WorkersAiClient`/`WorkersAiException` (Task 4).
- Produces:
  - `enum PopupStatus { loading, noSelection, streaming, error }`
  - `class ExplanationController extends ChangeNotifier { ExplanationController({required WorkersAiClient client}); PopupStatus status; String text; String errorMessage; Future<void> start({required String? capturedText, required AppSettings settings}); }`
  - `class PopupScreen extends StatefulWidget { const PopupScreen({required ExplanationController controller, required String? capturedText, required AppSettings settings, VoidCallback? onOpenSettings, VoidCallback? onDismiss}); }` — wraps its content in a `Focus`/`KeyboardListener` that calls `onDismiss` on `LogicalKeyboardKey.escape`; `main.dart` (Task 8) supplies `onDismiss` to close the popup window.

- [ ] **Step 1: Write the failing test**

Create `test/ui/popup/popup_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:insight/app/settings_model.dart';
import 'package:insight/services/workers_ai_client.dart';
import 'package:insight/ui/popup/explanation_controller.dart';
import 'package:insight/ui/popup/popup_screen.dart';

class MockWorkersAiClient extends Mock implements WorkersAiClient {}

AppSettings _testSettings() => const AppSettings(
      accountId: 'acct',
      apiToken: 'token',
      model: 'model',
      promptTemplate: '{{selection}}',
      shortcutKey: 'keyE',
      shortcutModifiers: ['meta'],
      launchAtLogin: false,
    );

void main() {
  testWidgets('shows "No text selected" when capturedText is null', (tester) async {
    final controller = ExplanationController(client: MockWorkersAiClient());
    await tester.pumpWidget(MaterialApp(
      home: PopupScreen(
        controller: controller,
        capturedText: null,
        settings: _testSettings(),
      ),
    ));
    await tester.pump();

    expect(find.text('No text selected'), findsOneWidget);
  });

  testWidgets('streams chunks into the text view', (tester) async {
    final client = MockWorkersAiClient();
    when(() => client.streamExplanation(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          prompt: any(named: 'prompt'),
        )).thenAnswer((_) => Stream.fromIterable(['Hel', 'lo']));
    final controller = ExplanationController(client: client);

    await tester.pumpWidget(MaterialApp(
      home: PopupScreen(
        controller: controller,
        capturedText: 'some text',
        settings: _testSettings(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('shows an error message and an Open Settings button on failure', (tester) async {
    final client = MockWorkersAiClient();
    when(() => client.streamExplanation(
          accountId: any(named: 'accountId'),
          apiToken: any(named: 'apiToken'),
          model: any(named: 'model'),
          prompt: any(named: 'prompt'),
        )).thenAnswer((_) => Stream.error(WorkersAiException('boom')));
    var settingsOpened = false;
    final controller = ExplanationController(client: client);

    await tester.pumpWidget(MaterialApp(
      home: PopupScreen(
        controller: controller,
        capturedText: 'some text',
        settings: _testSettings(),
        onOpenSettings: () => settingsOpened = true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('boom'), findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    expect(settingsOpened, isTrue);
  });

  testWidgets('pressing Esc calls onDismiss', (tester) async {
    var dismissed = false;
    final controller = ExplanationController(client: MockWorkersAiClient());

    await tester.pumpWidget(MaterialApp(
      home: PopupScreen(
        controller: controller,
        capturedText: null,
        settings: _testSettings(),
        onDismiss: () => dismissed = true,
      ),
    ));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(dismissed, isTrue);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/popup/popup_screen_test.dart`
Expected: FAIL — compile error, types not defined.

- [ ] **Step 3: Implement the controller**

Create `lib/ui/popup/explanation_controller.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../app/settings_model.dart';
import '../../services/workers_ai_client.dart';

enum PopupStatus { loading, noSelection, streaming, error }

class ExplanationController extends ChangeNotifier {
  ExplanationController({required WorkersAiClient client}) : _client = client;

  final WorkersAiClient _client;

  PopupStatus status = PopupStatus.loading;
  String text = '';
  String errorMessage = '';

  Future<void> start({
    required String? capturedText,
    required AppSettings settings,
  }) async {
    if (capturedText == null) {
      status = PopupStatus.noSelection;
      notifyListeners();
      return;
    }
    if (settings.accountId.isEmpty || settings.apiToken.isEmpty) {
      status = PopupStatus.error;
      errorMessage =
          'Cloudflare account ID or API token is missing. Open Settings to configure.';
      notifyListeners();
      return;
    }

    status = PopupStatus.streaming;
    text = '';
    notifyListeners();

    final prompt = settings.promptTemplate.replaceAll('{{selection}}', capturedText);
    try {
      await for (final chunk in _client.streamExplanation(
        accountId: settings.accountId,
        apiToken: settings.apiToken,
        model: settings.model,
        prompt: prompt,
      )) {
        text += chunk;
        notifyListeners();
      }
    } catch (e) {
      status = PopupStatus.error;
      errorMessage = e.toString();
      notifyListeners();
    }
  }
}
```

- [ ] **Step 4: Implement the popup screen**

Create `lib/ui/popup/popup_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/settings_model.dart';
import 'explanation_controller.dart';

class PopupScreen extends StatefulWidget {
  const PopupScreen({
    super.key,
    required this.controller,
    required this.capturedText,
    required this.settings,
    this.onOpenSettings,
    this.onDismiss,
  });

  final ExplanationController controller;
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

  static const _spinner = SizedBox(
    height: 24,
    width: 24,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

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
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          return Material(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: switch (controller.status) {
                PopupStatus.loading => _spinner,
                PopupStatus.noSelection => const Text(
                    'No text selected',
                    style: TextStyle(color: Colors.white),
                  ),
                PopupStatus.streaming => controller.text.isEmpty
                    ? _spinner
                    : Text(controller.text, style: const TextStyle(color: Colors.white)),
                PopupStatus.error => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(controller.errorMessage,
                          style: const TextStyle(color: Colors.redAccent)),
                      if (widget.onOpenSettings != null)
                        TextButton(
                          onPressed: widget.onOpenSettings,
                          child: const Text('Open Settings'),
                        ),
                    ],
                  ),
              },
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/ui/popup/popup_screen_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/ui/popup test/ui/popup
git commit -m "feat: add popup controller and screen with loading/streaming/error states"
```

---

### Task 6: Settings screen and shortcut recorder

**Files:**
- Create: `lib/ui/settings/shortcut_recorder_field.dart`
- Create: `lib/ui/settings/settings_screen.dart`
- Test: `test/ui/settings/shortcut_recorder_field_test.dart`
- Test: `test/ui/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes: `AppSettings`, `SettingsRepository`, `SecureStorage` (Task 2).
- Produces:
  - `class ShortcutRecorderField extends StatefulWidget { const ShortcutRecorderField({required String shortcutKey, required List<String> modifiers, required void Function(String key, List<String> modifiers) onChanged}); }`
  - `const kCommonWorkersAiModels = <String>[...]` — a short list of common Workers AI text model identifiers, shown in a dropdown alongside the free-text model field.
  - `class SettingsScreen extends StatefulWidget { const SettingsScreen({required SettingsRepository repository, VoidCallback? onSaved}); }` — has `Key('promptTemplateField')` on the prompt template `TextField`; calls `onSaved` after a successful save so callers (e.g. `main.dart`) can react to settings changes (re-registering the hotkey, etc.) without restarting the app.

- [ ] **Step 1: Write the failing test for the shortcut recorder**

Create `test/ui/settings/shortcut_recorder_field_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight/ui/settings/shortcut_recorder_field.dart';

void main() {
  testWidgets('records meta+shift+E and reports it via onChanged', (tester) async {
    String? capturedKey;
    List<String>? capturedModifiers;

    await tester.pumpWidget(MaterialApp(
      home: ShortcutRecorderField(
        shortcutKey: 'keyE',
        modifiers: const ['meta', 'shift'],
        onChanged: (key, modifiers) {
          capturedKey = key;
          capturedModifiers = modifiers;
        },
      ),
    ));

    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
    await tester.pump();

    expect(capturedKey, 'keyE');
    expect(capturedModifiers, containsAll(['meta', 'shift']));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/settings/shortcut_recorder_field_test.dart`
Expected: FAIL — compile error, `ShortcutRecorderField` not defined.

- [ ] **Step 3: Implement the shortcut recorder**

Create `lib/ui/settings/shortcut_recorder_field.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ShortcutRecorderField extends StatefulWidget {
  const ShortcutRecorderField({
    super.key,
    required this.shortcutKey,
    required this.modifiers,
    required this.onChanged,
  });

  final String shortcutKey;
  final List<String> modifiers;
  final void Function(String key, List<String> modifiers) onChanged;

  @override
  State<ShortcutRecorderField> createState() => _ShortcutRecorderFieldState();
}

class _ShortcutRecorderFieldState extends State<ShortcutRecorderField> {
  bool _recording = false;
  final _focusNode = FocusNode();

  String _describe(String key, List<String> modifiers) {
    final modLabels = modifiers.map((m) => m[0].toUpperCase() + m.substring(1)).join('+');
    final keyLabel = key.replaceFirst('key', '').toUpperCase();
    return modLabels.isEmpty ? keyLabel : '$modLabels+$keyLabel';
  }

  void _handleKey(KeyEvent event) {
    if (!_recording || event is! KeyDownEvent) return;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final modifiers = <String>[
      if (pressed.contains(LogicalKeyboardKey.metaLeft) ||
          pressed.contains(LogicalKeyboardKey.metaRight))
        'meta',
      if (pressed.contains(LogicalKeyboardKey.controlLeft) ||
          pressed.contains(LogicalKeyboardKey.controlRight))
        'control',
      if (pressed.contains(LogicalKeyboardKey.shiftLeft) ||
          pressed.contains(LogicalKeyboardKey.shiftRight))
        'shift',
      if (pressed.contains(LogicalKeyboardKey.altLeft) ||
          pressed.contains(LogicalKeyboardKey.altRight))
        'alt',
    ];

    final label = event.logicalKey.debugName ?? '';
    if (label.startsWith('Key ')) {
      final key = 'key${label.substring(4)}';
      setState(() => _recording = false);
      widget.onChanged(key, modifiers);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: OutlinedButton(
        onPressed: () {
          setState(() => _recording = true);
          _focusNode.requestFocus();
        },
        child: Text(_recording ? 'Press keys...' : _describe(widget.shortcutKey, widget.modifiers)),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the shortcut recorder test to verify it passes**

Run: `flutter test test/ui/settings/shortcut_recorder_field_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the failing test for the settings screen**

Create `test/ui/settings/settings_screen_test.dart`:

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

  testWidgets('loads existing settings into the form', (tester) async {
    await repository.save(const AppSettings(
      accountId: 'acct-1',
      apiToken: 'tok',
      model: 'model-x',
      promptTemplate: 'Explain: {{selection}}',
      shortcutKey: 'keyE',
      shortcutModifiers: ['meta', 'shift'],
      launchAtLogin: true,
    ));
    when(() => secureStorage.read(key: 'apiToken')).thenAnswer((_) async => 'tok');

    await tester.pumpWidget(MaterialApp(home: SettingsScreen(repository: repository)));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'acct-1'), findsOneWidget);
  });

  testWidgets('shows a validation error when saving a template missing {{selection}}', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(repository: repository)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('promptTemplateField')), 'no placeholder');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Prompt template must contain {{selection}}'), findsOneWidget);
  });

  testWidgets('calls onSaved after a successful save', (tester) async {
    var savedCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(repository: repository, onSaved: () => savedCount++),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedCount, 1);
  });

  testWidgets('picking a model from the dropdown fills the model field', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('modelDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(kCommonWorkersAiModels.first).last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, kCommonWorkersAiModels.first), findsOneWidget);
  });
}
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `flutter test test/ui/settings/settings_screen_test.dart`
Expected: FAIL — compile error, `SettingsScreen` not defined.

- [ ] **Step 7: Implement the settings screen**

Create `lib/ui/settings/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../app/settings_model.dart';
import '../../app/settings_repository.dart';
import 'shortcut_recorder_field.dart';

const kCommonWorkersAiModels = <String>[
  '@cf/meta/llama-3.1-8b-instruct',
  '@cf/meta/llama-3.1-70b-instruct',
  '@cf/mistral/mistral-7b-instruct-v0.1',
  '@cf/qwen/qwen1.5-14b-chat-awq',
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.repository, this.onSaved});

  final SettingsRepository repository;
  final VoidCallback? onSaved;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _accountIdController = TextEditingController();
  final _apiTokenController = TextEditingController();
  final _modelController = TextEditingController();
  final _promptTemplateController = TextEditingController();
  bool _launchAtLogin = false;
  String _shortcutKey = AppSettings.defaultShortcutKey;
  List<String> _shortcutModifiers = AppSettings.defaultShortcutModifiers;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _load();
  }

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
    });
  }

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
    ));
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
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
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Run the settings screen test to verify it passes**

Run: `flutter test test/ui/settings/settings_screen_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 9: Commit**

```bash
git add lib/ui/settings test/ui/settings
git commit -m "feat: add settings screen with shortcut recorder and template validation"
```

---

### Task 7: Tray icon and auto-start sync

**Files:**
- Create: `lib/services/tray_service.dart`
- Create: `lib/services/auto_start_sync.dart`
- Test: `test/services/tray_service_test.dart`
- Test: `test/services/auto_start_sync_test.dart`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces:
  - `abstract class TrayController { Future<void> setIcon(String iconPath); Future<void> setToolTip(String toolTip); Future<void> setContextMenu(Menu menu); void addListener(TrayListener listener); }` and `TrayManagerController implements TrayController`.
  - `class TrayService with TrayListener { TrayService({required TrayController controller, required VoidCallback onSettings, required VoidCallback onQuit}); Future<void> initialize(String iconPath); Future<void> showHotkeyConflictWarning(); }` — `showHotkeyConflictWarning` sets a distinguishing tray tooltip ("Insight: shortcut conflict — open Settings to rebind") and adds a "⚠ Shortcut conflict" item to the context menu that opens Settings, surfacing the spec's "hotkey registration fails → tray notification, rebind in Settings" requirement.
  - `abstract class AutoStartController { Future<void> enable(); Future<void> disable(); Future<bool> isEnabled(); }` and `LaunchAtStartupController implements AutoStartController`.
  - `class AutoStartSync { AutoStartSync(AutoStartController controller); Future<void> applySetting(bool shouldLaunchAtLogin); }`

- [ ] **Step 1: Write the failing test for auto-start sync**

Create `test/services/auto_start_sync_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:insight/services/auto_start_sync.dart';

class MockAutoStartController extends Mock implements AutoStartController {}

void main() {
  late MockAutoStartController controller;
  late AutoStartSync sync;

  setUp(() {
    controller = MockAutoStartController();
    sync = AutoStartSync(controller);
  });

  test('enables auto-start when requested and currently disabled', () async {
    when(() => controller.isEnabled()).thenAnswer((_) async => false);
    when(() => controller.enable()).thenAnswer((_) async {});

    await sync.applySetting(true);

    verify(() => controller.enable()).called(1);
    verifyNever(() => controller.disable());
  });

  test('disables auto-start when requested off and currently enabled', () async {
    when(() => controller.isEnabled()).thenAnswer((_) async => true);
    when(() => controller.disable()).thenAnswer((_) async {});

    await sync.applySetting(false);

    verify(() => controller.disable()).called(1);
    verifyNever(() => controller.enable());
  });

  test('does nothing when already in the desired state', () async {
    when(() => controller.isEnabled()).thenAnswer((_) async => true);

    await sync.applySetting(true);

    verifyNever(() => controller.enable());
    verifyNever(() => controller.disable());
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/services/auto_start_sync_test.dart`
Expected: FAIL — compile error, types not defined.

- [ ] **Step 3: Implement auto-start sync**

Create `lib/services/auto_start_sync.dart`:

```dart
import 'package:launch_at_startup/launch_at_startup.dart';

abstract class AutoStartController {
  Future<void> enable();
  Future<void> disable();
  Future<bool> isEnabled();
}

class LaunchAtStartupController implements AutoStartController {
  @override
  Future<void> enable() => launchAtStartup.enable();

  @override
  Future<void> disable() => launchAtStartup.disable();

  @override
  Future<bool> isEnabled() => launchAtStartup.isEnabled();
}

class AutoStartSync {
  AutoStartSync(this._controller);

  final AutoStartController _controller;

  Future<void> applySetting(bool shouldLaunchAtLogin) async {
    final currentlyEnabled = await _controller.isEnabled();
    if (shouldLaunchAtLogin && !currentlyEnabled) {
      await _controller.enable();
    } else if (!shouldLaunchAtLogin && currentlyEnabled) {
      await _controller.disable();
    }
  }
}
```

- [ ] **Step 4: Run the auto-start sync test to verify it passes**

Run: `flutter test test/services/auto_start_sync_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Write the failing test for the tray service**

Create `test/services/tray_service_test.dart`:

```dart
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
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `flutter test test/services/tray_service_test.dart`
Expected: FAIL — compile error, `TrayController`/`TrayService` not defined.

- [ ] **Step 7: Implement the tray service**

Create `lib/services/tray_service.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

abstract class TrayController {
  Future<void> setIcon(String iconPath);
  Future<void> setToolTip(String toolTip);
  Future<void> setContextMenu(Menu menu);
  void addListener(TrayListener listener);
}

class TrayManagerController implements TrayController {
  @override
  Future<void> setIcon(String iconPath) => trayManager.setIcon(iconPath);

  @override
  Future<void> setToolTip(String toolTip) => trayManager.setToolTip(toolTip);

  @override
  Future<void> setContextMenu(Menu menu) => trayManager.setContextMenu(menu);

  @override
  void addListener(TrayListener listener) => trayManager.addListener(listener);
}

class TrayService with TrayListener {
  TrayService({
    required this.controller,
    required VoidCallback onSettings,
    required VoidCallback onQuit,
  })  : _onSettings = onSettings,
        _onQuit = onQuit;

  final TrayController controller;
  final VoidCallback _onSettings;
  final VoidCallback _onQuit;

  Future<void> initialize(String iconPath) async {
    await controller.setIcon(iconPath);
    await controller.setContextMenu(Menu(items: [
      MenuItem(key: 'settings', label: 'Settings...'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]));
    controller.addListener(this);
  }

  Future<void> showHotkeyConflictWarning() async {
    await controller.setToolTip(
      'Insight: shortcut conflict — open Settings to rebind',
    );
    await controller.setContextMenu(Menu(items: [
      MenuItem(key: 'hotkeyConflict', label: '⚠ Shortcut conflict — rebind...'),
      MenuItem.separator(),
      MenuItem(key: 'settings', label: 'Settings...'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]));
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'settings' || menuItem.key == 'hotkeyConflict') {
      _onSettings();
    } else if (menuItem.key == 'quit') {
      _onQuit();
    }
  }
}
```

- [ ] **Step 8: Run the tray service test to verify it passes**

Run: `flutter test test/services/tray_service_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 9: Commit**

```bash
git add lib/services/tray_service.dart lib/services/auto_start_sync.dart test/services/tray_service_test.dart test/services/auto_start_sync_test.dart
git commit -m "feat: add tray service and launch-at-login sync"
```

---

### Task 8: Hotkey service, main window/popup window wiring, and macOS accessibility prompt

**Files:**
- Create: `lib/services/hotkey_service.dart`
- Test: `test/services/hotkey_service_test.dart`
- Modify: `lib/main.dart`
- Test: `test/main_test.dart`

**Interfaces:**
- Consumes: `AppSettings`/`SettingsRepository` (Task 2), `ClipboardCaptureService`/`PlatformKeySimulator`/`SystemClipboardAccess` (Task 3), `WorkersAiClient` (Task 4), `ExplanationController`/`PopupScreen` (Task 5), `SettingsScreen` (Task 6), `TrayService`/`TrayManagerController`/`AutoStartSync`/`LaunchAtStartupController` (Task 7).
- Produces: `abstract class HotkeyController { Future<void> register(HotKey hotKey, {required void Function(HotKey) onKeyDown}); Future<void> unregisterAll(); }`, `HotkeyManagerController implements HotkeyController`, `class HotkeyService { HotkeyService(HotkeyController controller); bool get registrationFailed; Future<void> applyShortcut(AppSettings settings, void Function() onTriggered); }`, and `Rect computePopupFrame(Offset cursor, {Size size})` (used by `main.dart`, kept as a small pure function for testability). `main.dart` also: (a) tracks the single open popup window id and closes any existing one before opening a new one, so a second hotkey press never stacks a second popup; (b) registers a `WindowListener` on the popup window that closes it on `onWindowBlur`, and wires `PopupScreen.onDismiss` to close it on Esc; (c) passes `onSaved` to `SettingsScreen` so saving settings re-runs `HotkeyService.applyShortcut` immediately, without an app restart; (d) on hotkey registration failure, calls `TrayService.showHotkeyConflictWarning()` (all platforms) in addition to opening the macOS Accessibility pane (macOS only).

- [ ] **Step 1: Write the failing test for the hotkey service**

Create `test/services/hotkey_service_test.dart`:

```dart
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
      ),
      () {},
    );

    expect(service.registrationFailed, isTrue);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/services/hotkey_service_test.dart`
Expected: FAIL — compile error, `HotkeyController`/`HotkeyService` not defined.

- [ ] **Step 3: Implement the hotkey service**

Create `lib/services/hotkey_service.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../app/settings_model.dart';

const Map<String, PhysicalKeyboardKey> kSupportedShortcutKeys = {
  'keyA': PhysicalKeyboardKey.keyA, 'keyB': PhysicalKeyboardKey.keyB,
  'keyC': PhysicalKeyboardKey.keyC, 'keyD': PhysicalKeyboardKey.keyD,
  'keyE': PhysicalKeyboardKey.keyE, 'keyF': PhysicalKeyboardKey.keyF,
  'keyG': PhysicalKeyboardKey.keyG, 'keyH': PhysicalKeyboardKey.keyH,
  'keyI': PhysicalKeyboardKey.keyI, 'keyJ': PhysicalKeyboardKey.keyJ,
  'keyK': PhysicalKeyboardKey.keyK, 'keyL': PhysicalKeyboardKey.keyL,
  'keyM': PhysicalKeyboardKey.keyM, 'keyN': PhysicalKeyboardKey.keyN,
  'keyO': PhysicalKeyboardKey.keyO, 'keyP': PhysicalKeyboardKey.keyP,
  'keyQ': PhysicalKeyboardKey.keyQ, 'keyR': PhysicalKeyboardKey.keyR,
  'keyS': PhysicalKeyboardKey.keyS, 'keyT': PhysicalKeyboardKey.keyT,
  'keyU': PhysicalKeyboardKey.keyU, 'keyV': PhysicalKeyboardKey.keyV,
  'keyW': PhysicalKeyboardKey.keyW, 'keyX': PhysicalKeyboardKey.keyX,
  'keyY': PhysicalKeyboardKey.keyY, 'keyZ': PhysicalKeyboardKey.keyZ,
};

PhysicalKeyboardKey _mapKey(String name) {
  final key = kSupportedShortcutKeys[name];
  if (key == null) throw ArgumentError('Unsupported shortcut key: $name');
  return key;
}

HotKeyModifier _mapModifier(String name) => switch (name) {
      'meta' => HotKeyModifier.meta,
      'control' => HotKeyModifier.control,
      'shift' => HotKeyModifier.shift,
      'alt' => HotKeyModifier.alt,
      _ => throw ArgumentError('Unsupported modifier: $name'),
    };

abstract class HotkeyController {
  Future<void> register(HotKey hotKey, {required void Function(HotKey) onKeyDown});
  Future<void> unregisterAll();
}

class HotkeyManagerController implements HotkeyController {
  @override
  Future<void> register(HotKey hotKey, {required void Function(HotKey) onKeyDown}) =>
      hotKeyManager.register(hotKey, keyDownHandler: onKeyDown);

  @override
  Future<void> unregisterAll() => hotKeyManager.unregisterAll();
}

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

- [ ] **Step 4: Run the hotkey service test to verify it passes**

Run: `flutter test test/services/hotkey_service_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Wire everything together in `main.dart`**

Replace `lib/main.dart` with:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'app/settings_model.dart';
import 'app/settings_repository.dart';
import 'services/auto_start_sync.dart';
import 'services/clipboard_capture_service.dart';
import 'services/hotkey_service.dart';
import 'services/tray_service.dart';
import 'services/workers_ai_client.dart';
import 'ui/popup/explanation_controller.dart';
import 'ui/popup/popup_screen.dart';
import 'ui/settings/settings_screen.dart';

Rect computePopupFrame(Offset cursor, {Size size = const Size(360, 200)}) {
  return Rect.fromLTWH(cursor.dx, cursor.dy, size.width, size.height);
}

Future<void> openMacAccessibilitySettings() async {
  if (Platform.isMacOS) {
    await Process.run('open', [
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
    ]);
  }
}

// NOTE ON desktop_multi_window's REAL API (found while implementing this
// task — the version that resolves for this project's SDK constraint,
// 0.3.0, differs from older versions some examples online show):
// there is no `DesktopMultiWindow.createWindow`/`.invokeMethod(id, ...)`
// static API, windowId is a String (not int), and there is no
// `setFrame`/`setTitle` on `WindowController`. Instead: every window
// (primary and popup alike) shares one `main()`; each calls
// `WindowController.fromCurrentEngine()` to read its own `arguments`
// (empty string ⇒ this is the primary window). A new window is spawned
// with `WindowController.create(WindowConfiguration(arguments: ...))`,
// and each window sizes/positions/shows *itself* via `window_manager`
// (whose channel is scoped to whichever engine/window called it) once its
// own `main()` runs. Cross-window calls (popup asking the main window to
// open Settings; main window closing a previous popup) go through
// `WindowController.fromWindowId(id).invokeMethod(method)`, handled by a
// `setWindowMethodHandler` the target window registered on itself.

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

// window_manager's channel targets whichever window this isolate/engine
// belongs to, so a popup window closes itself directly on blur — no
// cross-window WindowController call is needed for that.
class _PopupBlurListener extends WindowListener {
  @override
  void onWindowBlur() {
    windowManager.close();
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

  windowManager.addListener(_PopupBlurListener());

  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: frame.size,
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
    home: PopupScreen(
      controller: ExplanationController(client: WorkersAiClient()),
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

Future<void> _runMainWindow(WindowController windowController) async {
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(skipTaskbar: true, titleBarStyle: TitleBarStyle.hidden),
    () async {
      await windowManager.hide();
    },
  );

  final repository = SettingsRepository();
  var settings = await repository.load();

  await AutoStartSync(LaunchAtStartupController()).applySetting(settings.launchAtLogin);

  final clipboardCapture = ClipboardCaptureService(
    keySimulator: PlatformKeySimulator(),
    clipboard: SystemClipboardAccess(),
  );

  final hotkeyService = HotkeyService(HotkeyManagerController());
  final trayService = TrayService(
    controller: TrayManagerController(),
    onSettings: () async {
      await windowManager.show();
      await windowManager.focus();
    },
    onQuit: () => windowManager.close(),
  );
  await trayService.initialize('assets/tray_icon.png');

  await windowController.setWindowMethodHandler((call) async {
    if (call.method == 'openSettings') {
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

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SettingsScreen(
      repository: repository,
      onSaved: () async {
        settings = await repository.load();
        await applyHotkey(settings);
      },
    ),
  ));
}
```

- [ ] **Step 6: Write and run a test for the pure popup-frame helper**

Create `test/main_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight/main.dart';

void main() {
  test('computePopupFrame anchors a 360x200 frame at the cursor by default', () {
    final frame = computePopupFrame(const Offset(100, 200));

    expect(frame, const Rect.fromLTWH(100, 200, 360, 200));
  });

  test('computePopupFrame accepts a custom size', () {
    final frame = computePopupFrame(const Offset(0, 0), size: const Size(300, 150));

    expect(frame, const Rect.fromLTWH(0, 0, 300, 150));
  });
}
```

Run: `flutter test test/main_test.dart`
Expected: PASS (2 tests). This is the one automated check on `main.dart`; the rest of its wiring (hotkey → clipboard capture → popup window → tray, macOS accessibility prompt) is OS-level integration glue verified manually in Task 9.

- [ ] **Step 7: Run the full test suite to make sure nothing regressed**

Run: `flutter test`
Expected: PASS — all tests from Tasks 2-8 pass.

- [ ] **Step 8: Commit**

```bash
git add lib/services/hotkey_service.dart test/services/hotkey_service_test.dart lib/main.dart test/main_test.dart
git commit -m "feat: wire hotkey capture, popup window, and macOS accessibility prompt in main.dart"
```

---

### Task 9: Manual verification

**Files:** none (verification only — no code changes).

This task has no automated test: it exercises real OS-level behavior (global hotkeys, clipboard, popup windows, tray icon, login items) that cannot be driven from `flutter test`. Complete every item below before considering the feature done.

- [ ] **Step 1: Configure real settings**

Run the app (`flutter run -d macos`), open Settings from the tray icon, and enter a real Cloudflare Account ID, API Token, and model (e.g. `@cf/meta/llama-3.1-8b-instruct`). Save.

- [ ] **Step 2: Verify the hotkey + popup flow in a browser**

Select a sentence in a web browser, press the configured shortcut (default `Cmd+Shift+E` on macOS). Confirm: a popup appears near the cursor, shows a loading spinner, then streams in an explanation.

- [ ] **Step 3: Verify the hotkey + popup flow in a plain text editor and a PDF viewer**

Repeat Step 2 in a plain-text editor (e.g. TextEdit/Notepad) and a PDF viewer. Confirm the same behavior.

- [ ] **Step 4: Verify clipboard restore**

Copy some known text to the clipboard manually. Select different text elsewhere and trigger the shortcut. After the popup appears, paste somewhere — confirm the clipboard has been restored to the text you copied manually, not the text that was selected for explanation.

- [ ] **Step 5: Verify the "no selection" case**

Click somewhere with no text selected and trigger the shortcut. Confirm the popup shows "No text selected".

- [ ] **Step 6: Verify dismissal**

With a popup open, click outside it. Confirm the `_PopupBlurListener`'s `onWindowBlur` closes it. Repeat and press Esc instead — confirm `PopupScreen`'s `Focus.onKeyEvent` handler closes it via `onDismiss`. Also trigger the shortcut twice in quick succession and confirm the first popup is closed rather than leaving two popups open (the `openPopupWindowId` guard in `main.dart`).

- [ ] **Step 7: Verify macOS accessibility permission handling**

On a clean macOS user account (or after revoking Accessibility permission for the app in System Settings), launch the app and trigger the shortcut. Confirm the app opens System Settings' Accessibility pane rather than silently failing. Grant permission and confirm the shortcut then works after re-triggering.

- [ ] **Step 8: Verify launch at login**

Enable "Launch at login" in Settings, restart the machine (or log out/in), and confirm the app is running (tray icon visible) without being manually launched. Disable the toggle and confirm it no longer launches automatically.

- [ ] **Step 9: Repeat Steps 1-6 and 8 on Windows**

If Windows hardware/VM was not available during earlier tasks, run through the same checks on Windows now, using `Ctrl+Shift+E` as the default shortcut. Note any Windows-specific issues (e.g. `SendInput` timing, tray icon rendering) and fix before shipping.

- [ ] **Step 10: Record results**

Note the outcome of each step (pass/fail + any fixes made) in the PR description or commit message when this feature branch is finalized.
