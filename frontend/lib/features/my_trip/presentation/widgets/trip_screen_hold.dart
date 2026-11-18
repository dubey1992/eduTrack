import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// While a trip runs and its sheet is on screen, the phone keeps its screen
/// on and stays upright (docs/mobile-apps-review.md, 6.2): a cradled phone
/// that dims mid-stop, or a sheet that turns sideways as the bus takes a
/// corner, costs the attendant the child they were about to tick.
///
/// Only while the app is in front - Android drops the keep-on flag by
/// itself when the screen is locked or the app put away, so the GPS test's
/// "lock the screen and pocket it" still works. A no-op off Android.
class TripScreenHold extends StatefulWidget {
  const TripScreenHold({super.key, required this.active, required this.child});

  /// Off once the trip has ended: a finished trip's sheet may sleep.
  final bool active;
  final Widget child;

  @override
  State<TripScreenHold> createState() => _TripScreenHoldState();
}

class _TripScreenHoldState extends State<TripScreenHold> {
  @override
  void initState() {
    super.initState();
    if (widget.active) TripScreenHoldSwitch.instance.set(true);
  }

  @override
  void didUpdateWidget(TripScreenHold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) TripScreenHoldSwitch.instance.set(widget.active);
  }

  @override
  void dispose() {
    if (widget.active) TripScreenHoldSwitch.instance.set(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The switch itself: the keep-on flag through the app's own channel
/// (MainActivity.kt), and the orientation through Flutter.
class TripScreenHoldSwitch {
  TripScreenHoldSwitch._();

  static final instance = TripScreenHoldSwitch._();

  static const _channel = MethodChannel('school365ai/keep_awake');

  bool _on = false;

  /// Whether the hold is on - for tests.
  bool get isOn => _on;

  void set(bool on) {
    _on = on;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    SystemChrome.setPreferredOrientations(on ? const [DeviceOrientation.portraitUp] : const [])
        .catchError((Object error) {
          debugPrint('Could not ${on ? 'lock' : 'unlock'} the screen orientation: $error');
        });
    _channel.invokeMethod<void>('setKeepAwake', on).catchError((Object error) {
      // A phone that cannot do it still runs the trip; say so in the log.
      debugPrint('Could not ${on ? 'keep the screen on' : 'let the screen sleep'}: $error');
    });
  }
}
