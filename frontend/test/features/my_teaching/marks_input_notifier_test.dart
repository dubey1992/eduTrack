import 'dart:async';

import 'package:edutrack_app/core/utils/photo_picker.dart';
import 'package:edutrack_app/features/assessments/data/models/assessment_sheet.dart';
import 'package:edutrack_app/features/my_teaching/application/marks_input_notifier.dart';
import 'package:edutrack_app/features/my_teaching/application/marks_reading.dart';
import 'package:edutrack_app/features/my_teaching/data/marks_dictation.dart';
import 'package:edutrack_app/features/my_teaching/data/marks_photo_reader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_assessment_repository.dart';
import 'marks_input_fakes.dart';

/// Listening for marks and reading a photo of them (M12, 1.7).
void main() {
  SheetEntry student(int id, {String? marks}) => SheetEntry(
    studentId: id,
    studentName: 'Student $id',
    admissionNumber: 'ADM-$id',
    rollNumber: '$id',
    marksObtained: marks,
    isAbsent: false,
    grade: null,
    percentage: null,
    passed: null,
    remarks: null,
  );

  final sheet = AssessmentSheet(
    assessment: fakeAssessment(),
    entries: [
      student(1, marks: '15'),
      student(2),
      student(3),
    ],
  );

  late FakeMarksDictation voice;
  late FakeMarksPhotoReader photo;

  ProviderContainer container() {
    final container = ProviderContainer(
      overrides: [marksDictationProvider.overrideWithValue(voice), marksPhotoReaderProvider.overrideWithValue(photo)],
    );
    addTearDown(container.dispose);
    // Kept alive for the test: the provider is autoDispose.
    container.listen(marksInputProvider, (_, _) {});
    return container;
  }

  setUp(() {
    voice = FakeMarksDictation();
    photo = FakeMarksPhotoReader();
  });

  group('voice', () {
    test('reads the last thing heard, from the first student without a mark', () async {
      voice.hears = ['12', '12 14'];
      final c = container();

      final reading = await c.read(marksInputProvider.notifier).dictate(sheet);

      expect(reading!.byStudent, {2: const ReadMark.mark('12'), 3: const ReadMark.mark('14')});
      expect(c.read(marksInputProvider).status, MarksInputStatus.idle);
      expect(c.read(marksInputProvider).problem, isNull);
    });

    test('shows the words while listening, and Stop ends it', () async {
      voice.controller = StreamController<String>();
      final c = container();

      final done = c.read(marksInputProvider.notifier).dictate(sheet);
      voice.controller!.add('roll 3');
      await Future<void>.delayed(Duration.zero);
      expect(c.read(marksInputProvider).status, MarksInputStatus.listening);
      expect(c.read(marksInputProvider).heard, 'roll 3');

      voice.controller!.add('roll 3 18');
      await c.read(marksInputProvider.notifier).stopListening();
      final reading = await done;

      expect(voice.stops, 1);
      expect(reading!.byStudent, {3: const ReadMark.mark('18')});
    });

    test('a phone that will not listen says so', () async {
      voice.refuses = true;
      final c = container();

      expect(await c.read(marksInputProvider.notifier).dictate(sheet), isNull);
      expect(c.read(marksInputProvider).problem, MarksInputProblem.cannotListen);
    });

    test('nothing heard says so, and the problem can be dismissed', () async {
      voice.hears = ['hello'];
      final c = container();

      expect(await c.read(marksInputProvider.notifier).dictate(sheet), isNull);
      expect(c.read(marksInputProvider).problem, MarksInputProblem.nothingHeard);

      c.read(marksInputProvider.notifier).clearProblem();
      expect(c.read(marksInputProvider).problem, isNull);
    });

    test('a second tap while listening does nothing', () async {
      voice.controller = StreamController<String>();
      final c = container();

      final first = c.read(marksInputProvider.notifier).dictate(sheet);
      expect(await c.read(marksInputProvider.notifier).dictate(sheet), isNull);
      expect(voice.listens, 1);

      await voice.controller!.close();
      await first;
    });
  });

  group('photo', () {
    test('reads the lines of the photo against the sheet, from the top', () async {
      photo.lines = photoLines(['2 Diya 14', '18']);
      final c = container();

      final reading = await c.read(marksInputProvider.notifier).readPhoto(sheet, PhotoSource.camera);

      expect(photo.asked, [PhotoSource.camera]);
      expect(reading!.byStudent, {2: const ReadMark.mark('14'), 1: const ReadMark.mark('18')});
      expect(c.read(marksInputProvider).isBusy, isFalse);
    });

    test('a cancelled camera is no problem', () async {
      photo.lines = null;
      final c = container();

      expect(await c.read(marksInputProvider.notifier).readPhoto(sheet, PhotoSource.gallery), isNull);
      expect(c.read(marksInputProvider).problem, isNull);
    });

    test('a photo that cannot be read says so', () async {
      photo.fails = true;
      final c = container();

      expect(await c.read(marksInputProvider.notifier).readPhoto(sheet, PhotoSource.camera), isNull);
      expect(c.read(marksInputProvider).problem, MarksInputProblem.cannotReadPhoto);
    });

    test('a photo with no marks in it says so', () async {
      photo.lines = photoLines(['Weekly test']);
      final c = container();

      expect(await c.read(marksInputProvider.notifier).readPhoto(sheet, PhotoSource.camera), isNull);
      expect(c.read(marksInputProvider).problem, MarksInputProblem.nothingInPhoto);
    });
  });

  test('which buttons to offer follows the build', () async {
    voice.available = false;
    photo.isAvailable = false;
    final c = container();

    expect(await c.read(marksVoiceAvailableProvider.future), isFalse);
    expect(c.read(marksPhotoAvailableProvider), isFalse);
  });
}
