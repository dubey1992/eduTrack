import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../../features/auth/presentation/attendant_login_screen.dart';
import '../../features/errors/presentation/maintenance_screen.dart';
import '../../features/my_trip/presentation/my_trip_screen.dart';
import '../models/user_role.dart';
import '../network/maintenance_notifier.dart';
import '../widgets/crew_frame.dart';
import '../widgets/splash_screen.dart';

/// The router the Android app runs on (docs/driver-app.md).
///
/// **One codebase, two products.** The school's web app is an office: a
/// sidebar of twenty modules, a marketing homepage in front of it, screens
/// for payroll and admissions. The app on the bus is a phone in a cradle,
/// and the person holding it has one job for the next forty minutes.
///
/// So the driver build does not merely *hide* the rest - it does not carry
/// it. There is no '/' here, no shell, no dashboard. An address that is not
/// one of these four is not a page of this app, and a build that opened on
/// the marketing homepage was the bug that prompted this
/// ([main_driver.dart]).
///
/// What the crew can reach is still decided by the server, as it always
/// was. This only decides what the phone has screens for.
final driverRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      // Without the "sign in with email instead" way out: this build has
      // no email sign-in to offer, so the link would go nowhere.
      GoRoute(path: '/sign-in', builder: (context, state) => const AttendantLoginScreen(offersEmailSignIn: false)),
      GoRoute(
        path: '/my-trip',
        builder: (context, state) => const CrewFrame(child: MyTripScreen()),
      ),
      GoRoute(path: '/maintenance', builder: (context, state) => const MaintenanceScreen()),
      // Somebody who is signed in but is not bus crew. Rare - this build
      // only offers the crew's sign-in - but a session restored from an
      // older install could be anybody, and dropping them on a blank screen
      // would look like a broken app rather than the wrong one.
      GoRoute(path: '/not-crew', builder: (context, state) => const _NotCrewScreen()),
    ],
    redirect: (context, state) {
      final location = state.matchedLocation;

      // The API being down outranks everything, including a session that
      // cannot be restored while it is.
      if (ref.read(maintenanceProvider)) {
        return location == '/maintenance' ? null : '/maintenance';
      }

      final auth = ref.read(authNotifierProvider);

      if (auth.isLoading) return location == '/splash' ? null : '/splash';

      final user = auth.value;

      if (user == null) return location == '/sign-in' ? null : '/sign-in';

      if (user.role != UserRole.busAttendant) {
        return location == '/not-crew' ? null : '/not-crew';
      }

      // Signed in, and crew. There is one screen.
      return location == '/my-trip' ? null : '/my-trip';
    },
  );
});

/// Rebuilds the router when the session changes, the same way the web
/// app's does.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this._ref) {
    _subscriptions = [
      _ref.listen(authNotifierProvider, (_, _) => notifyListeners()),
      _ref.listen(maintenanceProvider, (_, _) => notifyListeners()),
    ];
  }

  final Ref _ref;
  late final List<ProviderSubscription> _subscriptions;

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    super.dispose();
  }
}

/// Signed in, but not with a bus crew account.
class _NotCrewScreen extends ConsumerWidget {
  const _NotCrewScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.directions_bus_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                'This app is for the bus crew',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Your account signs in to the school on the web instead. '
                'Ask your school admin if you should be driving a route.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
