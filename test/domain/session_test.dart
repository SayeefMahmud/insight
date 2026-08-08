import 'package:flutter_test/flutter_test.dart';
import 'package:insight/domain/session.dart';

void main() {
  test('generateSessionId returns unique non-empty ids', () {
    final a = generateSessionId();
    final b = generateSessionId();

    expect(a, isNotEmpty);
    expect(a, isNot(equals(b)));
  });

  test('SessionTurn round-trips through toJson/fromJson', () {
    final turn = SessionTurn(
      role: TurnRole.assistant,
      content: 'hello',
      timestamp: DateTime.utc(2026, 1, 1, 12),
    );

    final roundTripped = SessionTurn.fromJson(turn.toJson());

    expect(roundTripped.role, TurnRole.assistant);
    expect(roundTripped.content, 'hello');
    expect(roundTripped.timestamp, DateTime.utc(2026, 1, 1, 12));
  });

  test('lastActivityAt falls back to createdAt when there are no turns', () {
    final session = ExplanationSession(
      id: '1',
      selectedText: 'text',
      createdAt: DateTime.utc(2026, 1, 1),
      turns: const [],
    );

    expect(session.lastActivityAt, DateTime.utc(2026, 1, 1));
  });

  test('lastActivityAt uses the last turn timestamp when turns exist', () {
    final session = ExplanationSession(
      id: '1',
      selectedText: 'text',
      createdAt: DateTime.utc(2026, 1, 1),
      turns: [
        SessionTurn(role: TurnRole.assistant, content: 'a', timestamp: DateTime.utc(2026, 1, 2)),
        SessionTurn(role: TurnRole.user, content: 'b', timestamp: DateTime.utc(2026, 1, 3)),
      ],
    );

    expect(session.lastActivityAt, DateTime.utc(2026, 1, 3));
  });

  test('copyWith replaces turns and keeps other fields', () {
    final session = ExplanationSession(
      id: '1',
      selectedText: 'text',
      createdAt: DateTime.utc(2026, 1, 1),
      turns: const [],
    );
    final newTurns = [
      SessionTurn(role: TurnRole.assistant, content: 'a', timestamp: DateTime.utc(2026, 1, 2)),
    ];

    final updated = session.copyWith(turns: newTurns);

    expect(updated.id, '1');
    expect(updated.selectedText, 'text');
    expect(updated.turns, newTurns);
  });

  test('ExplanationSession round-trips through toJson/fromJson', () {
    final session = ExplanationSession(
      id: '1',
      selectedText: 'text',
      createdAt: DateTime.utc(2026, 1, 1),
      turns: [
        SessionTurn(role: TurnRole.assistant, content: 'a', timestamp: DateTime.utc(2026, 1, 2)),
      ],
    );

    final roundTripped = ExplanationSession.fromJson(session.toJson());

    expect(roundTripped.id, '1');
    expect(roundTripped.selectedText, 'text');
    expect(roundTripped.createdAt, DateTime.utc(2026, 1, 1));
    expect(roundTripped.turns.single.content, 'a');
  });
}
