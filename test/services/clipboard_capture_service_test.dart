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
    when(() => clipboard.writeText(any())).thenAnswer((_) async {});
    service = ClipboardCaptureService(
      keySimulator: keySimulator,
      clipboard: clipboard,
      copyDelay: Duration.zero,
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
}
