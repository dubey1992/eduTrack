import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../../features/auth/presentation/teacher/teacher_change_password_screen.dart';
import '../../features/auth/presentation/teacher/teacher_forgot_password_screen.dart';
import '../../features/auth/presentation/teacher/teacher_sign_in_screen.dart';
import '../../features/auth/presentation/teacher/teacher_welcome_screen.dart';
import '../../features/auth/presentation/teacher_splash_screen.dart';
import '../widgets/teacher_mark.dart';
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

/// How long the opening screen is held: long enough for the book to open
/// and the name to settle, short enough that a teacher is never waiting on
/// an animation.
const teacherOpeningBeat = Duration(milliseconds: 1400);

/// Where a signed-out teacher may be. All four are the app's own phone
/// screens; none is the web portal's.
const teacherSignedOutPaths = {'/welcome', '/login', '/forgot-password'};

final teacherOpeningBeatProvider = FutureProvider<void>((ref) => Future<void>.delayed(teacherOpeningBeat));

final teacherRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const TeacherSplashScreen()),
      // Signed out: what the app is, then the sign-in. Phone screens of the
      // app's own, not the portal's two-panel page.
      GoRoute(path: '/welcome', builder: (context, state) => const TeacherWelcomeScreen()),
      GoRoute(path: '/login', builder: (context, state) => const TeacherSignInScreen()),
      GoRoute(path: '/forgot-password', builder: (context, state) => const TeacherForgotPasswordScreen()),
      // Held here, as on the portal, until a temporary password is replaced.
      GoRoute(path: '/change-password', builder: (context, state) => const TeacherChangePasswordScreen()),
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

      // Signed out, the welcome is home. Sign-in and the password reset are
      // reachable from it and stay reachable.
      if (user == null) {
        return teacherSignedOutPaths.contains(location) ? null : '/welcome';
      }

      if (!teacherRoles.contains(user.role)) {
        return location == '/not-teacher' ? null : '/not-teacher';
      }

      if (user.mustChangePassword) {
        return location == '/change-password' ? null : '/change-password';
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
              const TeacherMark(size: 72, tile: true),
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
