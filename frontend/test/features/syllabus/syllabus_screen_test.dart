import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/subjects/data/models/subject.dart';
import 'package:edutrack_app/features/subjects/data/subject_repository.dart';
import 'package:edutrack_app/features/syllabus/data/models/syllabus_checklist.dart';
import 'package:edutrack_app/features/syllabus/data/syllabus_progress_repository.dart';
import 'package:edutrack_app/features/syllabus/data/syllabus_topic_repository.dart';
import 'package:edutrack_app/features/syllabus/presentation/syllabus_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_class_repository.dart';
import '../../support/fake_school_repository.dart';
import '../../support/fake_subject_repository.dart';
import '../../support/fake_syllabus_progress_repository.dart';
import '../../support/fake_syllabus_topic_repository.dart';

const _schoolAdmin = AuthenticatedUser(id: 5, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);
const _teacher = AuthenticatedUser(id: 20, name: 'Priya Sharma', email: 'priya@example.com', role: UserRole.teacher);

const _subject = Subject(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  departmentId: 1,
  departmentName: 'Mathematics',
  code: 'MAT',
  name: 'Mathematics',
  minClassLevel: 1,
  maxClassLevel: 10,
  leadTeacherId: null,
  leadTeacherName: null,
);

final _schoolClass = SchoolClass(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  academicYearId: 1,
  academicYearName: '2026-27',
  name: 'Grade 8',
  level: 8,
  sections: const [
    ClassSection(id: 10, schoolClassId: 1, name: 'A', roomNumber: null, classTeacherId: null, classTeacherName: null),
  ],
);

const _checklist = SyllabusChecklist(
  subjectId: 1,
  subjectName: 'Mathematics',
  classSectionId: 10,
  totalTopics: 1,
  completedTopics: 0,
  progressPercent: 0,
  topics: [
    SyllabusChecklistItem(
      id: 5,
      title: 'Whole Numbers',
      sequenceNumber: 1,
      completed: false,
      completedByName: null,
      completedAt: null,
    ),
  ],
);

Widget wrap(AuthenticatedUser actor, {FakeSyllabusProgressRepository? progressFake}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      subjectRepositoryProvider.overrideWithValue(FakeSubjectRepository(subjects: [_subject])),
      schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository(classes: [_schoolClass])),
      syllabusTopicRepositoryProvider.overrideWithValue(FakeSyllabusTopicRepository()),
      syllabusProgressRepositoryProvider.overrideWithValue(
        progressFake ?? FakeSyllabusProgressRepository(checklist: _checklist),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: SyllabusScreen()),
    ),
  );
}

Future<void> _pickSubjectAndSection(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Subject'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Mathematics').last);
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Class'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Grade 8 A').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('prompts to pick a subject and class before showing anything', (tester) async {
    await tester.pumpWidget(wrap(_schoolAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Pick a subject and a class section to view its syllabus.'), findsOneWidget);
  });

  testWidgets('a school admin sees Add/Edit/Delete controls and the progress bar', (tester) async {
    await tester.pumpWidget(wrap(_schoolAdmin));
    await tester.pumpAndSettle();

    await _pickSubjectAndSection(tester);

    expect(find.text('Add Topic'), findsOneWidget);
    expect(find.text('0 of 1 topics covered'), findsOneWidget);
    expect(find.text('1. Whole Numbers'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('a teacher does not see outline management controls', (tester) async {
    await tester.pumpWidget(wrap(_teacher));
    await tester.pumpAndSettle();

    await _pickSubjectAndSection(tester);

    expect(find.text('Add Topic'), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.text('1. Whole Numbers'), findsOneWidget);
  });

  testWidgets('ticking a topics checkbox marks it complete', (tester) async {
    final progressFake = FakeSyllabusProgressRepository(checklist: _checklist);
    await tester.pumpWidget(wrap(_teacher, progressFake: progressFake));
    await tester.pumpAndSettle();

    await _pickSubjectAndSection(tester);
    expect(find.text('0 of 1 topics covered'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(find.text('1 of 1 topics covered'), findsOneWidget);
  });
}
