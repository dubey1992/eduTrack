import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../storage/key_value_store.dart';

/// The app lock for the Staff and Family apps (docs/mobile-apps-review.md,
/// 4.4): payslips, fees and children's details behind the phone's own
/// fingerprint, face or screen PIN.
///
/// Off until the person turns it on - offered once after signing in, and a
/// switch in My Profile (Staff) or Your privacy (Family). When on, the app
/// locks when it starts and after [AppLockController.lockAfter] in the
/// background. It is the phone's choice, not the account's: signing out
/// forgets it, so the next person to sign in on this phone decides again.

/// The phone's own way of proving it is its owner. Behind an interface so
/// tests need no fingerprint.
abstract class DeviceUnlock {
  /// The phone has a fingerprint, face or screen lock set up.
  Future<bool> available();

  /// Shows the phone's prompt; true when the person passed it.
  Future<bool> unlock(String reason);
}

/// [DeviceUnlock] through `local_auth`. Biometrics when the phone has them,
/// the phone's PIN, pattern or password otherwise - never a second password
/// of the app's own.
class LocalAuthUnlock implements DeviceUnlock {
  LocalAuthUnlock([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> available() async {
    // The web app has no app lock: the browser and the computer's own sign
    // in are what guard it.
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException catch (error) {
      debugPrint('App lock: could not ask whether the phone has a screen lock: ${error.code}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> unlock(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } on LocalAuthException catch (error) {
      debugPrint('App lock: the phone did not unlock: ${error.code}');
      return false;
    } on PlatformException catch (error) {
      debugPrint('App lock: the phone did not unlock: ${error.code}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

final deviceUnlockProvider = Provider<DeviceUnlock>((ref) => LocalAuthUnlock());

/// Now, swappable so tests need not wait five minutes.
final appLockClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Whether this phone can have the lock at all - for the switch.
final appLockAvailableProvider = FutureProvider<bool>((ref) => ref.watch(deviceUnlockProvider).available());

@immutable
class AppLockState {
  const AppLockState({this.loaded = false, this.enabled = false, this.offered = false, this.locked = false});

  /// The saved choice has been read from the phone.
  final bool loaded;
  final bool enabled;

  /// The person has been asked once, whatever they answered.
  final bool offered;

  /// The lock screen is showing.
  final bool locked;

  AppLockState copyWith({bool? enabled, bool? offered, bool? locked}) => AppLockState(
    loaded: true,
    enabled: enabled ?? this.enabled,
    offered: offered ?? this.offered,
    locked: locked ?? this.locked,
  );
}

class AppLockController extends Notifier<AppLockState> {
  /// How long the app may sit in the background before it locks.
  static const lockAfter = Duration(minutes: 5);

  static const _enabledKey = 'app_lock.enabled';
  static const _offeredKey = 'app_lock.offered';

  DateTime? _leftAt;

  /// The phone's own prompt is up. Showing it can send the app to the
  /// background for a moment, which must not count as leaving it.
  bool _prompting = false;

  @override
  AppLockState build() {
    _load();
    return const AppLockState();
  }

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  /// Whether the person turned the lock on, read straight from the phone -
  /// for the home-screen widget's background job, which has no controller
  /// (M10). A switch that cannot be read counts as on: the widget then hides
  /// the details rather than risk showing them.
  static Future<bool> isEnabledIn(KeyValueStore store) async {
    try {
      return await store.read(_enabledKey) == 'yes';
    } on Exception catch (error) {
      debugPrint('App lock: could not read the switch for the widget: $error');
      return true;
    }
  }

  Future<void> _load() async {
    final enabled = await _read(_enabledKey);
    final offered = await _read(_offeredKey);
    // Locked from the start: a fresh start of the app is the longest time
    // away there is.
    state = AppLockState(loaded: true, enabled: enabled, offered: offered, locked: enabled);
  }

  Future<bool> _read(String key) async {
    try {
      return await _store.read(key) == 'yes';
    } on Exception catch (error) {
      debugPrint('App lock: could not read $key from the phone: $error');
      return false;
    }
  }

  Future<void> _write(String key, bool value) async {
    try {
      value ? await _store.write(key, 'yes') : await _store.delete(key);
    } on Exception catch (error) {
      debugPrint('App lock: could not save $key on the phone: $error');
    }
  }

  /// Turns the lock on once the phone has shown it is its owner. Returns
  /// why not, or null when it is on.
  Future<String?> turnOn() async {
    final device = ref.read(deviceUnlockProvider);
    if (!await device.available()) {
      return 'Set up a fingerprint, face or screen lock on this phone first, then turn this on.';
    }
    if (!await _prompt('Confirm it is you to lock School365ai')) {
      return 'The app lock was not turned on.';
    }

    await _write(_enabledKey, true);
    await _write(_offeredKey, true);
    state = state.copyWith(enabled: true, offered: true, locked: false);
    return null;
  }

  Future<void> turnOff() async {
    await _write(_enabledKey, false);
    state = state.copyWith(enabled: false, locked: false);
  }

  /// "Not now" on the offer: asked once, never again on this phone.
  Future<void> decline() async {
    await _write(_offeredKey, true);
    state = state.copyWith(offered: true);
  }

  void wentToBackground() {
    if (_prompting) return;
    _leftAt = ref.read(appLockClockProvider)();
  }

  void cameBack() {
    final leftAt = _leftAt;
    _leftAt = null;
    if (_prompting || !state.enabled || leftAt == null) return;

    if (ref.read(appLockClockProvider)().difference(leftAt) >= lockAfter) {
      state = state.copyWith(locked: true);
    }
  }

  /// The lock screen's Unlock. A phone whose screen lock has since been
  /// removed cannot prove anything, so the lock switches itself off rather
  /// than shutting its owner out.
  Future<bool> unlock() async {
    if (!await ref.read(deviceUnlockProvider).available()) {
      await turnOff();
      return true;
    }

    final passed = await _prompt('Unlock School365ai');
    if (passed) state = state.copyWith(locked: false);
    return passed;
  }

  /// Signed out: the next person on this phone chooses for themselves.
  Future<void> forget() async {
    await _write(_enabledKey, false);
    await _write(_offeredKey, false);
    _leftAt = null;
    state = const AppLockState(loaded: true);
  }

  Future<bool> _prompt(String reason) async {
    _prompting = true;
    try {
      return await ref.read(deviceUnlockProvider).unlock(reason);
    } finally {
      _prompting = false;
    }
  }
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(AppLockController.new);
