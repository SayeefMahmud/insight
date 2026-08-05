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
              value: kCommonWorkersAiModels.contains(_modelController.text)
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
