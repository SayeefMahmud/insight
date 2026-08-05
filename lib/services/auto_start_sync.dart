import 'package:launch_at_startup/launch_at_startup.dart';

abstract class AutoStartController {
  Future<void> enable();
  Future<void> disable();
  Future<bool> isEnabled();
}

class LaunchAtStartupController implements AutoStartController {
  @override
  Future<void> enable() => launchAtStartup.enable();

  @override
  Future<void> disable() => launchAtStartup.disable();

  @override
  Future<bool> isEnabled() => launchAtStartup.isEnabled();
}

class AutoStartSync {
  AutoStartSync(this._controller);

  final AutoStartController _controller;

  Future<void> applySetting(bool shouldLaunchAtLogin) async {
    final currentlyEnabled = await _controller.isEnabled();
    if (shouldLaunchAtLogin && !currentlyEnabled) {
      await _controller.enable();
    } else if (!shouldLaunchAtLogin && currentlyEnabled) {
      await _controller.disable();
    }
  }
}
