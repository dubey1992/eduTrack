import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/photo_picker.dart';
import '../../assessments/data/models/assessment_sheet.dart';
import '../data/marks_dictation.dart';
import '../data/marks_photo_reader.dart';
import 'marks_reading.dart';

/// Marks by voice or from a photo on the marks sheet (docs/mobile-apps-review.md,
/// M12, 1.7): listening, or reading the photo, and what went wrong. What
/// was read goes back to the screen for the teacher to check; nothing here
/// writes to the sheet.
final marksInputProvider = NotifierProvider.autoDispose<MarksInputNotifier, MarksInputState>(MarksInputNotifier.new);

/// Whether to show the microphone: a phone build, not the web.
final marksVoiceAvailableProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(marksDictationProvider).isAvailable(),
);

/// Whether to show the camera: Android, where ML Kit runs.
final marksPhotoAvailableProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(marksPhotoReaderProvider).isAvailable,
);

enum MarksInputStatus { idle, listening, readingPhoto }

enum MarksInputProblem {
  /// Microphone permission refused, or no recogniser on the phone.
  cannotListen,

  /// Listening ended with nothing that looks like a mark.
  nothingHeard,

  /// ML Kit failed on the photo.
  cannotReadPhoto,

  /// The photo was read, but nothing in it looks like a mark.
  nothingInPhoto,
}

class MarksInputState {
  const MarksInputState({this.status = MarksInputStatus.idle, this.heard = '', this.problem});

  final MarksInputStatus status;

  /// The words heard so far, shown while the teacher speaks.
  final String heard;
  final MarksInputProblem? problem;

  bool get isBusy => status != MarksInputStatus.idle;
}

class MarksInputNotifier extends Notifier<MarksInputState> {
  @override
  MarksInputState build() => const MarksInputState();

  /// Listens until the teacher pauses, then reads the marks heard. Null when
  /// nothing came of it, with [MarksInputState.problem] saying why.
  ///
  /// Marks said without a roll fill the sheet from the first student with
  /// no mark, so a long class can be read out in several goes.
  Future<MarksReading?> dictate(AssessmentSheet sheet) async {
    if (state.isBusy) return null;
    state = const MarksInputState(status: MarksInputStatus.listening);

    var heard = '';
    try {
      await for (final words in ref.read(marksDictationProvider).listen()) {
        heard = words;
        if (ref.mounted) state = MarksInputState(status: MarksInputStatus.listening, heard: words);
      }
    } on Object catch (error) {
      developer.log('Marks dictation failed', name: 'marks', error: error);
      if (ref.mounted) state = const MarksInputState(problem: MarksInputProblem.cannotListen);
      return null;
    }
    if (!ref.mounted) return null;

    final reading = MarksParser(sheet.entries).fromSpeech(heard, startAt: MarksParser.firstUnmarked(sheet.entries));
    if (reading.isEmpty) {
      state = const MarksInputState(problem: MarksInputProblem.nothingHeard);
      return null;
    }
    state = const MarksInputState();
    return reading;
  }

  /// Stops listening early; what was heard so far is still read.
  Future<void> stopListening() => ref.read(marksDictationProvider).stop();

  /// Takes or chooses a photo and reads the marks in it. Null when the
  /// teacher cancelled, or nothing came of it (then with a problem).
  Future<MarksReading?> readPhoto(AssessmentSheet sheet, PhotoSource source) async {
    if (state.isBusy) return null;
    state = const MarksInputState(status: MarksInputStatus.readingPhoto);

    final List<ReadLine>? lines;
    try {
      lines = await ref.read(marksPhotoReaderProvider).read(source);
    } on Object catch (error) {
      developer.log('Reading the marks photo failed', name: 'marks', error: error);
      if (ref.mounted) state = const MarksInputState(problem: MarksInputProblem.cannotReadPhoto);
      return null;
    }
    if (!ref.mounted) return null;
    if (lines == null) {
      state = const MarksInputState();
      return null;
    }

    final reading = MarksParser(sheet.entries).fromPhoto(lines);
    if (reading.isEmpty) {
      state = const MarksInputState(problem: MarksInputProblem.nothingInPhoto);
      return null;
    }
    state = const MarksInputState();
    return reading;
  }

  void clearProblem() {
    if (state.problem != null) state = const MarksInputState();
  }
}
