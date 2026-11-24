import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource;

import 'file_picker.dart' as browser;
import 'picked_file.dart';

/// Where a photo comes from on a phone. The web has one chooser for both.
enum PhotoSource { camera, gallery }

/// Asks the person for a photo: the browser's file chooser on the web; the
/// camera or the phone's photos on Android (image_picker, which uses the
/// system photo picker and the camera app, so the app needs no storage or
/// camera permission of its own). Null when they cancel. Swappable in tests.
typedef PhotoPicker = Future<PickedFile?> Function(PhotoSource source);

final photoPickerProvider = Provider<PhotoPicker>((ref) => pickPhoto);

Future<PickedFile?> pickPhoto(PhotoSource source) async {
  if (kIsWeb) return browser.pickFile(accept: 'image/jpeg,image/png');

  final picked = await ImagePicker().pickImage(
    source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
    // A doctor's note stays readable at this size, and the upload stays small.
    maxWidth: 2000,
    maxHeight: 2000,
    imageQuality: 85,
  );
  if (picked == null) return null;

  return PickedFile(name: picked.name, bytes: await picked.readAsBytes());
}
