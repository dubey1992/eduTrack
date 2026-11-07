import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../push/device_repository.dart';
import '../../push/push_messaging.dart';
import '../application/family_notifiers.dart';
import '../application/family_session_notifier.dart';

/// Push for the Family app: the staff app's PushRegistrar, on the family
/// session. Once a parent is signed in it asks permission, registers this
/// phone through `/family/devices`, and keeps it fresh; a tapped
/// notification opens Notices, and one arriving with the app open refreshes
/// them and says so.
///
/// A build without the Firebase keys has no push and does nothing here; the
/// school's messages still arrive in Notices.
class FamilyPushRegistrar extends ConsumerStatefulWidget {
  const FamilyPushRegistrar({super.key, required this.onOpenNotices, required this.child});

  final VoidCallback onOpenNotices;
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
        ..add(_push.opened.listen((_) => widget.onOpenNotices()))
        ..add(_push.received.listen(_show));
    }

    final launch = await _push.launchedBy();
    if (launch != null && mounted) widget.onOpenNotices();
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
          action: SnackBarAction(label: 'Open', onPressed: widget.onOpenNotices),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
