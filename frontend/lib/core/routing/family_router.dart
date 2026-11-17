import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/errors/presentation/maintenance_screen.dart';
import '../../features/family/application/family_session_notifier.dart';
import '../../features/family/presentation/family_attendance_screen.dart';
import '../../features/family/presentation/family_absence_note_screens.dart';
import '../../features/family/presentation/family_bus_screen.dart';
import '../../features/family/presentation/family_talk_screens.dart';
import '../../features/family/presentation/family_fees_screen.dart';
import '../../features/family/presentation/family_frame.dart';
import '../../features/family/presentation/family_home_screen.dart';
import '../../features/family/presentation/family_learning_screens.dart';
import '../../features/family/presentation/family_more_screens.dart';
import '../../features/family/presentation/family_sign_in_screen.dart';
import '../network/maintenance_notifier.dart';

/// The router the Family app runs on (docs/parent-student-app.md).
///
/// Built the way the teacher's and the driver's are: this build carries only
/// the parent's screens. What a parent may see is the server's decision -
/// their own children, at their own school - this only decides which
/// screens the phone has.
///
/// Every address a signed-in parent may be at, kept as one list beside the
/// routes, for the reason the teacher router gives: a redirect written as
/// "anything else goes home" bounces screens pushed over the tabs.
const familyPaths = {
  '/home',
  '/attendance',
  '/bus',
  '/bus/live',
  '/absence-notes',
  '/absence-notes/new',
  '/call-requests',
  '/fees',
  '/more',
  '/notices',
  '/calendar',
  '/notifications',
  '/results',
  '/timetable',
  '/syllabus',
};

final familyRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionRefresh(ref);
  ref.onDispose(refresh.dispose);

  GoRoute tab(FamilyPlace place, Widget screen, {bool showsChild = true}) => GoRoute(
    path: place.path,
    pageBuilder: (context, state) => NoTransitionPage(
      child: FamilyFrame(place: place, showsChild: showsChild, child: screen),
    ),
  );

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const FamilySplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const FamilySignInScreen()),
      tab(FamilyPlace.home, const FamilyHomeScreen()),
      tab(FamilyPlace.attendance, const FamilyAttendanceScreen()),
      tab(FamilyPlace.bus, const FamilyBusScreen()),
      tab(FamilyPlace.fees, const FamilyFeesScreen()),
      tab(FamilyPlace.more, const FamilyMoreScreen(), showsChild: false),
      // Over the tabs, with a back arrow.
      GoRoute(path: '/notices', builder: (context, state) => const FamilyNoticesScreen()),
      GoRoute(path: '/calendar', builder: (context, state) => const FamilyCalendarScreen()),
      GoRoute(path: '/notifications', builder: (context, state) => const FamilyNotificationsScreen()),
      GoRoute(path: '/bus/live', builder: (context, state) => const FamilyBusLiveScreen()),
      GoRoute(path: '/absence-notes', builder: (context, state) => const FamilyAbsenceNotesScreen()),
      GoRoute(path: '/absence-notes/new', builder: (context, state) => const FamilyNewAbsenceNoteScreen()),
      GoRoute(path: '/call-requests', builder: (context, state) => const FamilyCallRequestScreen()),
      GoRoute(path: '/results', builder: (context, state) => const FamilyResultsScreen()),
      GoRoute(path: '/timetable', builder: (context, state) => const FamilyTimetableScreen()),
      GoRoute(path: '/syllabus', builder: (context, state) => const FamilySyllabusScreen()),
      GoRoute(path: '/maintenance', builder: (context, state) => const MaintenanceScreen()),
    ],
    redirect: (context, state) {
      final location = state.matchedLocation;

      if (ref.read(maintenanceProvider)) {
        return location == '/maintenance' ? null : '/maintenance';
      }

      final session = ref.read(familySessionProvider);
      if (session.isLoading && !session.hasValue) {
        return location == '/splash' ? null : '/splash';
      }

      if (session.value == null) {
        return location == '/login' ? null : '/login';
      }

      return familyPaths.contains(location) ? null : '/home';
    },
  );
});

/// Rebuilds the router when the session or the maintenance flag changes.
class _SessionRefresh extends ChangeNotifier {
  _SessionRefresh(this._ref) {
    _subscriptions = [
      _ref.listen(familySessionProvider, (_, _) => notifyListeners()),
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
