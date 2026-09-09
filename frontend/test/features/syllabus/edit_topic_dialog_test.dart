import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/syllabus/application/syllabus_checklist_notifier.dart';
import 'package:edutrack_app/features/syllabus/data/models/syllabus_checklist.dart';
import 'package:edutrack_app/features/syllabus/data/models/syllabus_topic.dart';
import 'package:edutrack_app/features/syllabus/data/syllabus_progress_repository.dart';
import 'package:edutrack_app/features/syllabus/data/syllabus_topic_repository.dart';
import 'package:edutrack_app/features/syllabus/presentation/widgets/edit_topic_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_syllabus_progress_repository.dart';
import '../../support/fake_syllabus_topic_repository.dart';

const _params = SyllabusChecklistParams(classSectionId: 10, subjectId: 1);
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
const _topicItem = SyllabusChecklistItem(
  id: 5,
  title: 'Whole Numbers',
  sequenceNumber: 1,
  completed: false,
  completedByName: null,
  completedAt: null,
);

Widget wrap(FakeSyllabusTopicRepository topicFake) {
  return ProviderScope(
    overrides: [
      syllabusTopicRepositoryProvider.overrideWithValue(topicFake),
      syllabusProgressRepositoryProvider.overrideWithValue(FakeSyllabusProgressRepository(checklist: _checklist)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            ref.watch(syllabusChecklistProvider(_params));
            return Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const EditTopicDialog(topic: _topicItem, params: _params),
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

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a validation error when the title is cleared', (tester) async {
    final fake = FakeSyllabusTopicRepository(
      topics: const [
        SyllabusTopic(
          id: 5,
          schoolId: 1,
          subjectId: 1,
          subjectName: 'Mathematics',
          title: 'Whole Numbers',
          sequenceNumber: 1,
        ),
      ],
    );
    await tester.pumpWidget(wrap(fake));
    await _openDialog(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Topic title'), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Title is required'), findsOneWidget);
  });

  testWidgets('updates the topic, closes the dialog, and shows a confirmation snackbar', (tester) async {
    final fake = FakeSyllabusTopicRepository(
      topics: const [
        SyllabusTopic(
          id: 5,
          schoolId: 1,
          subjectId: 1,
          subjectName: 'Mathematics',
          title: 'Whole Numbers',
          sequenceNumber: 1,
        ),
      ],
    );
    await tester.pumpWidget(wrap(fake));
    await _openDialog(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Topic title'), 'Whole Numbers Revised');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final updated = await fake.list(subjectId: 1);
    expect(updated.single.title, 'Whole Numbers Revised');
    expect(find.byType(EditTopicDialog), findsNothing);
    expect(find.text('Topic updated.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeSyllabusTopicRepository(
      topics: const [
        SyllabusTopic(
          id: 5,
          schoolId: 1,
          subjectId: 1,
          subjectName: 'Mathematics',
          title: 'Whole Numbers',
          sequenceNumber: 1,
        ),
      ],
      failUpdateWith: const Failure(code: 'TOPIC_UPDATE_FAILED', message: 'Could not update the topic.'),
    );
    await tester.pumpWidget(wrap(fake));
    await _openDialog(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Topic title'), 'Whole Numbers Revised');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Could not update the topic.'), findsOneWidget);
    expect(find.byType(EditTopicDialog), findsOneWidget);
  });
}
