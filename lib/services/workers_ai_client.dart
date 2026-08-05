import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class WorkersAiException implements Exception {
  WorkersAiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class WorkersAiClient {
  WorkersAiClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Stream<String> streamExplanation({
    required String accountId,
    required String apiToken,
    required String model,
    required String prompt,
  }) async* {
    final uri = Uri.parse(
      'https://api.cloudflare.com/client/v4/accounts/$accountId/ai/run/$model',
    );
    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $apiToken'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'stream': true,
      });

    final streamedResponse = await _httpClient.send(request);

    if (streamedResponse.statusCode != 200) {
      final body = await streamedResponse.stream.bytesToString();
      throw WorkersAiException(
        'Workers AI request failed (${streamedResponse.statusCode}): $body',
      );
    }

    final lines =
        streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data.isEmpty) continue;
      if (data == '[DONE]') break;
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      final chunk = decoded['response'] as String?;
      if (chunk != null && chunk.isNotEmpty) {
        yield chunk;
      }
    }
  }
}
