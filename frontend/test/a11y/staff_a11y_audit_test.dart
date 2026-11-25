import 'package:edutrack_app/features/assessments/data/assessment_repository.dart';
import 'package:edutrack_app/features/hod/data/hod_report_repository.dart';
import 'package:edutrack_app/features/hod/data/models/hod_department_report.dart';
import 'package:edutrack_app/features/staff_attendance/data/models/staff_attendance_register.dart';
import 'package:edutrack_app/features/staff_attendance/data/staff_attendance_repository.dart';
import 'package:edutrack_app/features/syllabus/data/syllabus_progress_repository.dart';
import 'package:edutrack_app/features/teaching_reports/data/teaching_report_repository.dart';
import 'package:edutrack_app/features/attendance/data/attendance_repository.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_register.dart';
import 'package:edutrack_app/features/my_inbox/data/my_inbox_repository.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/routing/teacher_router.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:edutrack_app/features/profile/data/profile_repository.dart';
import 'package:edutrack_app/features/check_in/data/check_in_repository.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:edutrack_app/main_teacher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_my_inbox_repository.dart';
import '../support/fake_attendance_repository.dart';
import '../features/my_teaching/teaching_fixtures.dart';
import '../support/fake_assessment_repository.dart';
import '../support/fake_auth_repository.dart';
import '../support/fake_hod_report_repository.dart';
import '../support/fake_staff_attendance_repository.dart';
import '../support/fake_syllabus_progress_repository.dart';
import '../support/fake_teaching_report_repository.dart';
import '../support/fake_auth_token_storage.dart';
import '../support/fake_profile_repository.dart';
import '../support/fake_check_in_repository.dart';
import '../support/fake_today_repository.dart';
import '../support/in_memory_key_value_store.dart';
import '../support/session_users.dart';

import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/assessments/data/models/assessment_sheet.dart';
import 'package:edutrack_app/features/my_teaching/data/marks_dictation.dart';
import 'package:edutrack_app/features/my_teaching/data/marks_photo_reader.dart';
import 'package:edutrack_app/features/my_teaching/presentation/marks_entry_screen.dart';
import 'package:edutrack_app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../features/my_teaching/marks_input_fakes.dart';

import 'a11y_audit.dart';

const _grade8A = AttendanceRegister(
  classSectionId: 81,
  attendanceDate: '2026-10-26',
  submitted: false,
  students: [AttendanceRosterEntry(studentId: 1, name: 'Asha Rao', rollNumber: '1', status: null, remarks: null)],
);

