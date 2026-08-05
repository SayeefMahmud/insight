import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/settings_model.dart';
import 'explanation_controller.dart';

class PopupScreen extends StatefulWidget {
  const PopupScreen({
    super.key,
    required this.controller,
    required this.capturedText,
    required this.settings,
    this.onOpenSettings,
    this.onDismiss,
  });

  final ExplanationController controller;
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

  static const _spinner = SizedBox(
    height: 24,
    width: 24,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

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
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          return Material(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: switch (controller.status) {
                PopupStatus.loading => _spinner,
                PopupStatus.noSelection => const Text(
                    'No text selected',
                    style: TextStyle(color: Colors.white),
                  ),
                PopupStatus.streaming => controller.text.isEmpty
                    ? _spinner
                    : Text(controller.text, style: const TextStyle(color: Colors.white)),
                PopupStatus.error => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(controller.errorMessage,
                          style: const TextStyle(color: Colors.redAccent)),
                      if (widget.onOpenSettings != null)
                        TextButton(
                          onPressed: widget.onOpenSettings,
                          child: const Text('Open Settings'),
                        ),
                    ],
                  ),
              },
            ),
          );
        },
      ),
    );
  }
}
