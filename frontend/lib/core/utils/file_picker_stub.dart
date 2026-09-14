import 'picked_file.dart';

/// The non-web implementation.
///
/// Reading a file off an Android device needs a storage permission and a
/// picker the app does not carry yet, so the callers hide their upload
/// buttons rather than offering something that cannot work.
bool get canPickFile => false;

Future<PickedFile?> pickFile({required String accept}) {
  throw UnsupportedError('Uploading a file is only available in the web app for now.');
}
