import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps what [child] shows out of screenshots, screen recordings and the
/// recent-apps view on Android while it is on screen (docs/security.md, "The
/// phone apps"): payslips, and the screens where a passcode or setup code is
/// typed. Nothing else - staff use screenshots to ask for help, and blocking
/// them everywhere would block that too.
///
/// Counted, so a secure screen opened on top of another keeps protection on
/// until the last one closes. A no-op on the web and anywhere but Android.
class SecureScreen extends StatefulWidget {
  const SecureScreen({super.key, required this.child});

  final Widget child;

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  @override
  void initState() {
    super.initState();
    SecureScreenGuard.instance.acquire();
  }

  @override
  void dispose() {
    SecureScreenGuard.instance.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The count of secure screens open, and the switch it drives.
class SecureScreenGuard {
  SecureScreenGuard._();

  static final instance = SecureScreenGuard._();

  static const _channel = MethodChannel('school365ai/secure_screen');

  int _open = 0;

  /// Whether protection is on - for tests.
  bool get isOn => _open > 0;

  void acquire() {
    _open++;
    if (_open == 1) _set(true);
  }

  void release() {
    if (_open == 0) return;
    _open--;
    if (_open == 0) _set(false);
  }

  void _set(bool secure) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    _channel.invokeMethod<void>('setSecure', secure).catchError((Object error) {
      // A phone that cannot do it still shows the screen; say so in the log.
      debugPrint('Could not ${secure ? 'protect' : 'unprotect'} the screen from screenshots: $error');
    });
  }
}
