import 'dart:math';

enum TurnRole { user, assistant }

class SessionTurn {
  const SessionTurn({
    required this.role,
    required this.content,
    required this.timestamp,
  });

  final TurnRole role;
  final String content;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  static SessionTurn fromJson(Map<String, dynamic> json) => SessionTurn(
        role: TurnRole.values.byName(json['role'] as String),
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

class ExplanationSession {
  const ExplanationSession({
    required this.id,
    required this.selectedText,
    required this.createdAt,
    required this.turns,
  });

  final String id;
  final String selectedText;
  final DateTime createdAt;
  final List<SessionTurn> turns;

  DateTime get lastActivityAt => turns.isEmpty ? createdAt : turns.last.timestamp;

  ExplanationSession copyWith({List<SessionTurn>? turns}) => ExplanationSession(
        id: id,
        selectedText: selectedText,
        createdAt: createdAt,
        turns: turns ?? this.turns,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'selectedText': selectedText,
        'createdAt': createdAt.toIso8601String(),
        'turns': turns.map((t) => t.toJson()).toList(),
      };

  static ExplanationSession fromJson(Map<String, dynamic> json) => ExplanationSession(
        id: json['id'] as String,
        selectedText: json['selectedText'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        turns: (json['turns'] as List)
            .map((t) => SessionTurn.fromJson(t as Map<String, dynamic>))
            .toList(),
      );
}

String generateSessionId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
