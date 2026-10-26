import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/date_period.dart';
import 'package:edutrack_app/features/reports/data/models/report.dart';
import 'package:edutrack_app/features/reports/data/report_repository.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/hod/data/hod_report_repository.dart';
import 'package:edutrack_app/features/hod/data/models/hod_department_report.dart';
import 'package:edutrack_app/features/holidays/data/models/holiday.dart';
import 'package:edutrack_app/features/my_department/presentation/department_screen.dart';
import 'package:edutrack_app/features/my_teaching/presentation/report_detail_screen.dart';
import 'package:edutrack_app/features/staff_attendance/data/models/staff_attendance_register.dart';
import 'package:edutrack_app/features/staff_attendance/data/models/staff_attendance_status.dart';
import 'package:edutrack_app/features/staff_attendance/data/staff_attendance_repository.dart';
import 'package:edutrack_app/features/teaching_reports/data/models/teaching_report.dart';
import 'package:edutrack_app/features/teaching_reports/data/teaching_report_repository.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_hod_report_repository.dart';
import '../../support/fake_report_repository.dart';
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

TeachingReport returnedReport({required String note, int teacherId = hodId}) {
  final base = report(id: 1);
  return TeachingReport(
    id: base.id,
    schoolId: base.schoolId,
    timetableEntryId: base.timetableEntryId,
    classSectionName: base.classSectionName,
    periodNumber: base.periodNumber,
    subjectName: base.subjectName,
    teacherId: teacherId,
    teacherName: 'Meera Joshi',
    reportDate: base.reportDate,
    topicTaught: base.topicTaught,
    homework: null,
    remarks: null,
    reviewedBy: null,
    reviewedByName: null,
    reviewedAt: null,
    status: ReportStatus.returned,
    reviewNote: note,
    returnedAt: '2026-10-26T06:00:00Z',
    returnedByName: 'Rohit Verma',
  );
}

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
  late FakeReportRepository staffReport;

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
    staffReport = FakeReportRepository(
      result: ReportResult.fromJson({
        'range': {'from': '2026-10-26', 'to': '2026-10-28', 'working_days': 3},
        'rows': [
          {
            'staff_profile_id': 1,
            'name': 'Meera Joshi',
            'present': 3,
            'half_day': 0,
            'absent': 0,
            'leave': 0,
            'not_marked': 0,
            'attendance_rate': 96,
          },
        ],
        'totals': {'working_days': 3},
      }),
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
          reportRepositoryProvider.overrideWithValue(staffReport),
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

  group('Sending a report back', () {
    Future<void> openFirst(WidgetTester tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('review-1')));
      await tester.pumpAndSettle();
    }

    testWidgets('needs a note saying what should change', (tester) async {
      await openFirst(tester);

      await tester.tap(find.byKey(const Key('report-send-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send-back-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Say what should change.'), findsOneWidget);
      expect(reports.lastSendBackNote, isNull);
    });

    testWidgets('goes back with the note, and the report says so', (tester) async {
      await openFirst(tester);

      await tester.tap(find.byKey(const Key('report-send-back')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('send-back-note')), '  Please add what the class practised. ');
      await tester.tap(find.byKey(const Key('send-back-confirm')));
      await tester.pumpAndSettle();

      expect(reports.lastSendBackNote, 'Please add what the class practised.');
      expect(find.text('Sent back to the teacher.'), findsOneWidget);
      expect(find.text('Sent back'), findsOneWidget);
      expect(find.byKey(const Key('report-hod-note')), findsOneWidget);
      expect(find.byKey(const Key('report-returned-waiting')), findsOneWidget);
      expect(find.byKey(const Key('report-send-back')), findsNothing, reason: 'it is with the teacher now');
      expect(find.byKey(const Key('report-review')), findsOneWidget, reason: 'it may still be passed as fine');
    });

    testWidgets('a report already back with its teacher is said plainly', (tester) async {
      reports.failSendBackWith = const Failure(
        code: 'TEACHING_REPORT_RETURNED',
        message: 'This report is already back with its teacher.',
      );
      await openFirst(tester);

      await tester.tap(find.byKey(const Key('report-send-back')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('send-back-note')), 'More detail please.');
      await tester.tap(find.byKey(const Key('send-back-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('This report is already back with its teacher.'), findsOneWidget);
    });

    testWidgets('a review may carry a note too, and the teacher reads it', (tester) async {
      reports = FakeTeachingReportRepository(reports: [returnedReport(note: 'Please add what the class practised.')]);
      await pump(tester, at: '/teaching/reports/1', role: UserRole.teacher);

      expect(find.text('Sent back by Rohit Verma'), findsOneWidget);
      expect(find.text('Please add what the class practised.'), findsOneWidget);
    });
  });

  group('The teacher changes it and sends it again', () {
    testWidgets('opens prefilled, sends the changes, and it waits for review again', (tester) async {
      reports = FakeTeachingReportRepository(reports: [returnedReport(note: 'Add the homework.')]);
      await pump(tester, at: '/teaching/reports/1', role: UserRole.teacher);

      await tester.tap(find.byKey(const Key('report-change')));
      await tester.pumpAndSettle();
      expect(find.text('Change the report'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Fractions: adding unlike denominators'), findsOneWidget);
      expect(find.byKey(const Key('report-hod-note')), findsOneWidget, reason: 'what was asked, while answering it');

      await tester.enterText(find.byKey(const Key('report-homework')), 'Exercise 4.3');
      await tester.ensureVisible(find.byKey(const Key('report-submit')));
      await tester.tap(find.byKey(const Key('report-submit')));
      await tester.pumpAndSettle();

      expect(reports.lastResubmit, {
        'topic_taught': 'Fractions: adding unlike denominators',
        'homework': 'Exercise 4.3',
        'remarks': null,
      });
      expect(find.text('Sent again for review.'), findsOneWidget);
      expect(find.text('Awaiting review'), findsOneWidget);
      expect(find.byKey(const Key('report-change')), findsNothing);
    });

    testWidgets('nobody else gets Change', (tester) async {
      reports = FakeTeachingReportRepository(reports: [returnedReport(note: 'Add the homework.', teacherId: 7)]);
      await pump(tester, at: '/teaching/reports/1');

      expect(find.byKey(const Key('report-change')), findsNothing);
    });
  });

  group('By period', () {
    testWidgets('To review: This month asks for this month', (tester) async {
      await pump(tester);

      await tester.ensureVisible(find.byKey(const Key('period-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('period-month')));
      await tester.pumpAndSettle();

      final month = DatePeriod.month.rangeFrom(DateTime.now())!;
      expect(reports.lastListRange, (month.from, month.to));
    });

    testWidgets('Staff: a week shows each person totals from the attendance report', (tester) async {
      await pump(tester);
      await openTab(tester, 'staff');
      expect(find.byKey(const Key('staff-today-summary')), findsOneWidget, reason: 'a day is the register');

      await tester.ensureVisible(find.byKey(const Key('period-week')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('period-week')).last);
      await tester.pumpAndSettle();

      // The school's today is Monday 26 October: the week starts there and
      // stops there, since the report refuses days still to come.
      expect(staffReport.lastKind, ReportKind.staffAttendance);
      expect((staffReport.lastFrom, staffReport.lastTo), ('2026-10-26', '2026-10-26'));
      expect(find.text('3 school days so far'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('staff-period-1')), matching: find.text('96%')), findsOneWidget);
    });

    testWidgets('Staff: a month runs from the 1st to the school today, never past it', (tester) async {
      await pump(tester);
      await openTab(tester, 'staff');

      await tester.ensureVisible(find.byKey(const Key('period-month')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('period-month')).last);
      await tester.pumpAndSettle();

      expect((staffReport.lastFrom, staffReport.lastTo), ('2026-10-01', '2026-10-26'));
    });

    testWidgets('Staff: no week view offers All - a register is always about days', (tester) async {
      await pump(tester);
      await openTab(tester, 'staff');

      expect(find.byKey(const Key('period-all')), findsNothing);
    });
  });
}
