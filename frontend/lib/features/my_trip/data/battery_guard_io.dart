import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'battery_guard.dart';

BatteryGuard createBatteryGuard() => const AndroidBatteryGuard();

class AndroidBatteryGuard implements BatteryGuard {
  const AndroidBatteryGuard();

  @override
  Future<bool> isExempt() => FlutterForegroundTask.isIgnoringBatteryOptimizations;

  @override
  Future<bool> askForExemption() async {
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();

    // The call answers whether the dialog opened, not what was chosen, so
    // the phone itself is asked again afterwards.
    return FlutterForegroundTask.isIgnoringBatteryOptimizations;
  }
}
