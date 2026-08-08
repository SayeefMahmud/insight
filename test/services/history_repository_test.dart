import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:insight/domain/session.dart';
import 'package:insight/services/history_repository.dart';

class MockHistoryFileStorage extends Mock implements HistoryFileStorage {}

ExplanationSession _session({
  required String id,
  required DateTime lastActivity,
  String selectedText = 'text',
}) =>
    ExplanationSession(
      id: id,
      selectedText: selectedText,
      createdAt: lastActivity,
      turns: [
        SessionTurn(role: TurnRole.assistant, content: 'reply $id', timestamp: lastActivity),
      ],
    );

void main() {
  late MockHistoryFileStorage storage;
  late HistoryRepository repository;

  setUp(() {
    storage = MockHistoryFileStorage();
    repository = HistoryRepository(storage: storage);
  });

  test('loadAll returns empty list when nothing is stored', () async {
    when(() => storage.read()).thenAnswer((_) async => null);

    final result = await repository.loadAll();

    expect(result, isEmpty);
  });

  test('loadAll returns empty list when the stored file is corrupt', () async {
    when(() => storage.read()).thenAnswer((_) async => 'not valid json{{{');

    final result = await repository.loadAll();

    expect(result, isEmpty);
  });

  test('loadAll sorts by lastActivityAt descending', () async {
    final older = _session(id: 'older', lastActivity: DateTime.now().subtract(const Duration(days: 5)));
    final newer = _session(id: 'newer', lastActivity: DateTime.now().subtract(const Duration(days: 1)));
    when(() => storage.read()).thenAnswer((_) async => '[${_jsonOf(older)},${_jsonOf(newer)}]');

    final result = await repository.loadAll();

    expect(result.map((s) => s.id).toList(), ['newer', 'older']);
  });

  test('loadAll prunes sessions older than 30 days and persists the pruned list', () async {
    final stale = _session(
      id: 'stale',
      lastActivity: DateTime.now().subtract(const Duration(days: 31)),
    );
    final fresh = _session(id: 'fresh', lastActivity: DateTime.now());
    when(() => storage.read()).thenAnswer((_) async => '[${_jsonOf(stale)},${_jsonOf(fresh)}]');
    when(() => storage.write(any())).thenAnswer((_) async {});

    final result = await repository.loadAll();

    expect(result.map((s) => s.id).toList(), ['fresh']);
    final written = verify(() => storage.write(captureAny())).captured.single as String;
    expect(written, isNot(contains('stale')));
  });

  test('save upserts a session by id', () async {
    final existing = _session(id: '1', lastActivity: DateTime.utc(2026, 1, 1));
    when(() => storage.read()).thenAnswer((_) async => '[${_jsonOf(existing)}]');
    String? written;
    when(() => storage.write(any())).thenAnswer((invocation) async {
      written = invocation.positionalArguments.single as String;
    });

    final updated = existing.copyWith(turns: [
      ...existing.turns,
      SessionTurn(role: TurnRole.user, content: 'follow-up', timestamp: DateTime.utc(2026, 1, 2)),
    ]);
    await repository.save(updated);

    expect(written, contains('follow-up'));
    expect(written!.split('"id":"1"').length, 2); // appears exactly once, not duplicated
  });

  test('delete removes a session by id', () async {
    final a = _session(id: 'a', lastActivity: DateTime.utc(2026, 1, 1));
    final b = _session(id: 'b', lastActivity: DateTime.utc(2026, 1, 2));
    when(() => storage.read()).thenAnswer((_) async => '[${_jsonOf(a)},${_jsonOf(b)}]');
    String? written;
    when(() => storage.write(any())).thenAnswer((invocation) async {
      written = invocation.positionalArguments.single as String;
    });

    await repository.delete('a');

    expect(written, isNot(contains('"id":"a"')));
    expect(written, contains('"id":"b"'));
  });
}

String _jsonOf(ExplanationSession session) {
  final map = session.toJson();
  final buffer = StringBuffer('{');
  buffer.write('"id":"${map['id']}",');
  buffer.write('"selectedText":"${map['selectedText']}",');
  buffer.write('"createdAt":"${map['createdAt']}",');
  buffer.write('"turns":[');
  buffer.write((map['turns'] as List).map((t) {
    final turn = t as Map<String, dynamic>;
    return '{"role":"${turn['role']}","content":"${turn['content']}","timestamp":"${turn['timestamp']}"}';
  }).join(','));
  buffer.write(']}');
  return buffer.toString();
}
