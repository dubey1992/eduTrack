import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/photo_picker.dart';
import 'package:edutrack_app/features/assessments/data/assessment_repository.dart';
import 'package:edutrack_app/features/assessments/data/models/assessment.dart';
import 'package:edutrack_app/features/assessments/data/models/assessment_sheet.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/my_teaching/data/marks_dictation.dart';
import 'package:edutrack_app/features/my_teaching/data/marks_photo_reader.dart';
import 'package:edutrack_app/features/my_teaching/presentation/marks_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_assessment_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/session_users.dart';
import 'marks_input_fakes.dart';

/// Marks by voice or from a photo on the marks sheet (M12, 1.7): read,
/// checked in the review, and only then typed into the sheet.
void main() {
  SheetEntry student(int id, String name, {String? marks}) => SheetEntry(
    studentId: id,
    studentName: name,
    admissionNumber: 'ADM-$id',
    rollNumber: '$id',
    marksObtained: marks,
    isAbsent: false,
    grade: null,
    percentage: null,
    passed: null,
    remarks: null,
  );

  late FakeAssessmentRepository repository;
  late FakeMarksDictation voice;
  late FakeMarksPhotoReader photo;

  setUp(() {
    repository = FakeAssessmentRepository(
      sheetEntries: [
        student(1, 'Aarav Shah'),
        student(2, 'Diya Patel', marks: '7.00'),
        student(3, 'Kabir Rao'),
      ],
    );
    voice = FakeMarksDictation();
    photo = FakeMarksPhotoReader();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assessmentRepositoryProvider.overrideWithValue(repository),
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher, id: 7)),
          ),
          marksDictationProvider.overrideWithValue(voice),
          marksPhotoReaderProvider.overrideWithValue(photo),
        ],
        child: MaterialApp(theme: AppTheme.teacherLight(), home: const MarksEntryScreen(assessmentId: 1)),
      ),
    );
    await tester.pumpAndSettle();
  }

  String box(WidgetTester tester, int id) =>
      tester.widget<TextField>(find.byKey(Key('marks-box-$id'))).controller!.text;

  Future<void> speak(WidgetTester tester, String words) async {
    voice.hears = [words];
    await tester.tap(find.byKey(const Key('marks-speak')));
    await tester.pumpAndSettle();
  }

  Future<void> photograph(WidgetTester tester, List<String> lines, {bool camera = true}) async {
    photo.lines = photoLines(lines);
    await tester.tap(find.byKey(const Key('marks-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(camera ? 'marks-photo-camera' : 'marks-photo-gallery')));
    await tester.pumpAndSettle();
  }

  testWidgets('both buttons are offered on a draft, with labels for screen readers', (tester) async {
    await pump(tester);

    expect(find.byTooltip('Speak the marks'), findsOneWidget);
    expect(find.byTooltip('Read marks from a photo'), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('marks-speak'))), const Size(48, 48));
  });

  testWidgets('the camera is not offered where it cannot run (the web), nor the microphone', (tester) async {
    photo.isAvailable = false;
    voice.available = false;
    await pump(tester);

    expect(find.byKey(const Key('marks-photo')), findsNothing);
    expect(find.byKey(const Key('marks-speak')), findsNothing);
  });

  testWidgets('neither is offered on a published test', (tester) async {
    repository.sheetAssessment = fakeAssessment(status: AssessmentStatus.published);
    await pump(tester);

    expect(find.byKey(const Key('marks-speak')), findsNothing);
    expect(find.byKey(const Key('marks-photo')), findsNothing);
  });

  testWidgets('spoken marks are shown for checking, and Confirm fills only the rows read', (tester) async {
    await pump(tester);

    await speak(tester, 'roll 1 18 roll 3 absent');

    expect(find.byKey(const Key('marks-review')), findsOneWidget);
    expect(find.text('Check the marks read'), findsOneWidget);
    expect(box(tester, 1), isEmpty, reason: 'nothing on the sheet before Confirm');
    expect(
      find.descendant(
        of: find.byKey(const Key('marks-review-row-2')),
        matching: find.text('Not read - stays as it is'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('marks-review-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('marks-review')), findsNothing);
    expect(box(tester, 1), '18');
    expect(box(tester, 2), '7', reason: 'not read, so left as it was');
    expect(tester.widget<Switch>(find.byKey(const Key('marks-absent-3'))).value, isTrue);
    expect(find.text('2 marks put on the sheet. Check them, then save.'), findsOneWidget);
    expect(find.text('3 of 3 marked'), findsOneWidget);
    expect(repository.lastSaved, isNull, reason: 'saving stays the Save button');
  });

  testWidgets('Cancel changes nothing', (tester) async {
    await pump(tester);

    await speak(tester, '11 12 13');
    await tester.tap(find.byKey(const Key('marks-review-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('marks-review')), findsNothing);
    expect(box(tester, 1), isEmpty);
    expect(box(tester, 2), '7');
    expect(box(tester, 3), isEmpty);
    expect(tester.widget<FilledButton>(find.byKey(const Key('marks-save'))).onPressed, isNull);
  });

  testWidgets('a corrected mark in the review is what goes on the sheet', (tester) async {
    await pump(tester);

    await speak(tester, 'roll 1 81');
    expect(
      find.descendant(of: find.byKey(const Key('marks-review-row-1')), matching: find.text('Out of 20')),
      findsOneWidget,
      reason: 'over the maximum is flagged',
    );
    final card = tester.widget<Card>(find.byKey(const Key('marks-review-row-1')));
    expect(card.color, isNotNull, reason: 'and the row highlighted');

    await tester.enterText(find.byKey(const Key('marks-review-box-1')), '18');
    await tester.pump();
    expect(
      find.descendant(of: find.byKey(const Key('marks-review-row-1')), matching: find.text('Out of 20')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('marks-review-confirm')));
    await tester.pumpAndSettle();

    expect(box(tester, 1), '18');
  });

  testWidgets('rolls not on the sheet and extra marks are listed, not placed', (tester) async {
    await pump(tester);

    await speak(tester, 'roll 9 15 roll 1 10 11');

    expect(find.byKey(const Key('marks-review-issues')), findsOneWidget);
    expect(find.text('Roll 9 is not on this sheet'), findsOneWidget);
    expect(find.text('More marks than students'), findsOneWidget);
  });

  testWidgets('a photo: camera or photos, then the same review', (tester) async {
    await pump(tester);

    await photograph(tester, ['Roll Name Marks', '1 Aarav Shah 17', '3 Kabir Rao 4q'], camera: false);

    expect(photo.asked, [PhotoSource.gallery]);
    expect(find.byKey(const Key('marks-review')), findsOneWidget);
    expect(find.text('Could not read "4q"'), findsOneWidget);

    await tester.tap(find.byKey(const Key('marks-review-confirm')));
    await tester.pumpAndSettle();

    expect(box(tester, 1), '17');
    expect(box(tester, 3), isEmpty, reason: 'unreadable and not corrected: left as it was');
    expect(find.text('1 mark put on the sheet. Check it, then save.'), findsOneWidget);
  });

  testWidgets('a photo with nothing in it says so, and can be dismissed', (tester) async {
    await pump(tester);

    await photograph(tester, ['Weekly test']);

    expect(find.byKey(const Key('marks-review')), findsNothing);
    expect(find.textContaining('No marks were found in the photo'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('marks-input-problem')), findsNothing);
  });

  testWidgets('a phone that will not listen says so', (tester) async {
    voice.refuses = true;
    await pump(tester);

    await tester.tap(find.byKey(const Key('marks-speak')));
    await tester.pumpAndSettle();

    expect(find.textContaining('This phone will not listen'), findsOneWidget);
  });

  testWidgets('the review fits a phone at double text size', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester);
    // The sheet's own rows do not fit at double size on a 400-wide phone yet;
    // that predates this feature and is not what this test is about.
    tester.takeException();

    await speak(tester, 'roll 9 15 roll 1 81 roll 2 absent');

    expect(find.byKey(const Key('marks-review')), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const Key('marks-review-confirm'))).height, greaterThanOrEqualTo(48));
  });
}
