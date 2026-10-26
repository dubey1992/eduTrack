import 'package:edutrack_app/core/models/permission_level.dart';
import 'package:edutrack_app/features/assessments/data/assessment_repository.dart';
import 'package:edutrack_app/features/my_teaching/presentation/file_report_screen.dart';
import 'package:edutrack_app/features/my_teaching/presentation/marks_entry_screen.dart';
import 'package:edutrack_app/features/my_teaching/presentation/new_test_screen.dart';
import 'package:edutrack_app/features/my_teaching/presentation/report_detail_screen.dart';
import 'package:edutrack_app/features/my_teaching/presentation/syllabus_class_screen.dart';
import 'package:edutrack_app/features/my_teaching/presentation/teaching_screen.dart';
import 'package:edutrack_app/features/syllabus/data/syllabus_progress_repository.dart';
import 'package:edutrack_app/features/teaching_reports/data/teaching_report_repository.dart';
import 'package:edutrack_app/features/attendance/data/attendance_repository.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_register.dart';
import 'package:edutrack_app/features/my_register/presentation/register_screen.dart';
import 'package:edutrack_app/features/my_inbox/data/my_inbox_repository.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/maintenance_notifier.dart';
import 'package:edutrack_app/core/routing/teacher_router.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:edutrack_app/features/auth/presentation/teacher/teacher_welcome_screen.dart';
import 'package:edutrack_app/features/auth/presentation/teacher_splash_screen.dart';
import 'package:edutrack_app/features/errors/presentation/maintenance_screen.dart';
import 'package:edutrack_app/features/profile/data/profile_repository.dart';
import 'package:edutrack_app/features/profile/presentation/profile_screen.dart';
import 'package:edutrack_app/features/check_in/data/check_in_repository.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:edutrack_app/features/today/presentation/staff_home_screen.dart';
import 'package:edutrack_app/features/today/presentation/today_screen.dart';
import 'package:edutrack_app/main_teacher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_my_inbox_repository.dart';
import '../../support/fake_attendance_repository.dart';
import '../../features/my_teaching/teaching_fixtures.dart';
import '../../support/fake_assessment_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_syllabus_progress_repository.dart';
import '../../support/fake_teaching_report_repository.dart';
import '../../support/fake_auth_token_storage.dart';
import '../../support/fake_profile_repository.dart';
import '../../support/fake_check_in_repository.dart';
import '../../support/fake_today_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/session_users.dart';

const _grade8A = AttendanceRegister(
  classSectionId: 81,
  attendanceDate: '2026-10-26',
  submitted: false,
  students: [AttendanceRosterEntry(studentId: 1, name: 'Asha Rao', rollNumber: '1', status: null, remarks: null)],
);

