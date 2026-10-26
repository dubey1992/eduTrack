import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/hod/data/hod_report_repository.dart';
import 'package:edutrack_app/features/hod/data/models/hod_department_report.dart';
import 'package:edutrack_app/features/holidays/data/models/holiday.dart';
import 'package:edutrack_app/features/my_department/presentation/department_screen.dart';
import 'package:edutrack_app/features/my_teaching/presentation/report_detail_screen.dart';
import 'package:edutrack_app/features/staff_attendance/data/models/staff_attendance_register.dart';
import 'package:edutrack_app/features/staff_attendance/data/models/staff_attendance_status.dart';
import 'package:edutrack_app/features/staff_attendance/data/staff_attendance_repository.dart';
import 'package:edutrack_app/features/teaching_reports/data/teaching_report_repository.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_hod_report_repository.dart';
import '../../support/fake_staff_attendance_repository.dart';
import '../../support/fake_teaching_report_repository.dart';
import '../../support/fake_today_repository.dart';
import '../../support/session_users.dart';
import '../my_teaching/teaching_fixtures.dart';

const hodId = 9;

StaffRosterEntry person(int id, String name, StaffAttendanceStatus? status, {String? checkIn, bool app = false}) =>
    StaffRosterEntry(
      staffProfileId: id,
      employeeId: 'EMP-$id',
      name: name,
      departmentName: 'Mathematics',
      status: status,
      checkIn: checkIn,
      checkOut: null,
      workingHours: null,
      remarks: null,
      checkedInFromApp: app,
    );

StaffAttendanceRegister registerOf(List<StaffRosterEntry> staff, {HolidaySummary? holiday}) =>
    StaffAttendanceRegister(schoolId: 1, attendanceDate: '2026-10-26', submitted: true, staff: staff, holiday: holiday);

HodTeacherRow teacherRow(int id, String name, {HodTeacherStatus status = HodTeacherStatus.onTrack}) => HodTeacherRow(
  staffProfileId: id,
  userId: id,
  teacherName: name,
  employeeId: 'EMP-$id',
  departmentId: 1,
  departmentName: 'Mathematics',
  attendancePercent: 96.4,
  leaveDays: 0,
  lateMarks: 0,
  classesAssigned: 20,
  classesTaught: 18,
  reportsSubmitted: 17,
  reportsPendingReview: 2,
  syllabusPercent: 40,
  status: status,
);

HodDepartmentReport monthOf(List<HodTeacherRow> teachers) => HodDepartmentReport(
  month: '2026-10',
  schoolId: 1,
  departments: const [],
  workingDays: 20,
  teacherCount: teachers.length,
  avgAttendancePercent: 96,
  leaveDays: 0,
  lateMarks: 0,
  teachers: teachers,
  currentPage: 1,
  lastPage: 1,
  total: teachers.length,
  perPage: 100,
);

