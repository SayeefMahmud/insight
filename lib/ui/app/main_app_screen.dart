import 'package:flutter/material.dart';

import 'app_navigation.dart';

class MainAppScreen extends StatefulWidget {
  const MainAppScreen({
    super.key,
    required this.navigation,
    required this.homeScreen,
    required this.historyScreen,
    required this.settingsScreen,
  });

  final AppNavigation navigation;
  final Widget homeScreen;
  final Widget historyScreen;
  final Widget settingsScreen;

  @override
  State<MainAppScreen> createState() => _MainAppScreenState();
}

class _MainAppScreenState extends State<MainAppScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.navigation.activeTab.value.index,
    );
    widget.navigation.activeTab.addListener(_onExternalTabChange);
    _tabController.addListener(_onTabControllerChange);
  }

  void _onExternalTabChange() {
    final index = widget.navigation.activeTab.value.index;
    if (_tabController.index != index) {
      _tabController.animateTo(index);
    }
  }

  void _onTabControllerChange() {
    if (_tabController.indexIsChanging) return;
    final tab = AppTab.values[_tabController.index];
    if (widget.navigation.activeTab.value != tab) {
      widget.navigation.activeTab.value = tab;
    }
  }

  @override
  void dispose() {
    widget.navigation.activeTab.removeListener(_onExternalTabChange);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Insight'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.home), text: 'Home'),
            Tab(icon: Icon(Icons.history), text: 'History'),
            Tab(icon: Icon(Icons.settings), text: 'Settings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [widget.homeScreen, widget.historyScreen, widget.settingsScreen],
      ),
    );
  }
}
