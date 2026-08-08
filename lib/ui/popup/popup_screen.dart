import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/settings_model.dart';
import '../session/conversation_view.dart';
import '../session/session_controller.dart';

class PopupScreen extends StatefulWidget {
  const PopupScreen({
    super.key,
    required this.controller,
    required this.capturedText,
    required this.settings,
    this.onOpenSettings,
    this.onDismiss,
  });

  final SessionController controller;
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
      child: Material(
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ConversationView(
          controller: widget.controller,
          onOpenSettings: widget.onOpenSettings,
          onClose: widget.onDismiss,
        ),
      ),
    );
  }
}
