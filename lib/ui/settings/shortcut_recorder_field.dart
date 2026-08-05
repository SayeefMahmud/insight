import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ShortcutRecorderField extends StatefulWidget {
  const ShortcutRecorderField({
    super.key,
    required this.shortcutKey,
    required this.modifiers,
    required this.onChanged,
  });

  final String shortcutKey;
  final List<String> modifiers;
  final void Function(String key, List<String> modifiers) onChanged;

  @override
  State<ShortcutRecorderField> createState() => _ShortcutRecorderFieldState();
}

class _ShortcutRecorderFieldState extends State<ShortcutRecorderField> {
  bool _recording = false;
  final _focusNode = FocusNode();

  String _describe(String key, List<String> modifiers) {
    final modLabels = modifiers.map((m) => m[0].toUpperCase() + m.substring(1)).join('+');
    final keyLabel = key.replaceFirst('key', '').toUpperCase();
    return modLabels.isEmpty ? keyLabel : '$modLabels+$keyLabel';
  }

  void _handleKey(KeyEvent event) {
    if (!_recording || event is! KeyDownEvent) return;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final modifiers = <String>[
      if (pressed.contains(LogicalKeyboardKey.metaLeft) ||
          pressed.contains(LogicalKeyboardKey.metaRight))
        'meta',
      if (pressed.contains(LogicalKeyboardKey.controlLeft) ||
          pressed.contains(LogicalKeyboardKey.controlRight))
        'control',
      if (pressed.contains(LogicalKeyboardKey.shiftLeft) ||
          pressed.contains(LogicalKeyboardKey.shiftRight))
        'shift',
      if (pressed.contains(LogicalKeyboardKey.altLeft) ||
          pressed.contains(LogicalKeyboardKey.altRight))
        'alt',
    ];

    final label = event.logicalKey.debugName ?? '';
    if (label.startsWith('Key ')) {
      final key = 'key${label.substring(4)}';
      setState(() => _recording = false);
      widget.onChanged(key, modifiers);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: OutlinedButton(
        onPressed: () {
          setState(() => _recording = true);
          _focusNode.requestFocus();
        },
        child: Text(_recording ? 'Press keys...' : _describe(widget.shortcutKey, widget.modifiers)),
      ),
    );
  }
}
