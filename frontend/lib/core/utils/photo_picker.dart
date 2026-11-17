import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'file_picker.dart' as browser;
import 'picked_file.dart';

/// Where a photo comes from on a phone. The web has one chooser for both.
enum PhotoSource { camera, gallery }

/// Asks the person for an image: the browser's file chooser (a JPEG or PNG).
/// Null when they cancel. Swappable in tests.
///
/// This deploy carries the web chooser only. The phone apps' camera and
/// gallery picker arrives with the Family app (main), which adds
/// image_picker.
typedef PhotoPicker = Future<PickedFile?> Function(PhotoSource source);

final photoPickerProvider = Provider<PhotoPicker>((ref) => pickPhoto);

Future<PickedFile?> pickPhoto(PhotoSource source) => browser.pickFile(accept: 'image/jpeg,image/png');
