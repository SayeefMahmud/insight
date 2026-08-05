import 'package:flutter/foundation.dart';

import '../../app/settings_model.dart';
import '../../services/workers_ai_client.dart';

enum PopupStatus { loading, noSelection, streaming, error }

class ExplanationController extends ChangeNotifier {
  ExplanationController({required WorkersAiClient client}) : _client = client;

  final WorkersAiClient _client;

  PopupStatus status = PopupStatus.loading;
  String text = '';
  String errorMessage = '';

  Future<void> start({
    required String? capturedText,
    required AppSettings settings,
  }) async {
    if (capturedText == null) {
      status = PopupStatus.noSelection;
      notifyListeners();
      return;
    }
    if (settings.accountId.isEmpty || settings.apiToken.isEmpty) {
      status = PopupStatus.error;
      errorMessage =
          'Cloudflare account ID or API token is missing. Open Settings to configure.';
      notifyListeners();
      return;
    }

    status = PopupStatus.streaming;
    text = '';
    notifyListeners();

    final prompt = settings.promptTemplate.replaceAll('{{selection}}', capturedText);
    try {
      await for (final chunk in _client.streamExplanation(
        accountId: settings.accountId,
        apiToken: settings.apiToken,
        model: settings.model,
        prompt: prompt,
      )) {
        text += chunk;
        notifyListeners();
      }
    } catch (e) {
      status = PopupStatus.error;
      errorMessage = e.toString();
      notifyListeners();
    }
  }
}
