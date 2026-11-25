import 'dart:io' show Platform;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource;

import '../../../core/utils/photo_picker.dart';
import '../application/marks_reading.dart';
import 'marks_photo_reader.dart';

MarksPhotoReader createMarksPhotoReader() => MlKitMarksPhotoReader();

/// Google ML Kit's on-device text recognition (Latin script). The photo is
/// read on the phone and never leaves it; nothing is uploaded.
class MlKitMarksPhotoReader implements MarksPhotoReader {
  /// Android only: ML Kit has no desktop build, and the Staff app ships on
  /// Android.
  @override
  bool get isAvailable => Platform.isAndroid;

  @override
  Future<List<ReadLine>?> read(PhotoSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
      // Big enough for handwriting to stay readable; small enough to read quickly.
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 90,
    );
    if (picked == null) return null;

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final text = await recognizer.processImage(InputImage.fromFilePath(picked.path));
      return [
        for (final block in text.blocks)
          for (final line in block.lines)
            ReadLine(
              text: line.text,
              top: line.boundingBox.top,
              bottom: line.boundingBox.bottom,
              left: line.boundingBox.left,
            ),
      ];
    } finally {
      await recognizer.close();
    }
  }
}
