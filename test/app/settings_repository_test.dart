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
    expect(settings.themeMode, AppSettings.defaultThemeMode);
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
      themeMode: 'dark',
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
      themeMode: 'dark',
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
      themeMode: 'dark',
    );

    final roundTripped = AppSettings.fromJson(settings.toJson());

    expect(roundTripped.accountId, settings.accountId);
    expect(roundTripped.shortcutModifiers, settings.shortcutModifiers);
    expect(roundTripped.launchAtLogin, settings.launchAtLogin);
  });

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
}
