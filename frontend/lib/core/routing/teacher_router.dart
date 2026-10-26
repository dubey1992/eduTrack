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
import '../../features/my_inbox/presentation/my_inbox_screen.dart';
import '../../features/my_leave/presentation/apply_leave_screen.dart';
import '../../features/my_pay/presentation/my_payslip_detail_screen.dart';
import '../../features/my_pay/presentation/my_payslips_phone_screen.dart';
import '../../features/my_register/presentation/register_screen.dart';
import '../../features/my_teaching/presentation/file_report_screen.dart';
import '../../features/my_teaching/presentation/report_detail_screen.dart';
import '../../features/my_teaching/presentation/syllabus_class_screen.dart';
import '../../features/my_teaching/presentation/teaching_screen.dart';
import '../../features/syllabus/application/syllabus_checklist_notifier.dart';
import '../../features/my_leave/presentation/my_leave_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/today/presentation/staff_home_screen.dart';
import '../../features/today/presentation/today_screen.dart';
import '../models/user_role.dart';
import '../network/maintenance_notifier.dart';
import '../utils/date_format.dart';
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
const teacherPaths = {
  '/today',
  '/teaching',
  '/teaching/report',
  '/leave',
  '/leave/apply',
  '/pay',
  '/inbox',
  '/profile',
};

/// A payslip's own screen, `/pay/<id>`.
final _payslipPath = RegExp(r'^/pay/\d+$');

/// A class register, `/register/<class section id>?date=yyyy-MM-dd&label=...`.
final _registerPath = RegExp(r'^/register/\d+$');

/// A filed report, `/teaching/reports/<id>`, and one class's syllabus,
/// `/teaching/syllabus/<class section id>/<subject id>?label=...`.
final _teachingPaths = [RegExp(r'^/teaching/reports/\d+$'), RegExp(r'^/teaching/syllabus/\d+/\d+$')];

/// Those who teach a timetable: their home is Today, with periods and
/// registers. An HOD teaches too, and gets a Department tab in T7.
const teacherRoles = {UserRole.teacher, UserRole.hod};

/// Everybody this app is for: the teachers above and the rest of the
/// school's own staff, whose home is check-in (docs/staff-check-in.md).
/// Not the bus crew - their app is the Driver app - and not a Super Admin
/// or a Group Admin, who answer for many schools from the website.
const appRoles = {
  ...teacherRoles,
  UserRole.staff,
  UserRole.accountant,
  UserRole.transportManager,
  UserRole.schoolAdmin,
};

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
        // One address, two homes: a teacher's day is periods and registers;
        // everybody else's, here, is arriving and leaving.
        builder: (context, state) => TeacherFrame(
          place: TeacherPlace.today,
          child: teacherRoles.contains(ref.read(authNotifierProvider).value?.role)
              ? const TodayScreen()
              : const StaffHomeScreen(),
        ),
      ),
      GoRoute(
        path: '/teaching',
        builder: (context, state) => const TeacherFrame(place: TeacherPlace.teaching, child: TeachingScreen()),
      ),
      // Over the frame, from a period on Today, which knows the period.
      GoRoute(
        path: '/teaching/report',
        builder: (context, state) {
          final query = state.uri.queryParameters;
          return FileReportScreen(
            period: ReportPeriod(
              timetableEntryId: int.parse(query['entry'] ?? '0'),
              date: query['date'] ?? apiDate(DateTime.now()),
              classSection: query['class'] ?? '',
              subject: query['subject'] ?? 'Period',
              periodNumber: int.tryParse(query['period'] ?? '') ?? 0,
              subjectId: int.tryParse(query['subject_id'] ?? ''),
            ),
          );
        },
      ),
      GoRoute(
        path: '/teaching/reports/:id',
        builder: (context, state) => ReportDetailScreen(reportId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/teaching/syllabus/:sectionId/:subjectId',
        builder: (context, state) => SyllabusClassScreen(
          params: SyllabusChecklistParams(
            classSectionId: int.parse(state.pathParameters['sectionId']!),
            subjectId: int.parse(state.pathParameters['subjectId']!),
          ),
          label: state.uri.queryParameters['label'] ?? 'Syllabus',
        ),
      ),
      GoRoute(
        path: '/leave',
        builder: (context, state) => const TeacherFrame(place: TeacherPlace.leave, child: MyLeaveScreen()),
      ),
      // A screen of its own over the frame, with a back arrow: the form needs
      // the room the keyboard leaves.
      GoRoute(path: '/leave/apply', builder: (context, state) => const ApplyLeaveScreen()),
      GoRoute(
        path: '/pay',
        builder: (context, state) => const TeacherFrame(place: TeacherPlace.pay, child: MyPayslipsPhoneScreen()),
      ),
      GoRoute(
        path: '/pay/:id',
        builder: (context, state) => MyPayslipDetailScreen(payslipId: int.parse(state.pathParameters['id']!)),
      ),
      // Over the frame, from the register card on Today. The date comes from
      // Today, which has it from the server - the phone's own clock is not
      // the school's.
      GoRoute(
        path: '/register/:sectionId',
        builder: (context, state) => RegisterScreen(
          registerKey: (
            sectionId: int.parse(state.pathParameters['sectionId']!),
            date: state.uri.queryParameters['date'] ?? apiDate(DateTime.now()),
            label: state.uri.queryParameters['label'] ?? 'Class',
          ),
        ),
      ),
      // Over the frame, from the bell, with a back arrow.
      GoRoute(path: '/inbox', builder: (context, state) => const MyInboxScreen()),
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

      if (!appRoles.contains(user.role)) {
        return location == '/not-teacher' ? null : '/not-teacher';
      }

      if (user.mustChangePassword) {
        return location == '/change-password' ? null : '/change-password';
      }

      final known =
          teacherPaths.contains(location) ||
          _payslipPath.hasMatch(location) ||
          _registerPath.hasMatch(location) ||
          _teachingPaths.any((path) => path.hasMatch(location));
      return known ? null : '/today';
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

/// Signed in, but with an account this app is not for: bus crew, who have
/// the Driver app, or somebody who answers for many schools from the website.
class _NotTeacherScreen extends ConsumerWidget {
  const _NotTeacherScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crew = ref.watch(authNotifierProvider).value?.role.isCrew ?? false;

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
                crew ? 'Use the Driver app' : 'Use the School365ai website',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                crew
                    ? 'Drivers and bus attendants sign in to School365ai Driver, with their mobile number '
                          'and passcode.'
                    : 'This app is for the staff of a school. Your account looks after more than one school, '
                          'which the website is made for.',
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
