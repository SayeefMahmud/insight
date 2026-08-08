import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insight/ui/app/app_navigation.dart';
import 'package:insight/ui/app/main_app_screen.dart';

void main() {
  testWidgets('shows Home content initially and switches tabs on tap', (tester) async {
    final navigation = AppNavigation();

    await tester.pumpWidget(MaterialApp(
      home: MainAppScreen(
        navigation: navigation,
        homeScreen: const Text('HOME CONTENT'),
        historyScreen: const Text('HISTORY CONTENT'),
        settingsScreen: const Text('SETTINGS CONTENT'),
      ),
    ));

    expect(find.text('HOME CONTENT'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('HISTORY CONTENT'), findsOneWidget);
    expect(navigation.activeTab.value, AppTab.history);
  });

  testWidgets('external navigation.activeTab changes switch the visible tab', (tester) async {
    final navigation = AppNavigation();

    await tester.pumpWidget(MaterialApp(
      home: MainAppScreen(
        navigation: navigation,
        homeScreen: const Text('HOME CONTENT'),
        historyScreen: const Text('HISTORY CONTENT'),
        settingsScreen: const Text('SETTINGS CONTENT'),
      ),
    ));

    navigation.goToSettings();
    await tester.pumpAndSettle();

    expect(find.text('SETTINGS CONTENT'), findsOneWidget);
  });
}
