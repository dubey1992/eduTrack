import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/subjects/data/models/subject.dart';
import 'package:edutrack_app/features/subjects/data/subject_repository.dart';
import 'package:edutrack_app/features/timetable/application/timetable_grid_notifier.dart';
import 'package:edutrack_app/features/timetable/data/models/day_of_week.dart';
import 'package:edutrack_app/features/timetable/data/models/timetable_entry.dart';
import 'package:edutrack_app/features/timetable/data/timetable_repository.dart';
import 'package:edutrack_app/features/timetable/presentation/widgets/edit_entry_dialog.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_subject_repository.dart';
import '../../support/fake_timetable_repository.dart';
import '../../support/fake_user_repository.dart';

const _classSectionId = 10;

const _subject = Subject(
  id: 3,
  schoolId: 1,
  schoolName: 'Sunrise School',
  departmentId: 1,
  departmentName: 'Mathematics',
  code: 'MATH',
  name: 'Mathematics',
  minClassLevel: 1,
  maxClassLevel: 12,
  leadTeacherId: null,
  leadTeacherName: null,
);

const _teacher = AppUser(
  id: 20,
  firstName: 'Priya',
  lastName: 'Sharma',
  name: 'Priya Sharma',
  email: 'priya.sharma@example.com',
  mobile: null,
  role: UserRole.teacher,
  status: UserStatus.active,
);

const _existingEntry = TimetableEntry(
  id: 5,
  schoolId: 1,
  classSectionId: _classSectionId,
  classSectionName: 'Grade 8 A',
  periodId: 1,
  periodNumber: 1,
  dayOfWeek: DayOfWeek.monday,
  subjectId: 3,
  subjectName: 'Mathematics',
  teacherId: 20,
  teacherName: 'Priya Sharma',
);

// Opened via a real showDialog route (rather than placed directly as the
// Scaffold body) because EditEntryDialog pops itself on success - see
// add_school_dialog_test.dart's note on why that matters.
//
// timetableGridProvider is an AsyncNotifierProvider.autoDispose.family, and
// EditEntryDialog only ever *reads* it (ref.read(...).notifier), never
// watches it - so nothing keeps that family instance alive across the
// dialog's await chain unless something else in the tree watches it too,
// exactly like submit_report_dialog_test.dart's TeachingReportScreen parent
// does in the real app.
Widget wrap({
  required FakeTimetableRepository timetable,
  TimetableEntry? existing,
  List<Subject> subjects = const [_subject],
  List<AppUser> teachers = const [_teacher],
}) {
  final gridParams = TimetableGridParams.forClassSection(_classSectionId);

  return ProviderScope(
    overrides: [
      subjectRepositoryProvider.overrideWithValue(FakeSubjectRepository(subjects: subjects)),
      userRepositoryProvider.overrideWithValue(FakeUserRepository(users: teachers)),
      timetableRepositoryProvider.overrideWithValue(timetable),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            ref.watch(timetableGridProvider(gridParams));
            return Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => EditEntryDialog(
                    schoolId: null,
                    classSectionId: _classSectionId,
                    periodId: 1,
                    periodLabel: 'Period 1',
                    dayOfWeek: DayOfWeek.monday,
                    existing: existing,
                  ),
                ),
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows validation errors when subject and teacher are not selected', (tester) async {
    await tester.pumpWidget(wrap(timetable: FakeTimetableRepository()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Subject is required'), findsOneWidget);
    expect(find.text('Teacher is required'), findsOneWidget);
    expect(find.byType(EditEntryDialog), findsOneWidget);
  });

  testWidgets('creates a new entry for an empty cell and closes the dialog', (tester) async {
    final fake = FakeTimetableRepository();
    await tester.pumpWidget(wrap(timetable: fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Empty cell - no Clear button in create mode.
    expect(find.widgetWithText(TextButton, 'Clear'), findsNothing);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Subject'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mathematics').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Teacher'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Priya Sharma').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(EditEntryDialog), findsNothing);
    expect(fake.lastUpsertPayload, isNotNull);
    expect(fake.lastUpsertPayload!['class_section_id'], _classSectionId);
    expect(fake.lastUpsertPayload!['period_id'], 1);
    expect(fake.lastUpsertPayload!['day_of_week'], 'monday');
    expect(fake.lastUpsertPayload!['subject_id'], _subject.id);
    expect(fake.lastUpsertPayload!['teacher_id'], _teacher.id);
  });

  testWidgets('opens pre-filled for an occupied cell, allows changing it, and closes on save', (tester) async {
    const otherTeacher = AppUser(
      id: 21,
      firstName: 'Rahul',
      lastName: 'Verma',
      name: 'Rahul Verma',
      email: 'rahul.verma@example.com',
      mobile: null,
      role: UserRole.teacher,
      status: UserStatus.active,
    );
    final fake = FakeTimetableRepository(entries: [_existingEntry]);
    await tester.pumpWidget(wrap(timetable: fake, existing: _existingEntry, teachers: const [_teacher, otherTeacher]));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Pre-filled from the existing entry.
    expect(find.text('Mathematics'), findsOneWidget);
    expect(find.text('Priya Sharma'), findsOneWidget);
    // Occupied cell - Clear is offered.
    expect(find.widgetWithText(TextButton, 'Clear'), findsOneWidget);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Teacher'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rahul Verma').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(EditEntryDialog), findsNothing);
    expect(fake.lastUpsertPayload, isNotNull);
    expect(fake.lastUpsertPayload!['subject_id'], _subject.id);
    expect(fake.lastUpsertPayload!['teacher_id'], otherTeacher.id);
  });

  testWidgets('clearing an occupied cell deletes the entry and closes the dialog', (tester) async {
    final fake = FakeTimetableRepository(entries: [_existingEntry]);
    await tester.pumpWidget(wrap(timetable: fake, existing: _existingEntry));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pumpAndSettle();

    expect(find.byType(EditEntryDialog), findsNothing);
    expect(fake.lastDeletedId, _existingEntry.id);
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeTimetableRepository(
      failUpsertWith: const Failure(code: 'TEACHER_ALREADY_BOOKED', message: 'This teacher is already booked then.'),
    );
    await tester.pumpWidget(wrap(timetable: fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Subject'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mathematics').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Teacher'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Priya Sharma').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('This teacher is already booked then.'), findsOneWidget);
    expect(find.byType(EditEntryDialog), findsOneWidget);
  });
}
