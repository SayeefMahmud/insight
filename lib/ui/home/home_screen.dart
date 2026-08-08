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
    final modLabels = settings.shortcutModifiers
        .map((m) => m[0].toUpperCase() + m.substring(1))
        .join('+');
    final keyLabel = settings.shortcutKey.replaceFirst('key', '').toUpperCase();
    return modLabels.isEmpty ? keyLabel : '$modLabels+$keyLabel';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.hotkeyService,
      builder: (context, _) {
        final settings = _settings;
        return Material(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  key: const Key('shortcutStatus'),
                  leading: Icon(
                    widget.hotkeyService.registrationFailed
                        ? Icons.warning
                        : Icons.check_circle,
                    color: widget.hotkeyService.registrationFailed
                        ? Colors.orange
                        : Colors.green,
                  ),
                  title: Text(
                    settings == null
                        ? 'Loading...'
                        : 'Shortcut: ${_describeShortcut(settings)}',
                  ),
                  subtitle: Text(
                    widget.hotkeyService.registrationFailed
                        ? 'Conflict — rebind in Settings'
                        : 'Registered',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Recent activity',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No explanations yet'),
                ),
              for (final session in _recent)
                ListTile(
                  key: Key('recent-${session.id}'),
                  title: Text(
                    session.selectedText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => widget.navigation.openSession(session.id),
                ),
            ],
          ),
        );
      },
    );
  }
}
