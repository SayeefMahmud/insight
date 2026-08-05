import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight/ui/settings/shortcut_recorder_field.dart';

void main() {
  testWidgets('records meta+shift+E and reports it via onChanged', (tester) async {
    String? capturedKey;
    List<String>? capturedModifiers;

    await tester.pumpWidget(MaterialApp(
      home: ShortcutRecorderField(
        shortcutKey: 'keyE',
        modifiers: const ['meta', 'shift'],
        onChanged: (key, modifiers) {
          capturedKey = key;
          capturedModifiers = modifiers;
        },
      ),
    ));

    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
    await tester.pump();

    expect(capturedKey, 'keyE');
    expect(capturedModifiers, containsAll(['meta', 'shift']));
  });
}
