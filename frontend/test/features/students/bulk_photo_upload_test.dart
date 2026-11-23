import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/picked_file.dart';
import 'package:edutrack_app/features/students/application/bulk_photo_upload_notifier.dart';
import 'package:edutrack_app/features/students/data/models/photo_import.dart';
import 'package:edutrack_app/features/students/data/student_photo_import_repository.dart';
import 'package:edutrack_app/features/students/presentation/bulk_photo_upload_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Student photos in bulk (docs/student-photos.md, P2): what each file
/// matches, sending in small batches, carrying on after a failed batch, and
/// the dialog around it.

const _mb = 1024 * 1024;

/// Answers the preview from a fixed table of admission numbers, and stores
/// what it is sent.
class FakePhotoImportRepository implements StudentPhotoImportRepository {
  FakePhotoImportRepository({this.withPhoto = const {}, this.failPreview, this.failBatches = const {}});

  /// Admission numbers (lower case) of students who already have a photo.
  final Set<String> withPhoto;
  final Failure? failPreview;

  /// Which batches, counted from 1, fail once.
  final Set<int> failBatches;

  final List<List<String>> batches = [];
  int _attempts = 0;

  static const _roll = {'adm-1': 'Aarav Sharma', 'adm-2': 'Bina Kapoor', 'adm-3': 'Chetan Rao'};

  @override
  Future<List<PhotoPreviewRow>> preview(List<String> fileNames, {int? schoolId}) async {
    if (failPreview != null) throw failPreview!;

    return [
      for (final name in fileNames)
        if (!name.endsWith('.jpg'))
          PhotoPreviewRow(fileName: name, status: PhotoMatchStatus.notAnImage, reason: 'Only JPEG and PNG.')
        else if (_roll[name.split('.').first.toLowerCase()] case final student?)
          PhotoPreviewRow(
            fileName: name,
            status: withPhoto.contains(name.split('.').first.toLowerCase())
                ? PhotoMatchStatus.replace
                : PhotoMatchStatus.newPhoto,
            student: PhotoMatchStudent(
              id: 1,
              name: student,
              admissionNumber: name.split('.').first,
              classSectionName: 'Grade 8 A',
              hasPhoto: false,
            ),
          )
        else
          PhotoPreviewRow(fileName: name, status: PhotoMatchStatus.unmatched, reason: 'No student has this number.'),
    ];
  }

  @override
  Future<List<PhotoUploadResult>> upload(List<({String name, List<int> bytes})> files, {int? schoolId}) async {
    _attempts++;
    if (failBatches.contains(_attempts)) throw Failure.network();

    batches.add([for (final file in files) file.name]);
    return [
      for (final file in files)
        PhotoUploadResult(
          fileName: file.name,
          status: withPhoto.contains(file.name.split('.').first.toLowerCase())
              ? PhotoUploadStatus.replaced
              : PhotoUploadStatus.added,
          studentId: 1,
        ),
    ];
  }
}

ChosenFile _file(String name, {int size = 1000, bool unreadable = false}) =>
    ChosenFile(name: name, size: size, read: () async => unreadable ? throw StateError('gone') : List.filled(4, 1));

/// [count] matched files, named like real ones: adm-1.jpg repeated would be
/// a duplicate, so the fake matches by the part before the first dot.
List<ChosenFile> _many(int count, {int size = 1000}) => [
  for (var i = 0; i < count; i++) _file('ADM-${(i % 3) + 1}.$i.jpg', size: size),
];

