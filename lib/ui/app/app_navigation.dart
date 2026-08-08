import 'package:flutter/foundation.dart';

enum AppTab { home, history, settings }

class AppNavigation {
  AppNavigation()
    : activeTab = ValueNotifier(AppTab.home),
      selectedSessionId = ValueNotifier(null);

  final ValueNotifier<AppTab> activeTab;
  final ValueNotifier<String?> selectedSessionId;

  void goToSettings() => activeTab.value = AppTab.settings;

  void openSession(String id) {
    selectedSessionId.value = id;
    activeTab.value = AppTab.history;
  }
}
