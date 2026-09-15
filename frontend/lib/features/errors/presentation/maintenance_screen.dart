import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/maintenance_notifier.dart';
import '../../../core/widgets/status_page.dart';
import '../../auth/application/auth_notifier.dart';

/// Where the app waits out a scheduled maintenance window.
///
/// The router holds everyone here while the API is answering 503, so this is
/// the only screen anybody can reach. The twin of
/// `backend/resources/views/errors/503.blade.php`, which says the same thing
/// to whoever never got as far as loading the app.
class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  bool _isChecking = false;
  bool _checkedAndStillDown = false;

  Future<void> _recheck({required bool isSignedIn}) async {
    if (_isChecking) return;

    setState(() {
      _isChecking = true;
      _checkedAndStillDown = false;
    });

    final isBack = await ref.read(maintenanceProvider.notifier).recheck();

    if (!mounted) return;

    if (isBack) {
      // Clearing the flag alone would leave them sitting here, since the
      // router only redirects *to* this screen. Send them on themselves.
      context.go(isSignedIn ? '/dashboard' : '/');
      return;
    }

    setState(() {
      _isChecking = false;
      _checkedAndStillDown = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read inside the callback: on this screen nothing else
    // touches the session, so a bare read would find it still resolving and
    // send a signed-in user back to the homepage.
    final isSignedIn = ref.watch(authNotifierProvider).value != null;

    return StatusPage(
      badge: 'Scheduled maintenance',
      headline: "We're making School365ai better.",
      body:
          'The platform is briefly offline while we finish some planned work. '
          'Nothing has been lost - attendance, records and messages are all exactly '
          'where you left them, and will be there when we are back.',
      actions: [
        FilledButton(
          onPressed: _isChecking ? null : () => _recheck(isSignedIn: isSignedIn),
          child: _isChecking
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Try again'),
        ),
      ],
      detail: Text(
        _checkedAndStillDown
            ? 'Still offline as of a moment ago. We expect to be back shortly - '
                  'if this is urgent, contact your school administrator.'
            : 'We expect to be back shortly. If this is urgent, contact your '
                  'school administrator.',
      ),
    );
  }
}