void main() {
  ProviderContainer container(FakePhotoImportRepository fake) {
    final container = ProviderContainer(overrides: [studentPhotoImportRepositoryProvider.overrideWithValue(fake)]);
    addTearDown(container.dispose);
    // Kept alive for the test: the provider is autoDispose.
    container.listen(bulkPhotoUploadProvider, (_, _) {});
    return container;
  }

  group('checking the names', () {
    test('each file is matched, and nothing is sent but the names', () async {
      final fake = FakePhotoImportRepository(withPhoto: {'adm-2'});
      final c = container(fake);

      await c.read(bulkPhotoUploadProvider.notifier).check([
        _file('ADM-1.jpg'),
        _file('ADM-2.jpg'),
        _file('NOBODY.jpg'),
        _file('notes.pdf'),
      ]);

      final state = c.read(bulkPhotoUploadProvider);
      expect(state.step, BulkPhotoStep.preview);
      expect(state.rows.map((row) => row.status), [
        PhotoMatchStatus.newPhoto,
        PhotoMatchStatus.replace,
        PhotoMatchStatus.unmatched,
        PhotoMatchStatus.notAnImage,
      ]);
      expect(state.toSend, [0, 1]);
      expect(state.heldBack, 2);
      expect(fake.batches, isEmpty);
    });

    test('a photo over 5 MB is held back before it is sent', () async {
      final c = container(FakePhotoImportRepository());

      await c.read(bulkPhotoUploadProvider.notifier).check([_file('ADM-1.jpg', size: 5 * _mb + 1)]);

      final row = c.read(bulkPhotoUploadProvider).rows.single;
      expect(row.status, PhotoMatchStatus.tooLarge);
      expect(row.reason, 'The photo must be 5 MB or smaller.');
    });

    test("a refused check goes back to choosing, with the server's reason", () async {
      final c = container(
        FakePhotoImportRepository(
          failPreview: const Failure(
            code: 'VALIDATION_ERROR',
            message: 'The given data was invalid.',
            details: {
              'errors': {
                'school_id': ['The school id field is required.'],
              },
            },
          ),
        ),
      );

      await c.read(bulkPhotoUploadProvider.notifier).check([_file('ADM-1.jpg')]);

      final state = c.read(bulkPhotoUploadProvider);
      expect(state.step, BulkPhotoStep.choose);
      expect(state.error, 'The school id field is required.');
    });

    test('an empty choice changes nothing', () async {
      final c = container(FakePhotoImportRepository());

      await c.read(bulkPhotoUploadProvider.notifier).check(const []);

      expect(c.read(bulkPhotoUploadProvider).step, BulkPhotoStep.choose);
    });
  });

  group('sending', () {
    test('at most ten files go in one request', () async {
      final fake = FakePhotoImportRepository();
      final c = container(fake);
      final notifier = c.read(bulkPhotoUploadProvider.notifier);
      await notifier.check(_many(23));

      await notifier.upload();

      expect(fake.batches.map((batch) => batch.length), [10, 10, 3]);
      final state = c.read(bulkPhotoUploadProvider);
      expect(state.step, BulkPhotoStep.done);
      expect(state.sent, 23);
      expect(state.count(PhotoUploadStatus.added), 23);
    });

    test('and about 10 MB, so big photos go a few at a time', () async {
      final fake = FakePhotoImportRepository();
      final c = container(fake);
      final notifier = c.read(bulkPhotoUploadProvider.notifier);
      await notifier.check(_many(5, size: 4 * _mb));

      await notifier.upload();

      expect(fake.batches.map((batch) => batch.length), [2, 2, 1]);
    });

    test('held-back files are never sent', () async {
      final fake = FakePhotoImportRepository();
      final c = container(fake);
      final notifier = c.read(bulkPhotoUploadProvider.notifier);
      await notifier.check([_file('ADM-1.jpg'), _file('NOBODY.jpg'), _file('x.pdf')]);

      await notifier.upload();

      expect(fake.batches, [
        ['ADM-1.jpg'],
      ]);
    });

    test('a failed batch pauses, keeps what was sent, and Try again sends only the rest', () async {
      final fake = FakePhotoImportRepository(failBatches: {2});
      final c = container(fake);
      final notifier = c.read(bulkPhotoUploadProvider.notifier);
      await notifier.check(_many(15));

      await notifier.upload();

      var state = c.read(bulkPhotoUploadProvider);
      expect(state.step, BulkPhotoStep.paused);
      expect(state.sent, 10);
      expect(state.error, Failure.network().message);

      await notifier.upload();

      state = c.read(bulkPhotoUploadProvider);
      expect(state.step, BulkPhotoStep.done);
      expect(fake.batches.map((batch) => batch.length), [10, 5]);
      expect(state.results, hasLength(15));
    });

    test('a file that cannot be read is reported and the others still go', () async {
      final fake = FakePhotoImportRepository();
      final c = container(fake);
      final notifier = c.read(bulkPhotoUploadProvider.notifier);
      await notifier.check([_file('ADM-1.jpg', unreadable: true), _file('ADM-2.jpg')]);

      await notifier.upload();

      final state = c.read(bulkPhotoUploadProvider);
      expect(fake.batches, [
        ['ADM-2.jpg'],
      ]);
      final skipped = state.results.singleWhere((result) => result.status == PhotoUploadStatus.skipped);
      expect((skipped.fileName, skipped.reason), ('ADM-1.jpg', 'This file could not be read.'));
    });
  });

  group('the dialog', () {
    Widget app(FakePhotoImportRepository fake, List<ChosenFile> files, {VoidCallback? onUploaded}) {
      return ProviderScope(
        overrides: [
          studentPhotoImportRepositoryProvider.overrideWithValue(fake),
          photosPickerProvider.overrideWithValue(() async => files),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => BulkPhotoUploadDialog(onUploaded: onUploaded),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> openAndChoose(WidgetTester tester) async {
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bulk-photos-choose')));
      await tester.pumpAndSettle();
    }

    testWidgets('explains how to name the photos before anything is chosen', (tester) async {
      await tester.pumpWidget(app(FakePhotoImportRepository(), const []));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining("Name each photo after the student's admission number"), findsOneWidget);
      expect(find.textContaining('SPHS-26-01A01.jpg is SPHS/26/01A01'), findsOneWidget);
    });

    testWidgets('the check shows what will happen, problems first, and counts what will go', (tester) async {
      await tester.pumpWidget(
        app(FakePhotoImportRepository(withPhoto: {'adm-2'}), [
          _file('ADM-1.jpg'),
          _file('ADM-2.jpg'),
          _file('NOBODY.jpg'),
        ]),
      );
      await openAndChoose(tester);

      expect(find.text('1 new'), findsOneWidget);
      expect(find.text('1 replace a photo'), findsOneWidget);
      expect(find.text('1 held back'), findsOneWidget);
      expect(find.text('No student has this number.'), findsOneWidget);
      expect(find.textContaining('Aarav Sharma · ADM-1 · Grade 8 A'), findsOneWidget);
      expect(find.textContaining('replaces the photo'), findsOneWidget);
      expect(find.text('Upload 2 photos'), findsOneWidget);
      // Held back first: it is what somebody has to act on.
      final titles = tester.widgetList<ListTile>(find.byType(ListTile)).map((tile) => (tile.title as Text).data);
      expect(titles.first, 'NOBODY.jpg');
    });

    testWidgets('with nothing to send the upload button is off', (tester) async {
      await tester.pumpWidget(app(FakePhotoImportRepository(), [_file('NOBODY.jpg')]));
      await openAndChoose(tester);

      final button = tester.widget<FilledButton>(find.byKey(const Key('bulk-photos-upload')));
      expect(button.onPressed, isNull);
      // A count of nothing is not shown.
      expect(find.text('0 new'), findsNothing);
      expect(find.text('0 replace a photo'), findsNothing);
      expect(find.text('1 held back'), findsOneWidget);
    });

    testWidgets('uploading ends with what happened, and Done refreshes the list', (tester) async {
      var refreshed = 0;
      await tester.pumpWidget(
        app(FakePhotoImportRepository(withPhoto: {'adm-2'}), [
          _file('ADM-1.jpg'),
          _file('ADM-2.jpg'),
          _file('NOBODY.jpg'),
        ], onUploaded: () => refreshed++),
      );
      await openAndChoose(tester);

      await tester.tap(find.byKey(const Key('bulk-photos-upload')));
      await tester.pumpAndSettle();

      expect(find.text('1 added'), findsOneWidget);
      expect(find.text('1 replaced'), findsOneWidget);
      expect(find.text('1 not uploaded'), findsOneWidget);
      expect(find.text('NOBODY.jpg'), findsOneWidget);

      await tester.tap(find.byKey(const Key('bulk-photos-done')));
      await tester.pumpAndSettle();

      expect(refreshed, 1);
      expect(find.byType(BulkPhotoUploadDialog), findsNothing);
    });

    testWidgets('a failed batch offers Try again, which finishes the job', (tester) async {
      final fake = FakePhotoImportRepository(failBatches: {1});
      await tester.pumpWidget(app(fake, [_file('ADM-1.jpg')]));
      await openAndChoose(tester);

      await tester.tap(find.byKey(const Key('bulk-photos-upload')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bulk-photos-error')), findsOneWidget);
      expect(find.text('Uploaded 0 of 1 photos.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('bulk-photos-retry')));
      await tester.pumpAndSettle();

      expect(find.text('1 added'), findsOneWidget);
    });

    testWidgets('Choose other photos starts again', (tester) async {
      await tester.pumpWidget(app(FakePhotoImportRepository(), [_file('ADM-1.jpg')]));
      await openAndChoose(tester);

      await tester.tap(find.byKey(const Key('bulk-photos-choose-again')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bulk-photos-choose')), findsOneWidget);
    });
  });
}
