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
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  void _submit() {
    final text = _inputController.text;
    if (text.trim().isEmpty) return;
    _inputController.clear();
    widget.controller.sendFollowUp(text);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: AnimatedBuilder(
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
      ),
    );
  }

  Widget _buildSession(SessionController controller, {required bool showError}) {
    final session = controller.session!;
    final hasAssistantTurn = session.turns.any((t) => t.role == TurnRole.assistant);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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
            key: const Key('conversationScrollView'),
            controller: _scrollController,
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
