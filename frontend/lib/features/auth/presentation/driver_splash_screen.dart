import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_notifier.dart';

/// The first thing the bus crew sees, while the app works out whether they
/// are still signed in.
///
/// The web app's splash is a spinner, which is right for a screen nobody
/// looks at for more than a frame. This one is looked at: it opens on a
/// phone in a yard, sometimes on a network that is barely there, and a bare
/// spinner leaves the crew unable to tell a slow morning from a broken app.
/// So it says what it is doing, and after [_patience] it offers the only
/// useful thing - try again - rather than spinning forever.
class DriverSplashScreen extends ConsumerStatefulWidget {
  const DriverSplashScreen({super.key});

  @override
  ConsumerState<DriverSplashScreen> createState() => _DriverSplashScreenState();
}

class _DriverSplashScreenState extends ConsumerState<DriverSplashScreen> {
  /// How long a phone may sit here before the wait is worth questioning.
  /// Long enough that an ordinary cold start never shows the button.
  static const _patience = Duration(seconds: 6);

  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_patience, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tryAgain() {
    setState(() => _slow = false);
    _timer?.cancel();
    _timer = Timer(_patience, () {
      if (mounted) setState(() => _slow = true);
    });
    ref.invalidate(authNotifierProvider);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    // Marked decorative: it carries no information a screen
                    // reader would miss, and the line below says the same
                    // thing in words.
                    child: Image.asset(
                      'assets/driver/shuttle-run.gif',
                      key: const Key('splash-animation'),
                      excludeFromSemantics: true,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'School365ai Driver',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _slow ? 'Still trying to reach your school.' : 'Getting your trips ready…',
                  key: const Key('splash-status'),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_slow)
                  FilledButton.icon(
                    key: const Key('splash-try-again'),
                    onPressed: _tryAgain,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  )
                else
                  const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
                if (_slow) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Check that this phone has signal, then try again.',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
