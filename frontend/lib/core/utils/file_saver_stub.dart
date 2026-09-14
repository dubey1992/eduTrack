/// The non-web implementation.
///
/// Saving a file on Android needs a storage permission and a path, which the
/// app does not ask for yet. Throwing here - with a message a user can read -
/// keeps the button honest instead of appearing to work and doing nothing.
void saveBytes({required String fileName, required List<int> bytes, required String mimeType}) {
  throw UnsupportedError('Downloading a report is only available in the web app for now.');
}
