import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/teacher_splash_screen.dart';
import '../../features/errors/presentation/maintenance_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/today/presentation/today_screen.dart';
import '../models/user_role.dart';
import '../network/maintenance_notifier.dart';
import '../widgets/teacher_frame.dart';

/// The router the teacher app runs on (docs/teacher-app.md).
///
/// Built the way the driver's was ([driverRouterProvider]): this build does
/// not hide the office, it does not carry it. No '/', no dashboard, no
/// sidebar. What a teacher may do is still the server's decision, through
/// the permission matrix and the policies; this only decides which screens
/// the phone has.
///
/// Every address a signed-in teacher may be at. Kept as one list beside the
/// routes for the reason the driver router keeps one: a redirect written as
/// "anything else goes home" bounced screens that were pushed from home,
/// and their tests passed because they never went through the router.
const teacherPaths = {'/today', '/profile'};

/// The roles this app is for. An HOD teaches too and gets a Department tab
/// in T7; until then they see the teacher's screens.
const teacherRoles = {UserRole.teacher, UserRole.hod};

/// How long the opening screen is held. Shorter than the driver's, whose
/// splash is a scene; this one is a mark and a line, and a beat is only so
/// the app opens rather than appears.
const teacherOpeningBeat = Duration(milliseconds: 900);

final teacherOpeningBeatProvider = FutureProvider<void>((ref) => Future<void>.delayed(teacherOpeningBeat));

final teacherRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const TeacherSplashScreen()),
      // The web's sign-in, which already folds to a phone: email, password,
      // remember me, forgot password. Without the "bus attendant? sign in
      // with your mobile" way out - this build has no passcode sign-in to
      // offer. Named '/login' because the forgot- and reset-password
      // screens send people back to that address.
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen(offersAttendantSignIn: false)),
      GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/today',
        builder: (context, state) => const TeacherFrame(place: TeacherPlace.today, child: TodayScreen()),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const TeacherFrame(place: TeacherPlace.profile, child: ProfileScreen()),
      ),
      GoRoute(path: '/maintenance', builder: (context, state) => const MaintenanceScreen()),
      // Signed in, but not as a teacher: an administrator trying the app, or
      // bus crew who installed the wrong one. Told so, with the way out.
      GoRoute(path: '/not-teacher', builder: (context, state) => const _NotTeacherScreen()),
    ],
    redirect: (context, state) {
      final location = state.matchedLocation;

      if (ref.read(maintenanceProvider)) {
        return location == '/maintenance' ? null : '/maintenance';
      }

      final auth = ref.read(authNotifierProvider);

      if (auth.isLoading || ref.read(teacherOpeningBeatProvider).isLoading) {
        return location == '/splash' ? null : '/splash';
      }

      final user = auth.value;

      // Signed out: the sign-in is home, and the password reset is the one
      // other place a signed-out person may be.
      if (user == null) {
        return location == '/login' || location == '/forgot-password' ? null : '/login';
      }

      if (!teacherRoles.contains(user.role)) {
        return location == '/not-teacher' ? null : '/not-teacher';
      }

      return teacherPaths.contains(location) ? null : '/today';
    },
  );
});

/// Rebuilds the router when the session, the maintenance flag or the
/// opening beat changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this._ref) {
    _subscriptions = [
      _ref.listen(authNotifierProvider, (_, _) => notifyListeners()),
      _ref.listen(maintenanceProvider, (_, _) => notifyListeners()),
      _ref.listen(teacherOpeningBeatProvider, (_, _) => notifyListeners()),
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

/// Signed in, but not with a teacher's account.
class _NotTeacherScreen extends ConsumerWidget {
  const _NotTeacherScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.school_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                'This app is for teachers',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Your account signs in to the school on the web instead, '
                'or to the Driver app if you work on a bus.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('not-teacher-sign-out'),
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
