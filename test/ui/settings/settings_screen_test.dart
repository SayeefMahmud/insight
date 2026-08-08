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
      themeMode: 'dark',
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
