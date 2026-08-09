import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:insight/services/clipboard_capture_service.dart';

class MockKeySimulator extends Mock implements KeySimulator {}
class MockClipboardAccess extends Mock implements ClipboardAccess {}

void main() {
  late MockKeySimulator keySimulator;
  late MockClipboardAccess clipboard;
  late ClipboardCaptureService service;

  setUp(() {
    keySimulator = MockKeySimulator();
    clipboard = MockClipboardAccess();
    when(() => keySimulator.simulateCopy()).thenAnswer((_) async {});
    when(() => keySimulator.hasAccessibilityPermission()).thenAnswer((_) async => true);
    when(() => clipboard.writeText(any())).thenAnswer((_) async {});
    service = ClipboardCaptureService(
      keySimulator: keySimulator,
      clipboard: clipboard,
      copyDelay: Duration.zero,
      maxWait: Duration.zero,
    );
  });

  test('returns newly copied text and restores the original clipboard', () async {
    var readCallCount = 0;
    when(() => clipboard.readText()).thenAnswer((_) async {
      readCallCount++;
      return readCallCount == 1 ? 'old clipboard value' : 'selected text';
    });

    final result = await service.captureSelection();

    expect(result, 'selected text');
    verify(() => keySimulator.simulateCopy()).called(1);
    verify(() => clipboard.writeText('old clipboard value')).called(1);
  });

  test('returns null when the clipboard is unchanged (nothing selected)', () async {
    when(() => clipboard.readText()).thenAnswer((_) async => 'same value');

    final result = await service.captureSelection();

    expect(result, isNull);
    verify(() => clipboard.writeText('same value')).called(1);
  });

  test('returns null when the captured text is empty', () async {
    var readCallCount = 0;
    when(() => clipboard.readText()).thenAnswer((_) async {
      readCallCount++;
      return readCallCount == 1 ? 'old value' : '';
    });

    final result = await service.captureSelection();

    expect(result, isNull);
  });

  test('retries within maxWait when the target app is slow to update the clipboard', () async {
    final slowService = ClipboardCaptureService(
      keySimulator: keySimulator,
      clipboard: clipboard,
      copyDelay: const Duration(milliseconds: 5),
      maxWait: const Duration(milliseconds: 200),
    );
    var readCallCount = 0;
    when(() => clipboard.readText()).thenAnswer((_) async {
      readCallCount++;
      // 1st call: original clipboard. 2nd call: app hasn't copied yet
      // (still equal to original). 3rd call: the copy has landed.
      if (readCallCount <= 2) return 'old value';
      return 'selected text';
    });

    final result = await slowService.captureSelection();

    expect(result, 'selected text');
    expect(readCallCount, 3);
  });

  test('still attempts the copy when accessibility permission is missing', () async {
    when(() => keySimulator.hasAccessibilityPermission()).thenAnswer((_) async => false);
    when(() => clipboard.readText()).thenAnswer((_) async => 'same value');

    final result = await service.captureSelection();

    expect(result, isNull);
    verify(() => keySimulator.hasAccessibilityPermission()).called(1);
    verify(() => keySimulator.simulateCopy()).called(1);
  });
}