/// What the teacher app has screens for (docs/teacher-app.md, T0).
///
/// As with the driver router, most of these are about absence: this build
/// carries the sign-in, Today and the teacher's own profile, and none of
/// the office.
void main() {
  Widget teacherApp(FakeAuthRepository auth, {bool maintenance = false}) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
        todayRepositoryProvider.overrideWithValue(FakeTodayRepository()),
        myInboxRepositoryProvider.overrideWithValue(FakeMyInboxRepository()),
        checkInRepositoryProvider.overrideWithValue(FakeCheckInRepository()),
        attendanceRepositoryProvider.overrideWithValue(FakeAttendanceRepository(register: _grade8A)),
        assessmentRepositoryProvider.overrideWithValue(
          FakeAssessmentRepository(assessments: [fakeAssessment(id: 41)], sheetEntries: const []),
        ),
        teachingReportRepositoryProvider.overrideWithValue(FakeTeachingReportRepository(reports: [report(id: 501)])),
        syllabusProgressRepositoryProvider.overrideWithValue(
          FakeSyllabusProgressRepository(checklist: mathsChecklist(), myClasses: const [mathsGrade3A]),
        ),
        authTokenStorageProvider.overrideWithValue(FakeAuthTokenStorage()),
        if (maintenance) maintenanceProvider.overrideWith(_Down.new),
      ],
      child: const TeacherApp(),
    );
  }

  Future<void> pump(WidgetTester tester, FakeAuthRepository auth, {Size size = const Size(480, 2000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(teacherApp(auth));
    await tester.pump(teacherOpeningBeat + const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  group('the screens it carries', () {
    Iterable<String> pathsOf(ProviderContainer container) {
      return container.read(teacherRouterProvider).configuration.routes.whereType<GoRoute>().map((route) => route.path);
    }

    test('are the sign-in, Today and the profile', () {
      final container = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())]);
      addTearDown(container.dispose);

      expect(
        pathsOf(container),
        containsAll([
          '/splash',
          '/welcome',
          '/login',
          '/forgot-password',
          '/change-password',
          '/today',
          '/profile',
          '/maintenance',
          '/not-teacher',
        ]),
      );
    });

    test('and none of the office, nor the bus', () {
      final container = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())]);
      addTearDown(container.dispose);

      for (final elsewhere in [
        '/',
        '/dashboard',
        '/students',
        '/payroll',
        '/schools',
        '/my-trip',
        '/attendant-login',
      ]) {
        expect(pathsOf(container), isNot(contains(elsewhere)), reason: elsewhere);
      }
    });

    test('every reachable address is a route, and the other way round', () {
      final container = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())]);
      addTearDown(container.dispose);

      // The driver router's lesson: a screen that is routed but not in the
      // reachable set is bounced back to home the moment it opens.
      expect(pathsOf(container).toSet(), containsAll(teacherPaths));
    });
  });

  group('where it opens', () {
    testWidgets('on the splash first, which says what it is doing', (tester) async {
      tester.view.physicalSize = const Size(480, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(teacherApp(FakeAuthRepository()));
      await tester.pump();

      expect(find.byType(TeacherSplashScreen), findsOneWidget);
      expect(find.text('Getting your day ready…'), findsOneWidget);

      // Past the beat, so the held timer does not outlive the test.
      await tester.pump(teacherOpeningBeat + const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.byType(TeacherSplashScreen), findsNothing);
    });

    testWidgets('signed out: on the sign-in, without the bus crew\'s way in', (tester) async {
      await pump(tester, FakeAuthRepository());

      expect(find.byType(TeacherWelcomeScreen), findsOneWidget);
      expect(find.textContaining('Welcome to a Smarter School'), findsNothing, reason: "the web's marketing panel");
      expect(find.textContaining('Bus attendant?'), findsNothing);
    });

    testWidgets('signed in as a teacher: on Today, framed with the two tabs', (tester) async {
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher, name: 'Asha Rao')));

      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.text('Good day, Asha'), findsOneWidget);
      expect(find.byKey(const Key('teacher-nav')), findsOneWidget);
      expect(find.byKey(const Key('teacher-nav-today')), findsOneWidget);
      expect(find.byKey(const Key('teacher-nav-teaching')), findsOneWidget);
      expect(find.byKey(const Key('teacher-nav-profile')), findsOneWidget);
      expect(find.text('Asha Rao'), findsOneWidget, reason: 'the header says who is signed in');
    });

    testWidgets('an HOD is a teacher here too', (tester) async {
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.hod)));

      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('opens the class register from Today, and comes back', (tester) async {
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher)));

      await tester.tap(find.byKey(const Key('today-register-81')));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsOneWidget, reason: 'not bounced back to Today');
      expect(find.text('Grade 8 A register'), findsOneWidget);
      expect(find.text('Asha Rao'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('opens Teaching, a report and a class syllabus, and comes back from each', (tester) async {
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher)));

      await tester.tap(find.byKey(const Key('teacher-nav-teaching')));
      await tester.pumpAndSettle();
      expect(find.byType(TeachingScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('my-report-501')));
      await tester.pumpAndSettle();
      expect(find.byType(ReportDetailScreen), findsOneWidget, reason: 'not bounced back to Today');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('teaching-tab-syllabus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('my-syllabus-622-31')));
      await tester.pumpAndSettle();
      expect(find.byType(SyllabusClassScreen), findsOneWidget, reason: 'not bounced back to Today');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(TeachingScreen), findsOneWidget);
    });

    testWidgets('opens Marks, a sheet and the New test form, and comes back', (tester) async {
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher)));

      await tester.tap(find.byKey(const Key('teacher-nav-teaching')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('teaching-tab-marks')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('my-test-41')));
      await tester.pumpAndSettle();
      expect(find.byType(MarksEntryScreen), findsOneWidget, reason: 'not bounced back to Today');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('my-tests-new')));
      await tester.pumpAndSettle();
      expect(find.byType(NewTestScreen), findsOneWidget, reason: 'not bounced back to Today');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(TeachingScreen), findsOneWidget);
    });

    testWidgets('opens the report form from a period on Today', (tester) async {
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher)));

      await tester.ensureVisible(find.byKey(const Key('today-period-11')));
      await tester.tap(find.byKey(const Key('today-period-11')));
      await tester.pumpAndSettle();
      expect(find.byType(FileReportScreen), findsOneWidget, reason: 'not bounced back to Today');
    });

    testWidgets('a teacher whose school switched reports, the syllabus and class tests off has no Teaching tab', (
      tester,
    ) async {
      await pump(
        tester,
        FakeAuthRepository(
          sessionOnRestore: sessionUser(
            UserRole.teacher,
            permissions: {
              ...allModulesAt(PermissionLevel.manage),
              'teaching_reports': PermissionLevel.none,
              'syllabus': PermissionLevel.none,
              'assessments': PermissionLevel.none,
            },
          ),
        ),
      );

      expect(find.byKey(const Key('teacher-nav-teaching')), findsNothing);
    });

    testWidgets('and reaches their own profile and comes back', (tester) async {
      await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher)));

      await tester.tap(find.byKey(const Key('teacher-nav-profile')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('teacher-nav-today')));
      await tester.pumpAndSettle();
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('on a tablet the screen keeps a readable column instead of stretching', (tester) async {
      await pump(
        tester,
        FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher)),
        size: const Size(1600, 2560),
      );

      final width = tester.getSize(find.byType(TodayScreen)).width;
      expect(width, greaterThan(480));
      expect(width, lessThanOrEqualTo(640));
    });

    // The rest of the school's staff: their home is check-in, not periods
    // (docs/staff-check-in.md).
    for (final (role, label) in [
      (UserRole.schoolAdmin, 'a school admin'),
      (UserRole.staff, 'office staff'),
      (UserRole.accountant, 'an accountant'),
      (UserRole.transportManager, 'a transport manager'),
    ]) {
      testWidgets('signed in as $label: on their own Home, with check-in and the same two tabs', (tester) async {
        await pump(tester, FakeAuthRepository(sessionOnRestore: sessionUser(role)));

        expect(find.byType(StaffHomeScreen), findsOneWidget);
        expect(find.byType(TodayScreen), findsNothing, reason: 'no periods for somebody without a timetable');
        expect(find.byKey(const Key('check-in-card')), findsOneWidget);
        expect(find.byKey(const Key('teacher-nav')), findsOneWidget);
        expect(find.byKey(const Key('teacher-nav-teaching')), findsNothing, reason: 'no periods to report on');
      });
    }

    for (final (role, label, title) in [
      (UserRole.busAttendant, 'bus crew', 'Use the Driver app'),
      (UserRole.driver, 'a driver', 'Use the Driver app'),
      (UserRole.groupAdmin, 'a group admin', 'Use the School365ai website'),
      (UserRole.superAdmin, 'the super admin', 'Use the School365ai website'),
    ]) {
      testWidgets('signed in as $label: told where to go instead, with a way out', (tester) async {
        final auth = FakeAuthRepository(sessionOnRestore: sessionUser(role));
        await pump(tester, auth);

        expect(find.text(title), findsOneWidget);
        expect(find.byType(TodayScreen), findsNothing);
        expect(find.byType(StaffHomeScreen), findsNothing);

        await tester.tap(find.byKey(const Key('not-teacher-sign-out')));
        await tester.pumpAndSettle();
        expect(find.byType(TeacherWelcomeScreen), findsOneWidget);
      });
    }

    testWidgets('with the API down it waits, over everything else', (tester) async {
      tester.view.physicalSize = const Size(480, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        teacherApp(FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher)), maintenance: true),
      );
      await tester.pump(teacherOpeningBeat + const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.byType(MaintenanceScreen), findsOneWidget);
    });
  });
}

/// The API reported down, from the first frame.
class _Down extends MaintenanceNotifier {
  @override
  bool build() => true;
}
