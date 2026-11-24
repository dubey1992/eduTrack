import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
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
    final l10n = context.l10n;

    return StatusPage(
      badge: l10n.staffMaintenanceBadge,
      headline: l10n.staffMaintenanceHeadline,
      body: l10n.staffMaintenanceBody,
      actions: [
        FilledButton(
          onPressed: _isChecking ? null : () => _recheck(isSignedIn: isSignedIn),
          child: _isChecking
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.staffTryAgain),
        ),
      ],
      detail: Text(_checkedAndStillDown ? l10n.staffMaintenanceStillDown : l10n.staffMaintenanceBackShortly),
    );
  }
}
