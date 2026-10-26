import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/application/auth_notifier.dart';
import '../my_inbox/application/my_inbox_notifier.dart';
import 'device_repository.dart';
import 'push_messaging.dart';

/// Where a notification may take somebody. Anything else opens the inbox:
/// an address arriving from outside the app is not followed blindly.
const pushRoutes = {'/inbox', '/leave', '/teaching', '/today'};

String safePushRoute(String route) => pushRoutes.contains(route) ? route : '/inbox';

/// Push for the School365ai app (docs/teacher-app.md, T6). Wraps the app
/// once, above the router, like [RegisterSender]:
///
/// - when somebody is signed in, asks permission, registers this phone and
///   keeps the registration fresh when Firebase rotates the token;
/// - a notification tapped - with the app in the background or closed -
///   opens what it is about;
/// - one arriving with the app open refreshes the bell and says so on screen.
///
/// The phone is taken back at sign-out by [AuthNotifier.logout].
class PushRegistrar extends ConsumerStatefulWidget {
  const PushRegistrar({super.key, required this.app, required this.onOpen, required this.child});

  /// Which app this is, for the server: `staff` or `driver`.
  final String app;

  /// Goes to one of [pushRoutes].
  final ValueChanged<String> onOpen;
  final Widget child;

  @override
  ConsumerState<PushRegistrar> createState() => _PushRegistrarState();
}

class _PushRegistrarState extends ConsumerState<PushRegistrar> {
  final List<StreamSubscription<Object>> _subscriptions = [];
  bool _listening = false;

  PushMessaging get _push => ref.read(pushMessagingProvider);

  @override
  void initState() {
    super.initState();
    ref.listenManual(authNotifierProvider.select((auth) => auth.value?.id), (previous, next) {
      if (next != null && next != previous) unawaited(_signedIn());
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  Future<void> _signedIn() async {
    if (!await _push.start() || !mounted) return;

    final token = await _push.token();
    if (token != null) await _register(token);

    if (!_listening && mounted) {
      _listening = true;
      _subscriptions
        ..add(_push.tokenRefreshes.listen(_register))
        ..add(_push.opened.listen((notice) => widget.onOpen(safePushRoute(notice.route))))
        ..add(_push.received.listen(_show));
    }

    // Opened from closed by a tap: go there once signed in.
    final launch = await _push.launchedBy();
    if (launch != null && mounted) widget.onOpen(safePushRoute(launch.route));
  }

  Future<void> _register(String token) async {
    if (ref.read(authNotifierProvider).value == null) return;
    try {
      await ref.read(pushRegistrationProvider).register(token, app: widget.app);
    } catch (error) {
      // Tried again at the next sign-in or token change; the inbox still works.
      debugPrint('Could not register this phone for push: $error');
    }
  }

  void _show(PushNotice notice) {
    ref.invalidate(myUnreadCountProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(notice.body.isEmpty ? notice.title : '${notice.title}: ${notice.body}', maxLines: 3),
          action: SnackBarAction(label: 'Open', onPressed: () => widget.onOpen(safePushRoute(notice.route))),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
