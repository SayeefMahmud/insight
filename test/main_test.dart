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

  group('clampFrameToScreen', () {
    const screen = Rect.fromLTWH(0, 0, 1440, 900);

    test('leaves a frame that already fits untouched', () {
      const frame = Rect.fromLTWH(100, 100, 420, 520);

      expect(clampFrameToScreen(frame, screen), frame);
    });

    test('shifts up when the bottom would be cropped', () {
      const frame = Rect.fromLTWH(100, 700, 420, 520);

      final clamped = clampFrameToScreen(frame, screen);

      expect(clamped.top, screen.bottom - frame.height);
      expect(clamped.left, 100);
      expect(clamped.size, frame.size);
    });

    test('shifts left when the right edge would be cropped', () {
      const frame = Rect.fromLTWH(1300, 100, 420, 520);

      final clamped = clampFrameToScreen(frame, screen);

      expect(clamped.left, screen.right - frame.width);
      expect(clamped.top, 100);
    });

    test('clamps to the screen origin when the frame is larger than the screen', () {
      const frame = Rect.fromLTWH(-50, -50, 2000, 2000);

      final clamped = clampFrameToScreen(frame, screen);

      expect(clamped.left, screen.left);
      expect(clamped.top, screen.top);
    });
  });
}
