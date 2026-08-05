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
