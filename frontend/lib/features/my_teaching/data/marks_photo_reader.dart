import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/photo_picker.dart';
import '../application/marks_reading.dart';
import 'marks_photo_reader_io.dart' if (dart.library.js_interop) 'marks_photo_reader_web.dart' as platform;

/// Reading a photo of a marks list (docs/mobile-apps-review.md, M12, 1.7).
///
/// Behind an interface so that tests never reach the camera or ML Kit, and
/// so the web build - where there is no on-device text recognition - simply
/// has no camera button.
abstract class MarksPhotoReader {
  /// Whether to offer the camera button at all. Says what kind of build this
  /// is; it never asks the phone anything.
  bool get isAvailable;

  /// Asks for a photo, from the camera or the phone's photos, and returns
  /// the lines of text found in it. Null when the person cancels; throws when
  /// the photo could not be read.
  Future<List<ReadLine>?> read(PhotoSource source);
}

final marksPhotoReaderProvider = Provider<MarksPhotoReader>((ref) => platform.createMarksPhotoReader());
