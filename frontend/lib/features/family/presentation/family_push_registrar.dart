import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../push/device_repository.dart';
import '../../push/push_messaging.dart';
import '../application/family_notifiers.dart';
import '../application/family_session_notifier.dart';

/// Push for the Family app: the staff app's PushRegistrar, on the family
/// session. Once a parent is signed in it asks permission, registers this
/// phone through `/family/devices`, and keeps it fresh; a tapped
/// notification opens the screen it is about (a fee reminder Fees, a bus
/// alert the Bus tab - docs/mobile-apps-review.md, 5.2), and one arriving with
/// the app open refreshes Notices and says so.
///
/// A build without the Firebase keys has no push and does nothing here; the
/// school's messages still arrive in Notices.
/// The Family app's addresses a notification may open. Anything else the
/// server sends - an older server, a typo - opens Notices.
const familyPushRoutes = {'/notices', '/fees', '/bus', '/bus/live', '/results', '/attendance'};

String safeFamilyPushRoute(String route) => familyPushRoutes.contains(route) ? route : '/notices';

class FamilyPushRegistrar extends ConsumerStatefulWidget {
  const FamilyPushRegistrar({super.key, required this.onOpen, required this.child});

  /// Opens one of [familyPushRoutes].
  final ValueChanged<String> onOpen;
  final Widget child;

  @override
  ConsumerState<FamilyPushRegistrar> createState() => _FamilyPushRegistrarState();
}

class _FamilyPushRegistrarState extends ConsumerState<FamilyPushRegistrar> {
  static const _app = 'family';

  final List<StreamSubscription<Object>> _subscriptions = [];
  bool _listening = false;

  PushMessaging get _push => ref.read(pushMessagingProvider);

  @override
  void initState() {
    super.initState();
    ref.listenManual(familySessionProvider.select((session) => session.value?.id), (previous, next) {
      if (next != null && next != previous) unawaited(_signedIn());
      if (next == null && previous != null) unawaited(ref.read(pushRegistrationProvider).forget());
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
        ..add(_push.opened.listen((notice) => widget.onOpen(safeFamilyPushRoute(notice.route))))
        ..add(_push.received.listen(_show));
    }

    final launch = await _push.launchedBy();
    if (launch != null && mounted) widget.onOpen(safeFamilyPushRoute(launch.route));
  }

  Future<void> _register(String token) async {
    if (ref.read(familySessionProvider).value == null) return;
    try {
      await ref.read(pushRegistrationProvider).register(token, app: _app);
    } catch (error) {
      // Tried again at the next sign-in or token change; Notices still work.
      debugPrint('Could not register this phone for push: $error');
    }
  }

  void _show(PushNotice notice) {
    ref.invalidate(familyNoticesProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(notice.body.isEmpty ? notice.title : '${notice.title}: ${notice.body}', maxLines: 3),
          action: SnackBarAction(
            label: context.l10n.familyOpen,
            onPressed: () => widget.onOpen(safeFamilyPushRoute(notice.route)),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
