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
      return Material(
        child: Column(
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
        ),
      );
    }

    return Material(
      child: Column(
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
      ),
    );
  }
}
