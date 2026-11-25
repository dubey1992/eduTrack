import '../../../core/utils/photo_picker.dart';
import '../application/marks_reading.dart';
import 'marks_photo_reader.dart';

MarksPhotoReader createMarksPhotoReader() => const NoMarksPhotoReader();

/// The web portal has no on-device text recognition; marks are typed, or
/// uploaded as a spreadsheet, there.
class NoMarksPhotoReader implements MarksPhotoReader {
  const NoMarksPhotoReader();

  @override
  bool get isAvailable => false;

  @override
  Future<List<ReadLine>?> read(PhotoSource source) async => null;
}