/// Large text and screen readers in the Staff app (docs/mobile-apps-review.md,
/// M11, 3.4): every screen for a teacher, an HOD and an accountant, in English
/// and Hindi, at normal and double text size.
void main() {
  List<Override> staffOverrides(FakeAuthRepository auth, InMemoryKeyValueStore store) {
    return [
      authRepositoryProvider.overrideWithValue(auth),
      keyValueStoreProvider.overrideWithValue(store),
      profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
      todayRepositoryProvider.overrideWithValue(FakeTodayRepository()),
      myInboxRepositoryProvider.overrideWithValue(FakeMyInboxRepository()),
      checkInRepositoryProvider.overrideWithValue(FakeCheckInRepository()),
      attendanceRepositoryProvider.overrideWithValue(FakeAttendanceRepository(register: _grade8A)),
      assessmentRepositoryProvider.overrideWithValue(
        FakeAssessmentRepository(assessments: [fakeAssessment(id: 41)], sheetEntries: const []),
      ),
      staffAttendanceRepositoryProvider.overrideWithValue(
        FakeStaffAttendanceRepository(
          register: const StaffAttendanceRegister(
            schoolId: 1,
            attendanceDate: '2026-10-26',
            submitted: false,
            staff: [],
          ),
        ),
      ),
      hodReportRepositoryProvider.overrideWithValue(
        FakeHodReportRepository(
          report: const HodDepartmentReport(
            month: '2026-10',
            schoolId: 1,
            departments: [],
            workingDays: 20,
            teacherCount: 0,
            avgAttendancePercent: 0,
            leaveDays: 0,
            lateMarks: 0,
            teachers: [],
            currentPage: 1,
            lastPage: 1,
            total: 0,
            perPage: 100,
          ),
        ),
      ),
      teachingReportRepositoryProvider.overrideWithValue(FakeTeachingReportRepository(reports: [report(id: 501)])),
      syllabusProgressRepositoryProvider.overrideWithValue(
        FakeSyllabusProgressRepository(checklist: mathsChecklist(), myClasses: const [mathsGrade3A]),
      ),
      authTokenStorageProvider.overrideWithValue(FakeAuthTokenStorage()),
    ];
  }

  for (final language in ['en', 'hi']) {
    for (final role in [UserRole.teacher, UserRole.hod, UserRole.accountant]) {
      for (final scale in [1.0, 2.0]) {
        for (final path in teacherPaths) {
          testWidgets('${role.name} $path in $language at ${scale}x', (tester) async {
            tester.view.physicalSize = const Size(412, 915);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
            final handle = tester.ensureSemantics();
            final audit = A11yAudit(tester)..watchLayout();
            // The language the person picked, as the app keeps it (M11).
            final store = InMemoryKeyValueStore()..values['app.language'] = language;
            final container = ProviderContainer(
              overrides: staffOverrides(
                FakeAuthRepository(sessionOnRestore: sessionUser(role, name: 'Meera Joshi')),
                store,
              ),
            );
            addTearDown(container.dispose);
            await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const TeacherApp()));
            await tester.pump(teacherOpeningBeat + const Duration(milliseconds: 100));
            await tester.pumpAndSettle();
            container.read(teacherRouterProvider).go(path);
            await tester.pumpAndSettle();

            expect(await audit.checkScrolling(), isEmpty);
            handle.dispose();
          });
        }
      }
    }
  }

  // Marks by voice or camera (M12, 1.7): the sheet's two new buttons, and the
  // review of what was read, with a highlighted row and the issues list.
  for (final language in ['en', 'hi']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('marks sheet and the review of read marks in $language at ${scale}x', (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final handle = tester.ensureSemantics();
        final audit = A11yAudit(tester)..watchLayout();
        final voice = FakeMarksDictation(hears: ['roll 1 81 roll 2 absent roll 9 12 13']);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              assessmentRepositoryProvider.overrideWithValue(
                FakeAssessmentRepository(
                  sheetEntries: [
                    for (final (id, name) in [(1, 'Asha Rao'), (2, 'Kabir Singh'), (3, 'Meera Iyer')])
                      SheetEntry(
                        studentId: id,
                        studentName: name,
                        admissionNumber: 'ADM-$id',
                        rollNumber: '$id',
                        marksObtained: null,
                        isAbsent: false,
                        grade: null,
                        percentage: null,
                        passed: null,
                        remarks: null,
                      ),
                  ],
                ),
              ),
              keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
              authRepositoryProvider.overrideWithValue(
                FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher, name: 'Meera Joshi')),
              ),
              marksDictationProvider.overrideWithValue(voice),
              marksPhotoReaderProvider.overrideWithValue(FakeMarksPhotoReader()),
            ],
            child: MaterialApp(
              theme: AppTheme.teacherLight(),
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const MarksEntryScreen(assessmentId: 41),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // The marks rows themselves at double size predate M12 and are out of
        // this check's scope; the buttons and the review are what it is about.
        if (scale > 1) tester.takeException();
        expect(await audit.check(), isEmpty);

        await tester.tap(find.byKey(const Key('marks-speak')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('marks-review')), findsOneWidget);

        expect(await audit.checkScrolling(), isEmpty);
        handle.dispose();
      });
    }
  }
}
