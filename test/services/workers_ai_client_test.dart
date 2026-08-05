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
        .streamExplanation(
          accountId: 'acct',
          apiToken: 'test-token',
          model: '@cf/meta/llama-3.1-8b-instruct',
          prompt: 'Explain: hi',
        )
        .toList();

    expect(chunks.join(), 'Hello world');
  });

  test('throws WorkersAiException on a non-200 response', () async {
    final client = MockClient((request) async => http.Response('bad token', 401));
    final aiClient = WorkersAiClient(httpClient: client);

    expect(
      () => aiClient
          .streamExplanation(
            accountId: 'acct',
            apiToken: 'bad',
            model: 'm',
            prompt: 'p',
          )
          .toList(),
      throwsA(isA<WorkersAiException>()),
    );
  });
}
