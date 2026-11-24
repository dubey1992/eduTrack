import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/photo_picker.dart';
import 'package:edutrack_app/core/utils/picked_file.dart';
import 'package:edutrack_app/features/teaching_reports/data/models/teaching_report.dart';
import 'package:edutrack_app/features/teaching_reports/data/teaching_report_repository.dart';
import 'package:edutrack_app/features/teaching_reports/presentation/widgets/report_photos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_photo_dio.dart';
import '../../support/fake_teaching_report_repository.dart';
import 'teaching_fixtures.dart';

/// Photos on a teaching report (docs/mobile-apps-review.md, M9, 6.6): the
/// teacher adds up to three from the camera until the report is reviewed;
/// everyone who reads the report sees them.
void main() {
  const board = ReportPhoto(id: 5, url: '/teaching-reports/1/photos/5');

  Future<(FakeTeachingReportRepository, List<TeachingReport>, List<PhotoSource>)> pump(
    WidgetTester tester, {
    required TeachingReport shown,
    bool canChange = true,
  }) async {
    final repository = FakeTeachingReportRepository(reports: [shown]);
    final changes = <TeachingReport>[];
    final asked = <PhotoSource>[];
    var current = shown;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          teachingReportRepositoryProvider.overrideWithValue(repository),
          dioClientProvider.overrideWithValue(fakePhotoDio(bytes: const [1, 2, 3])),
          photoPickerProvider.overrideWithValue((source) async {
            asked.add(source);
            return const PickedFile(name: 'board.jpg', bytes: [1, 2, 3]);
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.teacherLight(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ReportPhotos(
                report: current,
                canChange: canChange,
                onChanged: (updated) => setState(() {
                  changes.add(updated);
                  current = updated;
                }),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return (repository, changes, asked);
  }

  testWidgets('the teacher takes a photo and it joins the report', (tester) async {
    final (repository, changes, asked) = await pump(tester, shown: report());

    expect(find.textContaining('never by parents'), findsOneWidget);
    await tester.tap(find.byKey(const Key('report-photo-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-photo-camera')));
    await tester.pumpAndSettle();

    expect(asked, [PhotoSource.camera]);
    expect(repository.addedPhotos, ['board.jpg']);
    expect(changes.single.photos.length, 1);
    expect(find.text('Photo added.'), findsOneWidget);
  });

  testWidgets('three photos and the Add button goes', (tester) async {
    await pump(
      tester,
      shown: report(
        photos: const [
          board,
          ReportPhoto(id: 6, url: '/teaching-reports/1/photos/6'),
          ReportPhoto(id: 7, url: '/teaching-reports/1/photos/7'),
        ],
      ),
    );

    expect(find.byKey(const Key('report-photo-add')), findsNothing);
    expect(find.byKey(const Key('report-photo-7')), findsOneWidget);
  });

  testWidgets('removing asks first, then takes it off', (tester) async {
    final (repository, changes, _) = await pump(tester, shown: report(photos: const [board]));

    await tester.tap(find.byKey(const Key('report-photo-remove-5')));
    await tester.pumpAndSettle();
    expect(find.text('Remove this photo?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(repository.removedPhotos, [5]);
    expect(changes.single.photos, isEmpty);
  });

  testWidgets("the server's refusal is shown under the photos", (tester) async {
    final (repository, _, _) = await pump(tester, shown: report());
    repository.failPhotoWith = const Failure(
      code: 'VALIDATION_ERROR',
      message: 'The given data was invalid.',
      details: {
        'errors': {
          'photo': ['This report has been reviewed, so its photos stay as they were.'],
        },
      },
    );

    await tester.tap(find.byKey(const Key('report-photo-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-photo-gallery')));
    await tester.pumpAndSettle();

    expect(find.text('This report has been reviewed, so its photos stay as they were.'), findsOneWidget);
  });

  testWidgets('a reader who may not change them sees them only', (tester) async {
    await pump(tester, shown: report(photos: const [board]), canChange: false);

    expect(find.byKey(const Key('report-photo-5')), findsOneWidget);
    expect(find.byKey(const Key('report-photo-add')), findsNothing);
    expect(find.byKey(const Key('report-photo-remove-5')), findsNothing);
  });

  testWidgets('a photo opens full size', (tester) async {
    await pump(tester, shown: report(photos: const [board]), canChange: false);

    await tester.tap(find.byKey(const Key('report-photo-5')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('report-photo-full')), findsOneWidget);
  });

  testWidgets('no photos and nothing to change shows nothing', (tester) async {
    await pump(tester, shown: report(), canChange: false);

    expect(find.byKey(const Key('report-photos')), findsNothing);
  });

  test('a report reads its photos, and an older answer has none', () {
    final json = {
      'id': 1,
      'school_id': 1,
      'timetable_entry_id': 11,
      'teacher_id': 7,
      'report_date': '2026-10-26',
      'topic_taught': 'Fractions',
    };

    expect(TeachingReport.fromJson(json).photos, isEmpty);
    expect(
      TeachingReport.fromJson({
        ...json,
        'photos': [
          {'id': 5, 'url': '/teaching-reports/1/photos/5'},
        ],
      }).photos.single.url,
      '/teaching-reports/1/photos/5',
    );
  });
}
