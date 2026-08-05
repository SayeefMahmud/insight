import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:insight/services/auto_start_sync.dart';

class MockAutoStartController extends Mock implements AutoStartController {}

void main() {
  late MockAutoStartController controller;
  late AutoStartSync sync;

  setUp(() {
    controller = MockAutoStartController();
    sync = AutoStartSync(controller);
  });

  test('enables auto-start when requested and currently disabled', () async {
    when(() => controller.isEnabled()).thenAnswer((_) async => false);
    when(() => controller.enable()).thenAnswer((_) async {});

    await sync.applySetting(true);

    verify(() => controller.enable()).called(1);
    verifyNever(() => controller.disable());
  });

  test('disables auto-start when requested off and currently enabled', () async {
    when(() => controller.isEnabled()).thenAnswer((_) async => true);
    when(() => controller.disable()).thenAnswer((_) async {});

    await sync.applySetting(false);

    verify(() => controller.disable()).called(1);
    verifyNever(() => controller.enable());
  });

  test('does nothing when already in the desired state', () async {
    when(() => controller.isEnabled()).thenAnswer((_) async => true);

    await sync.applySetting(true);

    verifyNever(() => controller.enable());
    verifyNever(() => controller.disable());
  });
}
