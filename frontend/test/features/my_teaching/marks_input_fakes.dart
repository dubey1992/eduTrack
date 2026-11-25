import 'dart:async';

import 'package:edutrack_app/core/utils/photo_picker.dart';
import 'package:edutrack_app/features/my_teaching/application/marks_reading.dart';
import 'package:edutrack_app/features/my_teaching/data/marks_photo_reader.dart';
import 'package:edutrack_app/features/my_trip/data/voice_search.dart';

/// Hears what a test says, either all at once ([hears]) or phrase by phrase
/// through [controller] when a test wants to see the sheet while listening.
class FakeMarksDictation implements VoiceSearch {
  FakeMarksDictation({this.available = true, this.hears = const [], this.controller});

  bool available;
  List<String> hears;
  StreamController<String>? controller;

  /// The phone refuses - permission denied, no recogniser - when set.
  bool refuses = false;
  int listens = 0;
  int stops = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Stream<String> listen() {
    listens++;
    if (refuses) return Stream.error(StateError('refused'));
    return controller?.stream ?? Stream.fromIterable(hears);
  }

  @override
  Future<void> stop() async {
    stops++;
    await controller?.close();
  }
}

/// Reads whatever lines a test hands it, as if from a photo.
class FakeMarksPhotoReader implements MarksPhotoReader {
  FakeMarksPhotoReader({this.isAvailable = true, this.lines = const [], this.fails = false});

  @override
  bool isAvailable;

  /// What the photo "says"; null is a cancelled camera.
  List<ReadLine>? lines;
  bool fails;
  final List<PhotoSource> asked = [];

  @override
  Future<List<ReadLine>?> read(PhotoSource source) async {
    asked.add(source);
    if (fails) throw StateError('ML Kit failed');
    return lines;
  }
}

/// Lines one under another, as a photo of a list reads.
List<ReadLine> photoLines(List<String> texts) => [
  for (var i = 0; i < texts.length; i++) ReadLine(text: texts[i], top: i * 40.0, bottom: i * 40.0 + 20, left: 0),
];
