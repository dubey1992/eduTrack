import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/academic_years/presentation/academic_year_list_screen.dart';
import '../../features/attendance/presentation/attendance_screen.dart';
import '../../features/auth/application/auth_notifier.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/classes/presentation/class_list_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/departments/presentation/department_list_screen.dart';
import '../../features/marketing/presentation/marketing_screen.dart';
import '../../features/payments/presentation/payment_list_screen.dart';
import '../../features/schools/presentation/school_list_screen.dart';
import '../../features/staff/presentation/staff_list_screen.dart';
import '../../features/staff_attendance/presentation/staff_attendance_screen.dart';
import '../../features/students/presentation/student_list_screen.dart';
import '../../features/subjects/presentation/subject_list_screen.dart';
import '../../features/users/presentation/user_list_screen.dart';
import '../widgets/app_shell.dart';
import '../widgets/splash_screen.dart';
import 'app_nav.dart';

/// Routes reachable without an active session - rendered full-screen,
/// outside the sidebar shell. '/' is the public marketing homepage (see
/// MarketingScreen); the authenticated landing screen lives at /dashboard.
const _publicPaths = {'/', '/login', '/forgot-password', '/reset-password'};

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const MarketingScreen()),
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => ResetPasswordScreen(
          email: state.uri.queryParameters['email'] ?? '',
          token: state.uri.queryParameters['token'] ?? '',
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
          GoRoute(path: '/users', builder: (context, state) => const UserListScreen()),
          GoRoute(path: '/schools', builder: (context, state) => const SchoolListScreen()),
          GoRoute(path: '/payments', builder: (context, state) => const PaymentListScreen()),
          GoRoute(path: '/academic-years', builder: (context, state) => const AcademicYearListScreen()),
          GoRoute(path: '/departments', builder: (context, state) => const DepartmentListScreen()),
          GoRoute(path: '/subjects', builder: (context, state) => const SubjectListScreen()),
          GoRoute(path: '/classes', builder: (context, state) => const ClassListScreen()),
          GoRoute(path: '/staff', builder: (context, state) => const StaffListScreen()),
          GoRoute(path: '/students', builder: (context, state) => const StudentListScreen()),
          GoRoute(path: '/attendance', builder: (context, state) => const AttendanceScreen()),
          GoRoute(path: '/staff-attendance', builder: (context, state) => const StaffAttendanceScreen()),
        ],
      ),
    ],
    redirect: (context, state) {
      final authState = ref.read(authNotifierProvider);
      final location = state.matchedLocation;

      if (authState.isLoading) {
        // A public destination renders the same regardless of how the
        // still-resolving session turns out, so there's no wrong content to
        // flash - only gate protected destinations behind the splash screen
        // while we find out. (Otherwise a fresh, logged-out visit to '/'
        // would bounce through the non-public '/splash' and land on
        // /login instead of ever showing the marketing homepage.)
        if (_publicPaths.contains(location) || location == '/splash') {
          return null;
        }
        return '/splash';
      }

      final user = authState.value;
      final isLoggedIn = user != null;

      if (!isLoggedIn) {
        return _publicPaths.contains(location) ? null : '/login';
      }

      // Once logged in, the marketing homepage/login/splash are all behind
      // them - send them to their actual landing screen instead.
      if (location == '/' || location == '/login' || location == '/splash') {
        return '/dashboard';
      }

      // Every shell route's access is driven by AppNav - the same config
      // that builds the sidebar - so the menu and the guard can never
      // drift apart. A route not listed there needs no role check.
      final navItem = AppNav.findByPath(location);
      if (navItem != null && !navItem.allows(user.role)) {
        return '/dashboard';
      }

      return null;
    },
  );
});

/// Bridges Riverpod's [authNotifierProvider] changes to go_router's
/// [Listenable]-based refresh mechanism, so navigation redirects re-run
/// whenever the session state changes (login, logout, restore).
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    _subscription = ref.listen<AsyncValue<Object?>>(authNotifierProvider, (previous, next) => notifyListeners());
  }

  late final ProviderSubscription<AsyncValue<Object?>> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
