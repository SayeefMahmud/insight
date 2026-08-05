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
