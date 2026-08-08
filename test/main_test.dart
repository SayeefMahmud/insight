import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight/main.dart';

void main() {
  test('computePopupFrame anchors a 420x520 frame at the cursor by default', () {
    final frame = computePopupFrame(const Offset(100, 200));

    expect(frame, const Rect.fromLTWH(100, 200, 420, 520));
  });

  test('computePopupFrame accepts a custom size', () {
    final frame = computePopupFrame(const Offset(0, 0), size: const Size(300, 150));

    expect(frame, const Rect.fromLTWH(0, 0, 300, 150));
  });
}
