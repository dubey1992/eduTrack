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
import 'package:edutrack_app/features/syllabus/data/models/syllabus_topic.dart';
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

const _admin = AuthenticatedUser(id: 5, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

const _subject = Subject(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  departmentId: 1,
  departmentName: 'Computer Science',
  code: 'CS',
  name: 'Computer Science',
  minClassLevel: -3,
  maxClassLevel: 12,
  leadTeacherId: null,
  leadTeacherName: null,
);

final _playgroup = SchoolClass(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  academicYearId: 1,
  academicYearName: '2026-27',
  name: 'Playgroup',
  level: -3,
  sections: const [
    ClassSection(id: 10, schoolClassId: 1, name: 'A', roomNumber: null, classTeacherId: null, classTeacherName: null),
  ],
);

SyllabusChecklistItem _item(int id, String title, int number, int? level) => SyllabusChecklistItem(
  id: id,
  title: title,
  sequenceNumber: number,
  completed: false,
  completedByName: null,
  completedAt: null,
  classLevel: level,
);

/// Playgroup's Computer Science: two of its own topics and one written
/// before topics had classes.
final _checklist = SyllabusChecklist(
  subjectId: 1,
  subjectName: 'Computer Science',
  classSectionId: 10,
  totalTopics: 3,
  completedTopics: 0,
  progressPercent: 0,
  classLevel: -3,
  classLevelName: 'Playgroup',
  topics: [_item(7, 'Using a mouse', 1, null), _item(8, 'Colours on screen', 1, -3), _item(9, 'Tap and drag', 2, -3)],
);

SyllabusTopic _topic(int id, String title, int number, int? level) => SyllabusTopic(
  id: id,
  schoolId: 1,
  subjectId: 1,
  subjectName: 'Computer Science',
  title: title,
  sequenceNumber: number,
  classLevel: level,
);

Future<FakeSyllabusTopicRepository> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final topics = FakeSyllabusTopicRepository(
    topics: [
      _topic(7, 'Using a mouse', 1, null),
      _topic(8, 'Colours on screen', 1, -3),
      _topic(9, 'Tap and drag', 2, -3),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _admin)),
        schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
        subjectRepositoryProvider.overrideWithValue(FakeSubjectRepository(subjects: [_subject])),
        schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository(classes: [_playgroup])),
        syllabusTopicRepositoryProvider.overrideWithValue(topics),
        syllabusProgressRepositoryProvider.overrideWithValue(FakeSyllabusProgressRepository(checklist: _checklist)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: SyllabusScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Subject'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Computer Science').last);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Class'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Playgroup A').last);
  await tester.pumpAndSettle();

  return topics;
}

/// A syllabus belongs to a class, shared by its sections (decided
/// 2026-11-05): Computer Science for Playgroup is nobody else's.
void main() {
  testWidgets('says whose syllabus it is', (tester) async {
    await _open(tester);

    expect(find.byKey(const Key('syllabus-whose')), findsOneWidget);
    expect(find.textContaining('Playgroup syllabus'), findsOneWidget);
  });

  testWidgets('a topic from before classes says every class follows it, and the class own do not', (tester) async {
    await _open(tester);

    expect(find.byKey(const Key('topic-all-classes-7')), findsOneWidget);
    expect(find.byKey(const Key('topic-all-classes-8')), findsNothing);
  });

  testWidgets('a topic added here is filed for the class, numbered after its own topics', (tester) async {
    final topics = await _open(tester);

    await tester.tap(find.text('Add Topic'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add-topic-for')), findsOneWidget);
    expect(find.textContaining('For Playgroup'), findsOneWidget);
    // After "Tap and drag" (2), not counting the topic every class follows.
    expect(find.widgetWithText(TextFormField, '3'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Topic title'), 'Shapes on screen');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(topics.lastCreatePayload!['class_level'], -3);
    expect(topics.lastCreatePayload!['sequence_number'], 3);
  });

  testWidgets('a topic from before classes is moved to this class from Edit', (tester) async {
    final topics = await _open(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playgroup only'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(topics.lastUpdatePayload!['class_level'], -3);
  });

  testWidgets('a class topic can be put back to every class', (tester) async {
    final topics = await _open(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined).at(1));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byKey(const Key('edit-topic-class')), matching: find.text('All classes')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(topics.lastUpdatePayload!.containsKey('class_level'), isTrue);
    expect(topics.lastUpdatePayload!['class_level'], isNull);
  });

  testWidgets('saving a title alone leaves the class alone', (tester) async {
    final topics = await _open(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(topics.lastUpdatePayload!.containsKey('class_level'), isFalse);
  });
}