/// The Department tab, for an HOD (docs/teacher-app.md, T7).
void main() {
  late FakeTeachingReportRepository reports;
  late FakeStaffAttendanceRepository staff;
  late FakeHodReportRepository month;

  setUp(() {
    reports = FakeTeachingReportRepository(
      reports: [
        report(id: 1),
        report(id: 2, topic: 'Place value'),
      ],
    );
    staff = FakeStaffAttendanceRepository(
      register: registerOf([
        person(1, 'Meera Joshi', StaffAttendanceStatus.present, checkIn: '08:20', app: true),
        person(2, 'Ravi Kumar', StaffAttendanceStatus.absent),
        person(3, 'Sana Khan', null),
      ]),
    );
    month = FakeHodReportRepository(
      report: monthOf([teacherRow(1, 'Meera Joshi'), teacherRow(2, 'Ravi Kumar', status: HodTeacherStatus.review)]),
    );
  });

  Future<void> pump(WidgetTester tester, {String at = '/department', UserRole role = UserRole.hod}) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: at,
      routes: [
        GoRoute(
          path: '/department',
          builder: (context, state) => const Scaffold(body: DepartmentScreen()),
        ),
        GoRoute(
          path: '/teaching/reports/:id',
          builder: (context, state) => ReportDetailScreen(reportId: int.parse(state.pathParameters['id']!)),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          teachingReportRepositoryProvider.overrideWithValue(reports),
          staffAttendanceRepositoryProvider.overrideWithValue(staff),
          hodReportRepositoryProvider.overrideWithValue(month),
          todayRepositoryProvider.overrideWithValue(FakeTodayRepository()),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(
              sessionOnRestore: sessionUser(role, id: hodId, name: 'Rohit Verma'),
            ),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.teacherLight(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key('department-tab-$key')));
    await tester.pumpAndSettle();
  }

  group('To review', () {
    testWidgets('asks the server for what is waiting, and lists it with who wrote it', (tester) async {
      await pump(tester);

      expect(reports.lastListToReview, isTrue);
      expect(find.byKey(const Key('review-1')), findsOneWidget);
      expect(find.byKey(const Key('review-2')), findsOneWidget);
      expect(find.text('Meera Joshi'), findsWidgets);
    });

    testWidgets('with nothing waiting, says so', (tester) async {
      reports = FakeTeachingReportRepository();
      await pump(tester);

      expect(find.byKey(const Key('review-empty')), findsOneWidget);
    });

    testWidgets('an error offers Retry, which tries again', (tester) async {
      reports.failListWith = Failure.network();
      await pump(tester);

      expect(find.text('Retry'), findsOneWidget);
      reports.failListWith = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-1')), findsOneWidget);
    });

    testWidgets('a report opens, is marked reviewed, and says who reviewed it', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const Key('review-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-review')));
      await tester.pumpAndSettle();

      expect(reports.lastReviewedId, 1);
      expect(find.text('By Meera Joshi'), findsOneWidget, reason: 'an HOD is told whose report it is');
      expect(find.text('Report reviewed.'), findsOneWidget);
      expect(find.byKey(const Key('report-review')), findsNothing, reason: 'reviewed once is reviewed');
      expect(find.byKey(const Key('report-reviewed-by')), findsOneWidget);
    });
  });

  group('Mark reviewed shows only where it may be used', () {
    testWidgets('never on the HOD\'s own report', (tester) async {
      reports = FakeTeachingReportRepository(reports: [report(id: 1, teacherId: hodId)]);
      await pump(tester, at: '/teaching/reports/1');

      expect(find.byKey(const Key('report-review')), findsNothing);
      expect(find.byKey(const Key('report-author')), findsNothing, reason: 'the author needs no telling');
    });

    testWidgets('never on a report already reviewed', (tester) async {
      reports = FakeTeachingReportRepository(reports: [report(id: 1, reviewed: true)]);
      await pump(tester, at: '/teaching/reports/1');

      expect(find.byKey(const Key('report-review')), findsNothing);
    });

    testWidgets('never for a teacher', (tester) async {
      await pump(tester, at: '/teaching/reports/1', role: UserRole.teacher);

      expect(find.byKey(const Key('report-review')), findsNothing);
    });
  });

  group('Staff today', () {
    testWidgets("reads the register for the school's today and shows who is in", (tester) async {
      await pump(tester);
      await openTab(tester, 'staff');

      expect(staff.lastRegisterDate, '2026-10-26');
      expect(find.text('1 of 3 in · 1 not marked yet'), findsOneWidget);
      expect(find.text('In 8:20 AM · from the app'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('staff-today-2')), matching: find.text('Absent')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('staff-today-3')), matching: find.text('Not marked')),
        findsOneWidget,
      );
    });

    testWidgets('a holiday says the school is closed', (tester) async {
      staff = FakeStaffAttendanceRepository(
        register: registerOf(
          const [],
          holiday: const HolidaySummary(id: 1, name: 'Diwali', type: HolidayType.religious),
        ),
      );
      await pump(tester);
      await openTab(tester, 'staff');

      expect(find.byKey(const Key('staff-today-holiday')), findsOneWidget);
    });

    testWidgets('a department with nobody in it says who adds staff', (tester) async {
      staff = FakeStaffAttendanceRepository(register: registerOf(const []));
      await pump(tester);
      await openTab(tester, 'staff');

      expect(find.byKey(const Key('staff-today-empty')), findsOneWidget);
    });

    testWidgets('an error offers Retry', (tester) async {
      staff.failRegisterWith = Failure.network();
      await pump(tester);
      await openTab(tester, 'staff');

      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('This month', () {
    testWidgets("each teacher's month, for this month", (tester) async {
      await pump(tester);
      await openTab(tester, 'month');

      expect(month.lastRequest!['month'], '2026-10');
      expect(find.text('17/18'), findsNWidgets(2));
      expect(find.text('40%'), findsNWidgets(2));
      expect(
        find.descendant(of: find.byKey(const Key('month-2')), matching: find.text('Needs a look')),
        findsOneWidget,
      );
    });

    testWidgets('no teachers says who adds them', (tester) async {
      month = FakeHodReportRepository(report: monthOf(const []));
      await pump(tester);
      await openTab(tester, 'month');

      expect(find.byKey(const Key('month-empty')), findsOneWidget);
    });

    testWidgets('an error offers Retry', (tester) async {
      month = FakeHodReportRepository(report: monthOf(const []), failWith: Failure.network());
      await pump(tester);
      await openTab(tester, 'month');

      expect(find.text('Retry'), findsOneWidget);
    });
  });

  testWidgets('fits a phone without overflowing', (tester) async {
    await pump(tester);
    await openTab(tester, 'month');

    expect(tester.takeException(), isNull);
  });
}
