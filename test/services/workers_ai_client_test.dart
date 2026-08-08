import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:insight/services/workers_ai_client.dart';

void main() {
  test('streams decoded text chunks from an SSE payload', () async {
    final sseBody = 'data: {"response":"Hello"}\n\n'
        'data: {"response":" world"}\n\n'
        'data: [DONE]\n\n';
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.url.toString(), contains('/accounts/acct/ai/run/'));
      return http.Response(sseBody, 200);
    });
    final aiClient = WorkersAiClient(httpClient: client);

    final chunks = await aiClient
        .streamChat(
          accountId: 'acct',
          apiToken: 'test-token',
          model: '@cf/meta/llama-3.1-8b-instruct',
          messages: const [ChatMessage(role: ChatRole.user, content: 'Explain: hi')],
        )
        .toList();

    expect(chunks.join(), 'Hello world');
  });

  test('sends the full conversation as the messages array', () async {
    late String sentBody;
    final capturingClient = MockClient((request) async {
      sentBody = utf8.decode(request.bodyBytes);
      return http.Response('data: [DONE]\n\n', 200);
    });
    final aiClient = WorkersAiClient(httpClient: capturingClient);

    await aiClient
        .streamChat(
          accountId: 'acct',
          apiToken: 'token',
          model: 'm',
          messages: const [
            ChatMessage(role: ChatRole.user, content: 'Explain: hi'),
            ChatMessage(role: ChatRole.assistant, content: 'It means hello.'),
            ChatMessage(role: ChatRole.user, content: 'In French?'),
          ],
        )
        .toList();

    expect(sentBody, contains('"role":"user"'));
    expect(sentBody, contains('"role":"assistant"'));
    expect(sentBody, contains('In French?'));
  });

  test('throws WorkersAiException on a non-200 response', () async {
    final client = MockClient((request) async => http.Response('bad token', 401));
    final aiClient = WorkersAiClient(httpClient: client);

    expect(
      () => aiClient
          .streamChat(
            accountId: 'acct',
            apiToken: 'bad',
            model: 'm',
            messages: const [ChatMessage(role: ChatRole.user, content: 'p')],
          )
          .toList(),
      throwsA(isA<WorkersAiException>()),
    );
  });
}
