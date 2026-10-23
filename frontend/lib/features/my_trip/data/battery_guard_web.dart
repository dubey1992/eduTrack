import 'battery_guard.dart';

BatteryGuard createBatteryGuard() => const BrowserBatteryGuard();

/// A browser tab is not put to sleep by a manufacturer's battery manager,
/// and has no setting to send anybody to. Nothing to warn about.
class BrowserBatteryGuard implements BatteryGuard {
  const BrowserBatteryGuard();

  @override
  Future<bool> isExempt() async => true;

  @override
  Future<bool> askForExemption() async => true;
}
