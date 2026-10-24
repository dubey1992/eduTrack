import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_notifier.dart';

/// The first thing a teacher sees, while the app finds out whether they
/// are still signed in (docs/teacher-app.md, T0).
///
/// The driver's splash is a scene - a bus arriving - because that app opens
/// in a yard on a bad network and has to look alive. This one opens in a
/// corridor on the school's Wi-Fi and should mostly be gone before it is
/// read. It still says what it is doing, and after [_patience] offers the
/// one useful thing rather than a spinner for ever.
class TeacherSplashScreen extends ConsumerStatefulWidget {
  const TeacherSplashScreen({super.key});

  @override
  ConsumerState<TeacherSplashScreen> createState() => _TeacherSplashScreenState();
}

class _TeacherSplashScreenState extends ConsumerState<TeacherSplashScreen> {
  static const _patience = Duration(seconds: 6);

  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  void _arm() {
    _timer?.cancel();
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
    _arm();
    ref.invalidate(authNotifierProvider);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(22)),
                  child: Icon(Icons.school_outlined, size: 52, color: scheme.onPrimary),
                ),
                const SizedBox(height: 24),
                Text(
                  'School365ai Teacher',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _slow ? 'Still trying to reach your school.' : 'Getting your day ready…',
                  key: const Key('splash-status'),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_slow) ...[
                  FilledButton.icon(
                    key: const Key('splash-try-again'),
                    onPressed: _tryAgain,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Check that this phone is online, then try again.',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ] else
                  const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
