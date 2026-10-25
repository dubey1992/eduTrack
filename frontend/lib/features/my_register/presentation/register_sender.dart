import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_notifier.dart';
import '../application/register_queue.dart';

/// Sends registers saved on the phone without waiting for anybody to open
/// the register again (docs/teacher-app.md, T2): when somebody signs in,
/// and whenever the app comes back to the front - the moment signal has
/// most often returned.
///
/// Wraps the teacher app once, above the router, so it outlives every
/// screen.
class RegisterSender extends ConsumerStatefulWidget {
  const RegisterSender({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RegisterSender> createState() => _RegisterSenderState();
}

class _RegisterSenderState extends ConsumerState<RegisterSender> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _send);
    // Signing in - or the app opening already signed in - sends what this
    // person left waiting. Another person's registers stay put.
    ref.listenManual(authNotifierProvider.select((auth) => auth.value?.id), (previous, next) {
      if (next != null && next != previous) _send();
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _send() {
    if (ref.read(authNotifierProvider).value == null) return;
    ref.read(registerQueueProvider.notifier).retryNow();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
