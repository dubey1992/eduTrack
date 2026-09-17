import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/academic_years/presentation/academic_year_list_screen.dart';
import '../../features/attendance/presentation/attendance_screen.dart';
import '../../features/auth/application/auth_notifier.dart';
import '../../features/announcements/presentation/announcement_screen.dart';
import '../../features/auth/presentation/change_password_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/classes/presentation/class_list_screen.dart';
import '../../features/communication/presentation/communication_screen.dart';
import '../../features/communication/presentation/inbox_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/early_access/presentation/early_access_screen.dart';
import '../../features/errors/presentation/maintenance_screen.dart';
import '../../features/errors/presentation/not_found_screen.dart';
import '../../features/departments/presentation/department_list_screen.dart';
import '../../features/hod/presentation/hod_report_screen.dart';
import '../../features/holidays/presentation/holiday_list_screen.dart';
import '../../features/marketing/presentation/marketing_screen.dart';
import '../../features/payments/presentation/payment_list_screen.dart';
import '../../features/payroll/presentation/my_payslips_screen.dart';
import '../../features/payroll/presentation/payroll_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/schools/presentation/school_list_screen.dart';
import '../../features/staff/presentation/staff_list_screen.dart';
import '../../features/staff_attendance/presentation/staff_attendance_screen.dart';
import '../../features/staff_leave/presentation/staff_leave_screen.dart';
import '../../features/students/presentation/student_list_screen.dart';
import '../../features/subjects/presentation/subject_list_screen.dart';
import '../../features/syllabus/presentation/syllabus_screen.dart';
import '../../features/teaching_reports/presentation/teaching_report_screen.dart';
import '../../features/timetable/presentation/timetable_screen.dart';
import '../../features/transport/presentation/driver_list_screen.dart';
import '../../features/transport/presentation/route_list_screen.dart';
import '../../features/transport/presentation/trip_screen.dart';
import '../../features/transport/presentation/vehicle_list_screen.dart';
import '../../features/users/presentation/user_list_screen.dart';
import '../network/maintenance_notifier.dart';
import '../widgets/app_shell.dart';
import '../widgets/splash_screen.dart';
import 'app_nav.dart';

/// Routes reachable without an active session - rendered full-screen,
/// outside the sidebar shell. '/' is the public marketing homepage (see
/// MarketingScreen); the authenticated landing screen lives at /dashboard.
const _publicPaths = {'/', '/login', '/forgot-password', '/reset-password'};

/// Every path this router actually serves.
///
/// Used to tell "you need to sign in" apart from "there is no such page": an
/// address that is not in here is a 404 and goes to [NotFoundScreen],
/// whoever is asking.
///
/// A route added below and forgotten here would quietly 404, so
/// app_router_test.dart walks the router's own configuration and fails if
/// the two ever disagree.
const appRoutePaths = {
  '/',
  '/splash',
  '/login',
  '/forgot-password',
  '/reset-password',
  '/change-password',
  '/maintenance',
  '/dashboard',
  '/users',
  '/schools',
  '/early-access',
  '/payments',
  '/academic-years',
  '/holidays',
  '/departments',
  '/subjects',
  '/classes',
  '/timetable',
  '/staff',
  '/students',
  '/attendance',
  '/staff-attendance',
  '/leaves',
  '/teaching-reports',
  '/syllabus',
  '/hod-reports',
  '/transport/vehicles',
  '/transport/drivers',
  '/transport/routes',
  '/transport/trips',
  '/communication',
  '/announcements',
  '/inbox',
  '/reports',
  '/payroll',
  '/my-payslips',
};

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
      // Outside the shell on purpose: an account still holding a temporary
      // password has no business reaching the sidebar behind it.
      GoRoute(path: '/change-password', builder: (context, state) => const ChangePasswordScreen()),
      // Where the whole app waits out a maintenance window. Reachable signed
      // in or out - the API being down does not care which.
      GoRoute(path: '/maintenance', builder: (context, state) => const MaintenanceScreen()),
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
          GoRoute(path: '/early-access', builder: (context, state) => const EarlyAccessScreen()),
          GoRoute(path: '/payments', builder: (context, state) => const PaymentListScreen()),
          GoRoute(path: '/academic-years', builder: (context, state) => const AcademicYearListScreen()),
          GoRoute(path: '/holidays', builder: (context, state) => const HolidayListScreen()),
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
          GoRoute(path: '/hod-reports', builder: (context, state) => const HodReportScreen()),
          GoRoute(path: '/transport/vehicles', builder: (context, state) => const VehicleListScreen()),
          GoRoute(path: '/transport/drivers', builder: (context, state) => const DriverListScreen()),
          GoRoute(path: '/transport/routes', builder: (context, state) => const RouteListScreen()),
          GoRoute(path: '/transport/trips', builder: (context, state) => const TripScreen()),
          GoRoute(path: '/communication', builder: (context, state) => const CommunicationScreen()),
          GoRoute(path: '/announcements', builder: (context, state) => const AnnouncementScreen()),
          GoRoute(path: '/inbox', builder: (context, state) => const InboxScreen()),
          GoRoute(path: '/reports', builder: (context, state) => const ReportsScreen()),
          GoRoute(path: '/payroll', builder: (context, state) => const PayrollScreen()),
          GoRoute(path: '/my-payslips', builder: (context, state) => const MyPayslipsScreen()),
        ],
      ),
    ],
    // Anything that matches no route at all. Reached by a stale bookmark or a
    // hand-edited address; the redirect below deliberately lets an unknown
    // path through so it lands here rather than being bounced to /login.
    errorBuilder: (context, state) => NotFoundScreen(location: state.uri.toString()),
    redirect: (context, state) {
      final authState = ref.read(authNotifierProvider);
      final location = state.matchedLocation;

      // A maintenance window is every screen at once, so it outranks every
      // other rule here - including the session, which cannot be restored
      // while the API is down anyway.
      if (ref.read(maintenanceProvider)) {
        return location == '/maintenance' ? null : '/maintenance';
      }

      // And once it is over, nobody should be left sitting on that page.
      if (location == '/maintenance') {
        return authState.value != null ? '/dashboard' : '/';
      }

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
        // An address that is not a route at all is a 404, not a locked door:
        // bouncing it to /login would tell somebody who mistyped a path that
        // they need an account, which is both wrong and confusing. Let it
        // fall through to errorBuilder.
        if (!appRoutePaths.contains(location)) return null;

        return _publicPaths.contains(location) ? null : '/login';
      }

      // An account created by a bulk import was handed a generated password
      // that whoever ran the import has seen. Nothing else opens until it
      // has been replaced.
      if (user.mustChangePassword && location != '/change-password') {
        return '/change-password';
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

/// Bridges Riverpod changes to go_router's [Listenable]-based refresh
/// mechanism, so navigation redirects re-run whenever the session state
/// changes (login, logout, restore) or the API goes into - or comes out of -
/// a maintenance window.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    _subscriptions = [
      ref.listen<AsyncValue<Object?>>(authNotifierProvider, (previous, next) => notifyListeners()),
      ref.listen<bool>(maintenanceProvider, (previous, next) => notifyListeners()),
    ];
  }

  late final List<ProviderSubscription<Object?>> _subscriptions;

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    super.dispose();
  }
}
