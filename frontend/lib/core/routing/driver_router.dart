import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../../features/auth/presentation/attendant_login_screen.dart';
import '../../features/auth/presentation/driver_landing_screen.dart';
import '../../features/auth/presentation/driver_splash_screen.dart';
import '../../features/errors/presentation/maintenance_screen.dart';
import '../../features/my_trip/presentation/battery_help_screen.dart';
import '../../features/my_trip/presentation/my_trip_screen.dart';
import '../../features/my_trip/presentation/navigate_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../network/maintenance_notifier.dart';
import '../widgets/crew_frame.dart';

/// The router the Android app runs on (docs/driver-app.md).
///
/// **One codebase, two products.** The school's web app is an office: a
/// sidebar of twenty modules, a marketing homepage in front of it, screens
/// for payroll and admissions. The app on the bus is a phone in a cradle,
/// and the person holding it has one job for the next forty minutes.
///
/// So the driver build does not merely *hide* the rest - it does not carry
/// it. There is no '/' here, no shell, no dashboard. An address that is not
/// one of these is not a page of this app, and a build that opened on
/// the marketing homepage was the bug that prompted this
/// ([main_driver.dart]).
///
/// What the crew can reach is still decided by the server, as it always
/// was. This only decides what the phone has screens for.
/// How long the opening screen is held, whatever the session does.
///
/// Restoring a session off the phone takes a few milliseconds, so without
/// this the splash is skipped in a single frame and the crew goes from the
/// Android launch icon straight to the landing - which is what happened the
/// first time this was built. A beat is the difference between an app that
/// opens and one that just appears.
///
/// **One full pass of the animation**, not a round number: the shuttle
/// loop is 36 frames at 70ms, so 2.52s is the bus arriving, the children
/// boarding and the bus pulling away. Cut it shorter and the crew sees a
/// fragment - a bus that never reaches the stop - which reads as the app
/// stuttering rather than as a scene. The extra 80ms covers the first
/// frame landing a moment after the route does.
/// Every address a signed-in crew member may be at.
///
/// A list rather than two comparisons, because the two comparisons were a
/// bug: the redirect sent *everything else* back to the trip, so Battery
/// help and Navigate were pushed and bounced straight off again. Both had
/// passing tests - of the screens, and of the buttons that open them -
/// because neither test went through this router (docs/driver-app.md).
///
/// Anything added to the router below belongs here too, or it is
/// unreachable on a phone however well it works on its own.
const crewPaths = {'/my-trip', '/profile', '/battery', '/navigate'};

const openingBeat = Duration(milliseconds: 2600);

/// Completes when that beat is over. Read by the redirect, so the router
/// re-runs the moment it finishes.
final openingBeatProvider = FutureProvider<void>((ref) => Future<void>.delayed(openingBeat));

final driverRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const DriverSplashScreen()),
      // What the app is, before anybody signs in. The sign-in screen is a
      // mobile number and four digits with no room to explain itself, and
      // the crew meets it in a yard rather than at a desk.
      GoRoute(path: '/start', builder: (context, state) => const DriverLandingScreen()),
      // Without the "sign in with email instead" way out: this build has
      // no email sign-in to offer, so the link would go nowhere.
      GoRoute(path: '/sign-in', builder: (context, state) => const AttendantLoginScreen(offersEmailSignIn: false)),
      GoRoute(
        path: '/my-trip',
        builder: (context, state) => const CrewFrame(place: CrewPlace.trip, child: MyTripScreen()),
      ),
      // The one screen besides the trip: their own details, which every
      // employee may edit wherever they work (docs/profile.md).
      GoRoute(
        path: '/profile',
        builder: (context, state) => const CrewFrame(place: CrewPlace.profile, child: ProfileScreen()),
      ),
      // Reached from the duty screen's warning and from Profile. Its own
      // page rather than a dialog: it is a list of steps somebody follows
      // with the phone in the other hand (docs/driver-app.md, D4.4).
      GoRoute(path: '/battery', builder: (context, state) => const BatteryHelpScreen()),
      // Guidance to one stop, carried in `extra` rather than the path: it
      // is three numbers and a name, not a resource anybody deep-links to
      // (docs/driver-app.md, D7).
      GoRoute(
        path: '/navigate',
        builder: (context, state) {
          final destination = state.extra;

          // Nothing reaches this without a stop, but a crash on a bus is
          // not the way to find out otherwise.
          if (destination is! NavigateTo) return const CrewFrame(place: CrewPlace.trip, child: MyTripScreen());

          return NavigateScreen(destination: destination);
        },
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

      // Held for the session *and* the beat: whichever finishes last.
      if (auth.isLoading || ref.read(openingBeatProvider).isLoading) {
        return location == '/splash' ? null : '/splash';
      }

      final user = auth.value;

      // Signed out, the landing is home. Sign-in is reachable from it and
      // stays reachable, so somebody who has read it once is not made to
      // read it again on the way back.
      if (user == null) {
        return location == '/start' || location == '/sign-in' ? null : '/start';
      }

      if (!user.role.isCrew) {
        return location == '/not-crew' ? null : '/not-crew';
      }

      // Signed in, and crew: the trip, their own profile, and the two
      // screens reached from them.
      return crewPaths.contains(location) ? null : '/my-trip';
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
      _ref.listen(openingBeatProvider, (_, _) => notifyListeners()),
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
