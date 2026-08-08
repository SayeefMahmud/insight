class AppSettings {
  const AppSettings({
    required this.accountId,
    required this.apiToken,
    required this.model,
    required this.promptTemplate,
    required this.shortcutKey,
    required this.shortcutModifiers,
    required this.launchAtLogin,
    required this.themeMode,
  });

  final String accountId;
  final String apiToken;
  final String model;
  final String promptTemplate;
  final String shortcutKey;
  final List<String> shortcutModifiers;
  final bool launchAtLogin;
  final String themeMode;

  static const defaultModel = '@cf/meta/llama-3.1-8b-instruct';
  static const defaultPromptTemplate =
      'Explain the following text concisely:\n\n{{selection}}';
  static const defaultShortcutKey = 'keyE';
  static const defaultShortcutModifiers = ['meta', 'shift'];
  static const defaultThemeMode = 'dark';

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'apiToken': apiToken,
        'model': model,
        'promptTemplate': promptTemplate,
        'shortcutKey': shortcutKey,
        'shortcutModifiers': shortcutModifiers,
        'launchAtLogin': launchAtLogin,
        'themeMode': themeMode,
      };

  static AppSettings fromJson(Map<String, dynamic> json) => AppSettings(
        accountId: json['accountId'] as String,
        apiToken: json['apiToken'] as String,
        model: json['model'] as String,
        promptTemplate: json['promptTemplate'] as String,
        shortcutKey: json['shortcutKey'] as String,
        shortcutModifiers: List<String>.from(json['shortcutModifiers'] as List),
        launchAtLogin: json['launchAtLogin'] as bool,
        themeMode: json['themeMode'] as String,
      );
}
