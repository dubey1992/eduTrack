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
import '../../features/staff_leave/presentation/staff_leave_screen.dart';
import '../../features/students/presentation/student_list_screen.dart';
import '../../features/subjects/presentation/subject_list_screen.dart';
import '../../features/syllabus/presentation/syllabus_screen.dart';
import '../../features/teaching_reports/presentation/teaching_report_screen.dart';
import '../../features/timetable/presentation/timetable_screen.dart';
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
    // Deliberately no `initialLocation` override - go_router derives the
    // first route from the actual browser URL on web (window.location),
    // which is what lets a hard reload on e.g. /timetable stay on
    // /timetable instead of always restarting at '/'. An explicit
    // `initialLocation` here would replace that with a hardcoded value on
    // every single launch, including reloads.
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
          GoRoute(path: '/timetable', builder: (context, state) => const TimetableScreen()),
          GoRoute(path: '/staff', builder: (context, state) => const StaffListScreen()),
          GoRoute(path: '/students', builder: (context, state) => const StudentListScreen()),
          GoRoute(path: '/attendance', builder: (context, state) => const AttendanceScreen()),
          GoRoute(path: '/staff-attendance', builder: (context, state) => const StaffAttendanceScreen()),
          GoRoute(path: '/leaves', builder: (context, state) => const StaffLeaveScreen()),
          GoRoute(path: '/teaching-reports', builder: (context, state) => const TeachingReportScreen()),
          GoRoute(path: '/syllabus', builder: (context, state) => const SyllabusScreen()),
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
        // Carry the originally-requested destination through the splash
        // gate as a query param, so a hard reload on e.g. /timetable lands
        // back on /timetable once the session resolves, instead of always
        // bouncing to /dashboard once the location has already become
        // '/splash' below.
        return Uri(path: '/splash', queryParameters: {'from': state.uri.toString()}).toString();
      }

      final user = authState.value;
      final isLoggedIn = user != null;

      if (!isLoggedIn) {
        return _publicPaths.contains(location) ? null : '/login';
      }

      // Once logged in, the marketing homepage/login/splash are all behind
      // them - send them to their actual landing screen instead, or back to
      // whatever destination the splash gate above was carrying, if any
      // (the role/permission check further down still applies to it, via
      // this same redirect running again for the new location).
      if (location == '/' || location == '/login' || location == '/splash') {
        final from = state.uri.queryParameters['from'];
        if (from != null && from.isNotEmpty && !_publicPaths.contains(from) && from != '/splash') {
          return from;
        }
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
