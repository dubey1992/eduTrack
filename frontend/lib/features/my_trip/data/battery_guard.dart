import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'battery_guard_io.dart' if (dart.library.js_interop) 'battery_guard_web.dart' as platform;

/// Whether this phone will let a trip keep reporting with the screen off.
///
/// Android's own battery saver is one question, and the plugin can ask it.
/// The harder one is the layer Xiaomi, Oppo and Vivo add on top, which kills
/// foreground services their own way and cannot be asked from code at all -
/// that part is a help screen and a person tapping through Settings
/// (docs/driver-app.md, D4.4).
abstract class BatteryGuard {
  /// False when Android is free to stop this app in the background.
  Future<bool> isExempt();

  /// Shows the system's own "allow this app to run in the background?"
  /// dialog. True when the phone is exempt afterwards.
  Future<bool> askForExemption();
}

final batteryGuardProvider = Provider<BatteryGuard>((ref) => platform.createBatteryGuard());

/// Whether this phone needs the driver's attention.
///
/// autoDispose, and deliberately: this is a fact about the phone rather
/// than about whoever is signed in, and the only thing that changes it is
/// somebody walking through Settings. Asking again each time the screen is
/// opened is both cheaper than caching it for a session and more correct
/// than carrying a stale "all fine" back from before they did.
final phoneMayStopSharingProvider = FutureProvider.autoDispose<bool>((ref) async {
  return !await ref.read(batteryGuardProvider).isExempt();
});
