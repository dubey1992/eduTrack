import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/syllabus/application/syllabus_checklist_notifier.dart';
import 'package:edutrack_app/features/syllabus/data/models/syllabus_checklist.dart';
import 'package:edutrack_app/features/syllabus/data/syllabus_progress_repository.dart';
import 'package:edutrack_app/features/syllabus/data/syllabus_topic_repository.dart';
import 'package:edutrack_app/features/syllabus/presentation/widgets/add_topic_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_syllabus_progress_repository.dart';
import '../../support/fake_syllabus_topic_repository.dart';

const _params = SyllabusChecklistParams(classSectionId: 10, subjectId: 1);
const _emptyChecklist = SyllabusChecklist(
  subjectId: 1,
  subjectName: 'Mathematics',
  classSectionId: 10,
  totalTopics: 0,
  completedTopics: 0,
  progressPercent: 0,
  topics: [],
);

// In the real app, SyllabusScreen's checklist section watches this exact
// family instance the whole time a dialog above it is open, which keeps
// this autoDispose provider alive across the dialog's await chain. This
// test stands the dialog up on its own, so it holds that same watch itself
// - otherwise the provider gets torn down mid-submit and the dialog would
// see a spurious failure that could never happen with the real screen
// behind it. See submit_report_dialog_test.dart for the original case.
Widget wrap(FakeSyllabusTopicRepository topicFake, {FakeSyllabusProgressRepository? progressFake}) {
  return ProviderScope(
    overrides: [
      syllabusTopicRepositoryProvider.overrideWithValue(topicFake),
      syllabusProgressRepositoryProvider.overrideWithValue(
        progressFake ?? FakeSyllabusProgressRepository(checklist: _emptyChecklist),
      ),
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
                  builder: (_) =>
                      const AddTopicDialog(schoolId: null, subjectId: 1, params: _params, nextSequenceNumber: 1),
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
  testWidgets('shows a validation error when the title is left empty', (tester) async {
    await tester.pumpWidget(wrap(FakeSyllabusTopicRepository()));
    await _openDialog(tester);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Title is required'), findsOneWidget);
  });

  testWidgets('creates the topic, closes the dialog, and shows a confirmation snackbar', (tester) async {
    final fake = FakeSyllabusTopicRepository();
    await tester.pumpWidget(wrap(fake));
    await _openDialog(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Topic title'), 'Whole Numbers');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(fake.lastCreatePayload, isNotNull);
    expect(fake.lastCreatePayload!['title'], 'Whole Numbers');
    expect(fake.lastCreatePayload!['sequence_number'], 1);
    expect(find.byType(AddTopicDialog), findsNothing);
    expect(find.text('Topic added.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeSyllabusTopicRepository(
      failCreateWith: const Failure(code: 'DUPLICATE_SEQUENCE', message: 'That position is already used.'),
    );
    await tester.pumpWidget(wrap(fake));
    await _openDialog(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Topic title'), 'Whole Numbers');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('That position is already used.'), findsOneWidget);
    expect(find.byType(AddTopicDialog), findsOneWidget);
  });
}
